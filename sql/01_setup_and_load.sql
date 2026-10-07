-- ============================================================
-- 01_setup_and_load.sql
-- Creates the discount_leakage database and loads cleaned CSVs.
-- Run this AFTER the Python notebook has written data/clean/.
-- ============================================================

-- BEFORE RUNNING:
--   1. In MySQL server config (my.cnf / my.ini) set local_infile = 1
--      OR run:  SET GLOBAL local_infile = 1;
--   2. Connect with the --local-infile=1 flag, e.g.:
--        mysql --local-infile=1 -u root -p
--   3. Edit the four file paths below to absolute paths on your machine.
--      Use forward slashes even on Windows, e.g.:
--        'C:/Users/yourname/project/data/clean/transactions_clean.csv'

-- ============================================================
-- 1. Database
-- ============================================================
DROP DATABASE IF EXISTS discount_leakage;
CREATE DATABASE discount_leakage CHARACTER SET utf8mb4;
USE discount_leakage;

-- ============================================================
-- 2. Table definitions
-- ============================================================

-- Each column name matches exactly the column written by the notebook.
CREATE TABLE transactions (
    household_key  INT            NOT NULL,
    basket_id      BIGINT         NOT NULL,
    day            INT            NOT NULL,
    week_no        INT            NOT NULL,
    product_id     INT            NOT NULL,
    store_id       INT            NOT NULL,
    quantity       INT            NOT NULL,
    sales_value    DECIMAL(10,2)  NOT NULL,
    retailer_disc  DECIMAL(10,2)  NOT NULL,
    mfr_disc       DECIMAL(10,2)  NOT NULL,
    gross_sales    DECIMAL(10,2)  NOT NULL
);

CREATE TABLE products (
    product_id      INT          NOT NULL,
    department      VARCHAR(60)  NOT NULL,
    brand           VARCHAR(60),
    commodity_desc  VARCHAR(100)
);

CREATE TABLE campaign_table (
    household_key  INT  NOT NULL,
    campaign       INT  NOT NULL
);

CREATE TABLE campaign_desc (
    campaign     INT          NOT NULL,
    description  VARCHAR(60)  NOT NULL,   -- campaign type label
    start_day    INT          NOT NULL,
    end_day      INT          NOT NULL
);

-- ============================================================
-- 3. Load data  (EDIT THE PATHS BELOW)
-- ============================================================

-- transactions
LOAD DATA LOCAL INFILE 'D:/VS Code/Python/Portfolio Project 1/discount-leakage-analysis/data/clean/transactions_clean.csv'
INTO TABLE transactions
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(household_key, basket_id, day, week_no, product_id, store_id,
 quantity, sales_value, retailer_disc, mfr_disc, gross_sales);

-- products
LOAD DATA LOCAL INFILE 'D:/VS Code/Python/Portfolio Project 1/discount-leakage-analysis/data/clean/products_clean.csv'
INTO TABLE products
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(product_id, department, brand, commodity_desc);

-- campaign_table
LOAD DATA LOCAL INFILE 'D:/VS Code/Python/Portfolio Project 1/discount-leakage-analysis/data/clean/campaign_table_clean.csv'
INTO TABLE campaign_table
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(household_key, campaign);

-- campaign_desc
LOAD DATA LOCAL INFILE 'D:/VS Code/Python/Portfolio Project 1/discount-leakage-analysis/data/clean/campaign_desc_clean.csv'
INTO TABLE campaign_desc
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(campaign, description, start_day, end_day);

-- ============================================================
-- 4. Indexes  (add after loading for speed)
-- ============================================================

ALTER TABLE products ADD PRIMARY KEY (product_id);

-- Two composite indexes on transactions for join-heavy queries
CREATE INDEX idx_tx_hh_day    ON transactions (household_key, day);
CREATE INDEX idx_tx_product   ON transactions (product_id);

-- ============================================================
-- 5. Quick row counts to confirm load succeeded
-- ============================================================
SELECT 'transactions'   AS tbl, COUNT(*) AS row_count FROM transactions
UNION ALL
SELECT 'products',                COUNT(*) FROM products
UNION ALL
SELECT 'campaign_table',          COUNT(*) FROM campaign_table
UNION ALL
SELECT 'campaign_desc',           COUNT(*) FROM campaign_desc;
