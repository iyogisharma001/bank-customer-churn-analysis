-- =====================================================================
-- Bank Customer Churn Analysis | 01_setup_and_load.sql
-- Purpose : Create the database and load the raw CSV into a staging table
-- Engine  : MySQL 8.0+
-- Input   : data/Churn_Modelling.csv (10,000 rows, 14 columns)
-- =====================================================================

DROP DATABASE IF EXISTS bank_churn;
CREATE DATABASE bank_churn;
USE bank_churn;

-- ---------------------------------------------------------------------
-- Staging table: mirrors the CSV column-for-column. No cleaning here.
-- Rule: land raw data first, transform later. If something breaks
-- downstream, you can always compare against the untouched staging copy.
-- Note: 'RowNumber' is renamed row_num because ROW_NUMBER is a reserved
-- word in MySQL 8 (it is a window function).
-- ---------------------------------------------------------------------
CREATE TABLE stg_churn (
    row_num          INT,
    customer_id      INT,
    surname          VARCHAR(50),
    credit_score     INT,
    geography        VARCHAR(20),
    gender           VARCHAR(10),
    age              INT,
    tenure           INT,
    balance          DECIMAL(12,2),
    num_of_products  INT,
    has_cr_card      TINYINT,
    is_active_member TINYINT,
    estimated_salary DECIMAL(12,2),
    exited           TINYINT
);

-- ---------------------------------------------------------------------
-- Load the CSV.
-- Before running:
--   1. Replace the path below with the full path to YOUR file.
--      Windows paths must use forward slashes: 'C:/projects/data/Churn_Modelling.csv'
--   2. Enable local loading on the server:   SET GLOBAL local_infile = 1;
--      and in MySQL Workbench: Edit Connection > Advanced >
--      Others: OPT_LOCAL_INFILE=1
-- The Kaggle file uses Windows line endings (\r\n). If you saved it on
-- Mac/Linux and it now uses \n, change the LINES TERMINATED BY clause.
--
-- Alternative (no settings needed): Workbench > right-click stg_churn >
-- Table Data Import Wizard > select the CSV > map columns > Next.
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'C:/projects/bank-churn-analysis/data/Churn_Modelling.csv'
INTO TABLE stg_churn
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES;

-- Must return an empty result. Any warning means a load problem
-- (most often wrong line endings, which corrupt the last column).
SHOW WARNINGS;

SELECT COUNT(*) AS rows_loaded FROM stg_churn;   -- expect 10000
