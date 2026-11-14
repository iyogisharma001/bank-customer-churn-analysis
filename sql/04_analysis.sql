-- =====================================================================
-- Bank Customer Churn Analysis | 04_analysis.sql
-- Purpose : Answer the business questions. Every query reads from
--           vw_customer_360 so SQL and Excel use identical logic.
--
-- Churn rate = churned customers / total customers.
-- Because exited is 0/1, SUM(exited) = number churned and
-- SUM(exited) / COUNT(*) = churn rate.
-- =====================================================================
USE bank_churn;

-- =====================================================================
-- Q1. HEADLINE KPIs
-- Business question: How big is the churn problem?
-- =====================================================================
SELECT
    COUNT(*)                                                     AS total_customers,
    SUM(exited)                                                  AS churned_customers,
    ROUND(100.0 * SUM(exited) / COUNT(*), 2)                     AS churn_rate_pct,
    ROUND(SUM(balance), 0)                                       AS total_balance,
    ROUND(SUM(CASE WHEN exited = 1 THEN balance ELSE 0 END), 0)  AS balance_lost,
    ROUND(100.0 * SUM(CASE WHEN exited = 1 THEN balance ELSE 0 END)
                / SUM(balance), 2)                               AS pct_balance_lost
FROM vw_customer_360;

-- =====================================================================
-- Q2. CHURNED vs RETAINED PROFILE
-- Business question: On average, how do customers who left differ
-- from those who stayed?
-- =====================================================================
SELECT
    churn_status,
    COUNT(*)                                   AS customers,
    ROUND(AVG(age), 1)                         AS avg_age,
    ROUND(AVG(credit_score), 0)                AS avg_credit_score,
    ROUND(AVG(tenure_years), 1)                AS avg_tenure_yrs,
    ROUND(AVG(balance), 0)                     AS avg_balance,
    ROUND(AVG(num_products), 2)                AS avg_products,
    ROUND(100.0 * AVG(is_active_member), 1)    AS pct_active,
    ROUND(100.0 * AVG(gender = 'Female'), 1)   AS pct_female,
    ROUND(100.0 * AVG(geography = 'Germany'), 1) AS pct_germany,
    ROUND(AVG(estimated_salary), 0)            AS avg_salary
FROM vw_customer_360
GROUP BY churn_status
ORDER BY churn_status;

-- =====================================================================
-- Q3. CHURN PROFILE ACROSS EVERY DIMENSION (one result set)
-- Business question: Which attributes separate high-churn from
-- low-churn customers?
-- Techniques: CTEs, UNION ALL, CROSS JOIN, RANK() OVER (PARTITION BY)
-- Lift = segment churn rate / bank churn rate
--        (lift 1.60 = 60% more likely to churn than the average customer)
-- =====================================================================
WITH overall AS (
    SELECT SUM(exited) / COUNT(*) AS base_rate
    FROM vw_customer_360
),
profile AS (
    SELECT 'Geography' AS dimension, geography AS segment,
           COUNT(*) AS customers, SUM(exited) AS churned
    FROM vw_customer_360 GROUP BY geography
    UNION ALL
    SELECT 'Gender', gender, COUNT(*), SUM(exited)
    FROM vw_customer_360 GROUP BY gender
    UNION ALL
    SELECT 'Age band', age_band, COUNT(*), SUM(exited)
    FROM vw_customer_360 GROUP BY age_band
    UNION ALL
    SELECT 'Products held', CAST(num_products AS CHAR), COUNT(*), SUM(exited)
    FROM vw_customer_360 GROUP BY num_products
    UNION ALL
    SELECT 'Activity', activity_status, COUNT(*), SUM(exited)
    FROM vw_customer_360 GROUP BY activity_status
    UNION ALL
    SELECT 'Balance band', balance_band, COUNT(*), SUM(exited)
    FROM vw_customer_360 GROUP BY balance_band
    UNION ALL
    SELECT 'Credit band', credit_band, COUNT(*), SUM(exited)
    FROM vw_customer_360 GROUP BY credit_band
    UNION ALL
    SELECT 'Tenure band', tenure_band, COUNT(*), SUM(exited)
    FROM vw_customer_360 GROUP BY tenure_band
    UNION ALL
    SELECT 'Credit card', IF(has_credit_card = 1, 'Has card', 'No card'),
           COUNT(*), SUM(exited)
    FROM vw_customer_360 GROUP BY has_credit_card
)
SELECT
    p.dimension,
    p.segment,
    p.customers,
    p.churned,
    ROUND(100 * p.churned / p.customers, 1)            AS churn_rate_pct,
    ROUND((p.churned / p.customers) / o.base_rate, 2)  AS lift_vs_bank,
    RANK() OVER (PARTITION BY p.dimension
                 ORDER BY p.churned / p.customers DESC) AS rank_in_dimension
FROM profile p
CROSS JOIN overall o
ORDER BY p.dimension, rank_in_dimension;

-- =====================================================================
-- Q4. COUNTRY DEEP-DIVE (SQL cross-tab with conditional aggregation)
-- Business question: Why is one country different? Is it activity,
-- gender, or balance mix?
-- Technique: CASE inside aggregate functions = a pivot table in SQL
-- =====================================================================
SELECT
    geography,
    COUNT(*)                                                         AS customers,
    ROUND(100.0 * SUM(exited) / COUNT(*), 1)                         AS churn_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN is_active_member = 1 THEN exited END)
                / SUM(is_active_member = 1), 1)                      AS active_churn_pct,
    ROUND(100.0 * SUM(CASE WHEN is_active_member = 0 THEN exited END)
                / SUM(is_active_member = 0), 1)                      AS inactive_churn_pct,
    ROUND(100.0 * SUM(CASE WHEN gender = 'Female' THEN exited END)
                / SUM(gender = 'Female'), 1)                         AS female_churn_pct,
    ROUND(100.0 * SUM(CASE WHEN gender = 'Male' THEN exited END)
                / SUM(gender = 'Male'), 1)                           AS male_churn_pct,
    ROUND(100.0 * SUM(balance = 0) / COUNT(*), 1)                    AS pct_zero_balance,
    ROUND(AVG(balance), 0)                                           AS avg_balance,
    ROUND(SUM(CASE WHEN exited = 1 THEN balance ELSE 0 END), 0)      AS balance_lost
FROM vw_customer_360
GROUP BY geography
ORDER BY churn_rate_pct DESC;

-- =====================================================================
-- Q4b. LIKE-FOR-LIKE CHECK: is Germany's churn just a balance-mix effect?
-- Germany has NO zero-balance customers, while ~48% of France and Spain
-- do, and zero-balance customers churn less. So compare only customers
-- who hold a balance. If Germany is still much higher, the gap is real.
-- =====================================================================
SELECT
    geography,
    COUNT(*)                                  AS customers_with_balance,
    SUM(exited)                               AS churned,
    ROUND(100.0 * SUM(exited) / COUNT(*), 1)  AS churn_rate_pct
FROM vw_customer_360
WHERE balance > 0
GROUP BY geography
ORDER BY churn_rate_pct DESC;

-- =====================================================================
-- Q5. HIGH-CHURN SEGMENTS  (core deliverable)
-- Business question: Which specific customer groups should the
-- retention team target first?
-- Segment = Geography x Age band x Activity status, minimum 100 customers
-- Techniques: multiple CTEs, HAVING, CROSS JOIN, DENSE_RANK()
-- Note: pct_of_all_churners divides by the TOTAL from the overall CTE.
--       Using SUM(churned) OVER () would be wrong here, because window
--       functions run AFTER HAVING and would only see surviving segments.
-- =====================================================================
WITH overall AS (
    SELECT SUM(exited) / COUNT(*) AS base_rate,
           SUM(exited)            AS total_churned
    FROM vw_customer_360
),
segments AS (
    SELECT
        geography,
        age_band,
        activity_status,
        COUNT(*)                                          AS customers,
        SUM(exited)                                       AS churned,
        SUM(exited) / COUNT(*)                            AS churn_rate,
        SUM(CASE WHEN exited = 1 THEN balance ELSE 0 END) AS balance_lost
    FROM vw_customer_360
    GROUP BY geography, age_band, activity_status
    HAVING COUNT(*) >= 100          -- small segments give unreliable rates
)
SELECT
    s.geography,
    s.age_band,
    s.activity_status,
    s.customers,
    s.churned,
    ROUND(100 * s.churn_rate, 1)                    AS churn_rate_pct,
    ROUND(s.churn_rate / o.base_rate, 2)            AS lift_vs_bank,
    ROUND(100 * s.churned / o.total_churned, 1)     AS pct_of_all_churners,
    ROUND(s.balance_lost, 0)                        AS balance_lost,
    DENSE_RANK() OVER (ORDER BY s.churn_rate DESC)  AS churn_rank
FROM segments s
CROSS JOIN overall o
ORDER BY churn_rank
LIMIT 10;

-- =====================================================================
-- Q6. WHICH AGE BAND CHURNS MOST INSIDE EACH COUNTRY?
-- Business question: Is the age effect the same in every market?
-- Technique: window function applied on top of a GROUP BY result,
--            RANK() with PARTITION BY (ranking restarts per country)
-- =====================================================================
SELECT
    geography,
    age_band,
    COUNT(*)                                  AS customers,
    SUM(exited)                               AS churned,
    ROUND(100.0 * SUM(exited) / COUNT(*), 1)  AS churn_rate_pct,
    RANK() OVER (PARTITION BY geography
                 ORDER BY SUM(exited) / COUNT(*) DESC) AS rank_within_country
FROM vw_customer_360
GROUP BY geography, age_band
ORDER BY geography, rank_within_country;

-- =====================================================================
-- Q7. PRODUCT HOLDING: how does churn change with each extra product?
-- Technique: LAG() compares each row with the previous row
-- =====================================================================
SELECT
    num_products,
    COUNT(*)                                  AS customers,
    SUM(exited)                               AS churned,
    ROUND(100.0 * SUM(exited) / COUNT(*), 1)  AS churn_rate_pct,
    ROUND(100.0 * SUM(exited) / COUNT(*)
          - LAG(100.0 * SUM(exited) / COUNT(*)) OVER (ORDER BY num_products), 1)
                                              AS change_vs_prev_pp
FROM vw_customer_360
GROUP BY num_products
ORDER BY num_products;

-- =====================================================================
-- Q8. BALANCE DECILES: where is lost balance concentrated?
-- Techniques: NTILE(10), running total with SUM() OVER (ORDER BY ...)
-- Caveat: about 36% of customers hold exactly zero, so the bottom
--         deciles are all zero and NTILE splits those ties arbitrarily.
-- =====================================================================
WITH deciles AS (
    SELECT customer_id, balance, exited,
           NTILE(10) OVER (ORDER BY balance DESC) AS balance_decile
    FROM vw_customer_360
),
decile_summary AS (
    SELECT
        balance_decile,
        MIN(balance)                                      AS min_balance,
        MAX(balance)                                      AS max_balance,
        COUNT(*)                                          AS customers,
        SUM(exited)                                       AS churned,
        SUM(CASE WHEN exited = 1 THEN balance ELSE 0 END) AS balance_lost
    FROM deciles
    GROUP BY balance_decile
)
SELECT
    balance_decile,
    ROUND(min_balance, 0)                   AS min_balance,
    ROUND(max_balance, 0)                   AS max_balance,
    customers,
    churned,
    ROUND(100.0 * churned / customers, 1)   AS churn_rate_pct,
    ROUND(balance_lost, 0)                  AS balance_lost,
    ROUND(100.0 * SUM(balance_lost) OVER (ORDER BY balance_decile)
                / SUM(balance_lost) OVER (), 1) AS cumulative_pct_balance_lost
FROM decile_summary
ORDER BY balance_decile;

-- =====================================================================
-- Q9. RETENTION PRIORITY LIST
-- Business question: Which CURRENT customers should relationship
-- managers call first?
-- Logic: score each retained customer by the historical churn rate of
--        the segment they belong to, weighted by their balance:
--        expected_balance_at_risk = segment churn rate x balance
--        then take the top 50 per country.
-- Techniques: CTE joined back to the view on 4 keys, ROW_NUMBER()
-- IMPORTANT: this is a rule-based heuristic, NOT a predictive model.
-- =====================================================================
WITH segment_risk AS (
    SELECT
        geography, age_band, activity_status, num_products,
        COUNT(*)               AS seg_size,
        SUM(exited) / COUNT(*) AS seg_churn_rate
    FROM vw_customer_360
    GROUP BY geography, age_band, activity_status, num_products
),
scored AS (
    SELECT
        v.customer_id,
        v.geography,
        v.age_band,
        v.gender,
        v.activity_status,
        v.num_products,
        v.balance,
        r.seg_size,
        r.seg_churn_rate,
        r.seg_churn_rate * v.balance AS expected_balance_at_risk
    FROM vw_customer_360 v
    JOIN segment_risk r
      ON  r.geography       = v.geography
      AND r.age_band        = v.age_band
      AND r.activity_status = v.activity_status
      AND r.num_products    = v.num_products
    WHERE v.exited = 0              -- only customers we can still save
      AND r.seg_size >= 30          -- ignore unstable tiny segments
)
SELECT
    customer_id,
    geography,
    age_band,
    gender,
    activity_status,
    num_products,
    ROUND(balance, 0)                   AS balance,
    ROUND(100 * seg_churn_rate, 1)      AS segment_churn_pct,
    ROUND(expected_balance_at_risk, 0)  AS expected_balance_at_risk,
    priority_rank
FROM (
    SELECT scored.*,
           ROW_NUMBER() OVER (PARTITION BY geography
                              ORDER BY expected_balance_at_risk DESC) AS priority_rank
    FROM scored
) ranked
WHERE priority_rank <= 50
ORDER BY geography, priority_rank;

-- =====================================================================
-- Q10. EXPORT FOR EXCEL
-- Run, then in Workbench click "Export recordset to an external file"
-- and save as customer_360.csv
-- =====================================================================
SELECT *
FROM vw_customer_360
ORDER BY customer_id;
