-- =====================================================================
-- Bank Customer Churn Analysis | 05_practice_exercises.sql
-- Answers to the practice exercises in the project report.
-- Try each exercise yourself BEFORE reading the answer.
-- =====================================================================
USE bank_churn;

-- E1. Churn rate by gender within each country
SELECT geography, gender,
       COUNT(*)                                 AS customers,
       ROUND(100.0 * SUM(exited) / COUNT(*), 1) AS churn_rate_pct
FROM vw_customer_360
GROUP BY geography, gender
ORDER BY geography, churn_rate_pct DESC;

-- E2. Average balance of churned vs retained customers, by country
SELECT geography,
       ROUND(AVG(CASE WHEN exited = 1 THEN balance END), 0) AS avg_balance_churned,
       ROUND(AVG(CASE WHEN exited = 0 THEN balance END), 0) AS avg_balance_retained
FROM vw_customer_360
GROUP BY geography;

-- E3. Top 3 churned customers by balance in each country
SELECT *
FROM (
    SELECT customer_id, geography, balance,
           ROW_NUMBER() OVER (PARTITION BY geography ORDER BY balance DESC) AS rn
    FROM vw_customer_360
    WHERE exited = 1
) t
WHERE rn <= 3
ORDER BY geography, rn;

-- E4. Customers whose balance is above their own country's average:
--     how many are there, and what is their churn rate?
WITH x AS (
    SELECT customer_id, geography, balance, exited,
           AVG(balance) OVER (PARTITION BY geography) AS country_avg_balance
    FROM vw_customer_360
)
SELECT geography,
       COUNT(*)                                 AS above_avg_customers,
       ROUND(100.0 * SUM(exited) / COUNT(*), 1) AS churn_rate_pct
FROM x
WHERE balance > country_avg_balance
GROUP BY geography;

-- E5. Churn rate by tenure year and change vs the previous year
SELECT tenure_years,
       COUNT(*)                                 AS customers,
       ROUND(100.0 * SUM(exited) / COUNT(*), 1) AS churn_rate_pct,
       ROUND(100.0 * SUM(exited) / COUNT(*)
             - LAG(100.0 * SUM(exited) / COUNT(*)) OVER (ORDER BY tenure_years), 1) AS change_pp
FROM vw_customer_360
GROUP BY tenure_years
ORDER BY tenure_years;

-- E6. One row per age band, one column per country (SQL pivot)
SELECT age_band,
       ROUND(100.0 * SUM(CASE WHEN geography = 'France'  THEN exited END)
                   / SUM(geography = 'France'), 1)  AS france_pct,
       ROUND(100.0 * SUM(CASE WHEN geography = 'Germany' THEN exited END)
                   / SUM(geography = 'Germany'), 1) AS germany_pct,
       ROUND(100.0 * SUM(CASE WHEN geography = 'Spain'   THEN exited END)
                   / SUM(geography = 'Spain'), 1)   AS spain_pct
FROM vw_customer_360
GROUP BY age_band
ORDER BY age_band;

-- E7. What share of all balance lost comes from customers with balance > 100,000?
SELECT ROUND(100.0 * SUM(CASE WHEN exited = 1 AND balance > 100000 THEN balance ELSE 0 END)
                   / SUM(CASE WHEN exited = 1 THEN balance ELSE 0 END), 1) AS pct_of_balance_lost
FROM vw_customer_360;

-- E8. Redefine age bands as 18-34 / 35-54 / 55+ WITHOUT touching the view.
--     (Run inside a transaction so you can undo it.)
START TRANSACTION;
DELETE FROM segment_bands WHERE band_type = 'AGE';
INSERT INTO segment_bands VALUES
('AGE', '1. 18-34', 18,  35, 1),
('AGE', '2. 35-54', 35,  55, 2),
('AGE', '3. 55+',   55, 200, 3);
SELECT age_band, COUNT(*) AS customers,
       ROUND(100.0 * SUM(exited) / COUNT(*), 1) AS churn_rate_pct
FROM vw_customer_360
GROUP BY age_band
ORDER BY age_band;
ROLLBACK;   -- restores the original bands

-- E10. Segments (country x gender x activity) with at least 100 customers
--      and churn rate at least 2x the bank average
WITH base AS (SELECT AVG(exited) AS bank_rate FROM vw_customer_360)
SELECT v.geography, v.gender, v.activity_status,
       COUNT(*)                                 AS customers,
       ROUND(100.0 * AVG(v.exited), 1)          AS churn_rate_pct,
       ROUND(AVG(v.exited) / MAX(b.bank_rate), 2) AS lift
FROM vw_customer_360 v
CROSS JOIN base b
GROUP BY v.geography, v.gender, v.activity_status
HAVING COUNT(*) >= 100
   AND AVG(v.exited) >= 2 * MAX(b.bank_rate)
ORDER BY churn_rate_pct DESC;
