-- =====================================================================
-- Bank Customer Churn Analysis | 02_data_quality.sql
-- Purpose : Validate the raw data BEFORE any analysis.
-- Every check states its expected result. If a result differs,
-- stop and investigate before moving to 03.
-- =====================================================================
USE bank_churn;

-- DQ1. Row count -------------------------------------------- expect 10000
SELECT COUNT(*) AS total_rows
FROM stg_churn;

-- DQ2. Duplicate customer IDs ------------------------------- expect 0 rows
SELECT customer_id, COUNT(*) AS occurrences
FROM stg_churn
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- DQ3. Missing values in every column ------------------------ expect all 0
-- In MySQL a TRUE/FALSE expression evaluates to 1/0, so SUM() counts it.
SELECT
    SUM(customer_id      IS NULL) AS null_customer_id,
    SUM(surname          IS NULL) AS null_surname,
    SUM(credit_score     IS NULL) AS null_credit_score,
    SUM(geography        IS NULL) AS null_geography,
    SUM(gender           IS NULL) AS null_gender,
    SUM(age              IS NULL) AS null_age,
    SUM(tenure           IS NULL) AS null_tenure,
    SUM(balance          IS NULL) AS null_balance,
    SUM(num_of_products  IS NULL) AS null_products,
    SUM(has_cr_card      IS NULL) AS null_has_cr_card,
    SUM(is_active_member IS NULL) AS null_is_active,
    SUM(estimated_salary IS NULL) AS null_salary,
    SUM(exited           IS NULL) AS null_exited
FROM stg_churn;

-- DQ4. Value ranges: catch impossible values ----------- expect sane ranges
SELECT
    MIN(credit_score)     AS min_credit,  MAX(credit_score)     AS max_credit,
    MIN(age)              AS min_age,     MAX(age)              AS max_age,
    MIN(tenure)           AS min_tenure,  MAX(tenure)           AS max_tenure,
    MIN(balance)          AS min_balance, MAX(balance)          AS max_balance,
    MIN(num_of_products)  AS min_prod,    MAX(num_of_products)  AS max_prod,
    MIN(estimated_salary) AS min_salary,  MAX(estimated_salary) AS max_salary
FROM stg_churn;

-- DQ5. Categorical values: catch typos and stray spaces ---- expect 3 x 2 combos
SELECT geography, gender, COUNT(*) AS customers
FROM stg_churn
GROUP BY geography, gender
ORDER BY geography, gender;

-- DQ6. Binary flags must contain only 0 and 1 ------------- expect 0/1 only
SELECT 'has_cr_card' AS flag, has_cr_card AS value, COUNT(*) AS customers
FROM stg_churn GROUP BY has_cr_card
UNION ALL
SELECT 'is_active_member', is_active_member, COUNT(*)
FROM stg_churn GROUP BY is_active_member
UNION ALL
SELECT 'exited', exited, COUNT(*)
FROM stg_churn GROUP BY exited
ORDER BY flag, value;

-- DQ7. Distribution check: how many customers hold a zero balance?
-- Not an error, but an important property of the data to know.
SELECT
    SUM(balance = 0)                           AS zero_balance_customers,
    ROUND(100.0 * SUM(balance = 0) / COUNT(*), 1) AS zero_balance_pct
FROM stg_churn;
