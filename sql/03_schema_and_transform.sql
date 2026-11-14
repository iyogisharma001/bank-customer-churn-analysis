-- =====================================================================
-- Bank Customer Churn Analysis | 03_schema_and_transform.sql
-- Purpose : Model the flat file into a relational schema, add a
--           segment lookup table, and build one analysis-ready view.
--
-- Why split one CSV into tables?
--   In a real bank, customer demographics (CRM), account data (core
--   banking) and closure status (operations) live in different systems.
--   Modelling it the same way mirrors production data and makes every
--   join in the analysis a genuine join.
-- =====================================================================
USE bank_churn;

DROP VIEW  IF EXISTS vw_customer_360;
DROP TABLE IF EXISTS segment_bands;
DROP TABLE IF EXISTS customer_status;
DROP TABLE IF EXISTS accounts;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS dim_geography;

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------
CREATE TABLE dim_geography (
    geo_id       TINYINT AUTO_INCREMENT PRIMARY KEY,
    country_name VARCHAR(20) NOT NULL UNIQUE
);

CREATE TABLE customers (
    customer_id INT PRIMARY KEY,
    surname     VARCHAR(50),
    gender      VARCHAR(10)      NOT NULL,
    age         TINYINT UNSIGNED NOT NULL,
    geo_id      TINYINT          NOT NULL,
    CONSTRAINT fk_customer_geo FOREIGN KEY (geo_id) REFERENCES dim_geography(geo_id)
);

CREATE TABLE accounts (
    customer_id      INT PRIMARY KEY,
    credit_score     SMALLINT      NOT NULL,
    tenure_years     TINYINT       NOT NULL,
    balance          DECIMAL(12,2) NOT NULL,
    num_products     TINYINT       NOT NULL,
    has_credit_card  TINYINT(1)    NOT NULL,
    is_active_member TINYINT(1)    NOT NULL,
    estimated_salary DECIMAL(12,2) NOT NULL,
    CONSTRAINT fk_account_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE customer_status (
    customer_id INT PRIMARY KEY,
    exited      TINYINT(1) NOT NULL,     -- 1 = churned, 0 = retained
    CONSTRAINT fk_status_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

-- ---------------------------------------------------------------------
-- 2. Populate from staging (order matters: parents before children,
--    because of the foreign keys)
-- ---------------------------------------------------------------------
INSERT INTO dim_geography (country_name)
SELECT DISTINCT TRIM(geography)
FROM stg_churn
ORDER BY 1;

INSERT INTO customers (customer_id, surname, gender, age, geo_id)
SELECT s.customer_id, s.surname, TRIM(s.gender), s.age, g.geo_id
FROM stg_churn s
JOIN dim_geography g
  ON g.country_name = TRIM(s.geography);

INSERT INTO accounts (customer_id, credit_score, tenure_years, balance, num_products,
                      has_credit_card, is_active_member, estimated_salary)
SELECT customer_id, credit_score, tenure, balance, num_of_products,
       has_cr_card, is_active_member, estimated_salary
FROM stg_churn;

INSERT INTO customer_status (customer_id, exited)
SELECT customer_id, exited
FROM stg_churn;

-- Reconciliation: all five numbers must be 10000 ---------------------
SELECT
    (SELECT COUNT(*) FROM stg_churn)       AS staging_rows,
    (SELECT COUNT(*) FROM customers)       AS customers_rows,
    (SELECT COUNT(*) FROM accounts)        AS accounts_rows,
    (SELECT COUNT(*) FROM customer_status) AS status_rows,
    (SELECT COUNT(*)
       FROM customers c
       JOIN accounts a        ON a.customer_id = c.customer_id
       JOIN customer_status s ON s.customer_id = c.customer_id) AS joined_rows;

-- ---------------------------------------------------------------------
-- 3. Segment lookup table
--    One row per band. lower_bound is INCLUSIVE, upper_bound EXCLUSIVE,
--    so bands never overlap and never leave gaps.
--    The business can redefine a band by editing one row here, with no
--    change to any query. Numeric prefixes keep labels sorted in Excel.
-- ---------------------------------------------------------------------
CREATE TABLE segment_bands (
    band_type   VARCHAR(20)   NOT NULL,
    band_label  VARCHAR(30)   NOT NULL,
    lower_bound DECIMAL(12,2) NOT NULL,
    upper_bound DECIMAL(12,2) NOT NULL,
    sort_order  TINYINT       NOT NULL,
    PRIMARY KEY (band_type, band_label)
);

INSERT INTO segment_bands (band_type, band_label, lower_bound, upper_bound, sort_order) VALUES
('AGE',     '1. 18-29',                 18,       30, 1),
('AGE',     '2. 30-39',                 30,       40, 2),
('AGE',     '3. 40-49',                 40,       50, 3),
('AGE',     '4. 50-59',                 50,       60, 4),
('AGE',     '5. 60+',                   60,      200, 5),
('CREDIT',  '1. Poor (<580)',          300,      580, 1),
('CREDIT',  '2. Fair (580-669)',       580,      670, 2),
('CREDIT',  '3. Good (670-739)',       670,      740, 3),
('CREDIT',  '4. Very Good (740-799)',  740,      800, 4),
('CREDIT',  '5. Excellent (800+)',     800,     1000, 5),
('BALANCE', '1. Zero',                   0,     0.01, 1),
('BALANCE', '2. Up to 50K',           0.01,    50000, 2),
('BALANCE', '3. 50K-100K',           50000,   100000, 3),
('BALANCE', '4. 100K-150K',         100000,   150000, 4),
('BALANCE', '5. 150K+',             150000, 99999999, 5),
('TENURE',  '1. New (0-2 yrs)',          0,        3, 1),
('TENURE',  '2. Mid (3-6 yrs)',          3,        7, 2),
('TENURE',  '3. Long (7-10 yrs)',        7,       11, 3);

-- ---------------------------------------------------------------------
-- 4. Analysis-ready view: the single source of truth for SQL and Excel
--    * INNER JOINs for the core tables (every customer must exist in all)
--    * LEFT JOINs with range conditions (non-equi joins) for the bands,
--      so a customer outside every band shows up as NULL instead of
--      silently disappearing. The check below proves none do.
-- ---------------------------------------------------------------------
CREATE VIEW vw_customer_360 AS
SELECT
    c.customer_id,
    c.gender,
    c.age,
    g.country_name AS geography,
    a.credit_score,
    a.tenure_years,
    a.balance,
    a.num_products,
    a.has_credit_card,
    a.is_active_member,
    a.estimated_salary,
    s.exited,
    ab.band_label  AS age_band,
    cb.band_label  AS credit_band,
    bb.band_label  AS balance_band,
    tb.band_label  AS tenure_band,
    CASE WHEN a.is_active_member = 1 THEN 'Active'  ELSE 'Inactive' END AS activity_status,
    CASE WHEN s.exited = 1           THEN 'Churned' ELSE 'Retained' END AS churn_status
FROM customers c
JOIN dim_geography   g ON g.geo_id      = c.geo_id
JOIN accounts        a ON a.customer_id = c.customer_id
JOIN customer_status s ON s.customer_id = c.customer_id
LEFT JOIN segment_bands ab
       ON ab.band_type = 'AGE'
      AND c.age >= ab.lower_bound AND c.age < ab.upper_bound
LEFT JOIN segment_bands cb
       ON cb.band_type = 'CREDIT'
      AND a.credit_score >= cb.lower_bound AND a.credit_score < cb.upper_bound
LEFT JOIN segment_bands bb
       ON bb.band_type = 'BALANCE'
      AND a.balance >= bb.lower_bound AND a.balance < bb.upper_bound
LEFT JOIN segment_bands tb
       ON tb.band_type = 'TENURE'
      AND a.tenure_years >= tb.lower_bound AND a.tenure_years < tb.upper_bound;

-- Every customer must fall in exactly one band per type ---- expect 10000, all 0
SELECT
    COUNT(*)                  AS view_rows,
    SUM(age_band     IS NULL) AS unbanded_age,
    SUM(credit_band  IS NULL) AS unbanded_credit,
    SUM(balance_band IS NULL) AS unbanded_balance,
    SUM(tenure_band  IS NULL) AS unbanded_tenure
FROM vw_customer_360;
