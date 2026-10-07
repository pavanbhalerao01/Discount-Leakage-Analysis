-- ============================================================
-- 02_analysis.sql
-- Answers the 5 business questions for Discount Leakage Analysis.
-- Run AFTER 01_setup_and_load.sql has finished successfully.
-- Each CREATE TABLE produces the summary Power BI will read.
-- ============================================================

USE discount_leakage;

-- Drop output tables so re-runs are clean
DROP TABLE IF EXISTS dept_summary, commodity_discount,
                     hh_summary, hh_segments, segment_summary,
                     hh_campaign_spend, campaign_lift;

-- ============================================================
-- Q1 + Q5: Department summary
-- retailer_disc_rate_pct = retailer discount / gross sales (pre-discount revenue)
-- pct_of_all_retailer_disc = this dept's share of the total retailer discount pool
-- ============================================================
CREATE TABLE dept_summary AS
SELECT p.department,
  ROUND(SUM(t.sales_value),0)                                          AS net_sales,
  ROUND(SUM(t.gross_sales),0)                                          AS gross_sales,
  ROUND(SUM(t.retailer_disc),0)                                        AS retailer_disc,
  ROUND(SUM(t.mfr_disc),0)                                             AS mfr_disc,
  ROUND(100*SUM(t.retailer_disc)/SUM(t.gross_sales),1)                 AS retailer_disc_rate_pct,
  ROUND(100*SUM(t.retailer_disc)/SUM(SUM(t.retailer_disc)) OVER (),1)  AS pct_of_all_retailer_disc
FROM transactions t
JOIN products p ON p.product_id = t.product_id
GROUP BY p.department
HAVING SUM(t.gross_sales) > 0;

-- Quick check
SELECT * FROM dept_summary ORDER BY retailer_disc DESC;

-- ============================================================
-- Q2: Commodity Pareto – top ~20 commodities by retailer discount
-- share_of_disc_pct > share_of_sales_pct means this commodity is
-- discounted MORE than its revenue contribution, i.e. discount leakage.
-- cum_share_of_disc_pct: cumulative share (for Pareto line in Power BI).
-- ============================================================
CREATE TABLE commodity_discount AS
WITH c AS (
  SELECT p.department,
         p.commodity_desc,
         SUM(t.retailer_disc) AS disc,
         SUM(t.gross_sales)   AS gross
  FROM transactions t
  JOIN products p ON p.product_id = t.product_id
  GROUP BY p.department, p.commodity_desc
  HAVING SUM(t.gross_sales) > 0
)
SELECT department,
       commodity_desc,
       ROUND(disc,0)                                                              AS retailer_disc,
       ROUND(gross,0)                                                             AS gross_sales,
       ROUND(100*disc/gross,1)                                                    AS disc_rate_pct,
       ROUND(100*disc/SUM(disc) OVER (),2)                                        AS share_of_disc_pct,
       ROUND(100*gross/SUM(gross) OVER (),2)                                      AS share_of_sales_pct,
       ROUND(
         100*SUM(disc) OVER (ORDER BY disc DESC ROWS UNBOUNDED PRECEDING)
         /SUM(disc) OVER ()
       ,1)                                                                         AS cum_share_of_disc_pct,
       ROW_NUMBER() OVER (ORDER BY disc DESC)                                     AS rnk
FROM c;

-- Show the top 20 for review
SELECT * FROM commodity_discount WHERE rnk <= 20 ORDER BY rnk;

-- ============================================================
-- Q3a: Household-level totals
-- disc_rate_pct = retailer discount / gross sales for each household
-- ============================================================
CREATE TABLE hh_summary AS
SELECT household_key,
  SUM(sales_value)                               AS net_sales,
  SUM(gross_sales)                               AS gross_sales,
  SUM(retailer_disc)                             AS retailer_disc,
  SUM(mfr_disc)                                  AS mfr_disc,
  COUNT(DISTINCT basket_id)                      AS visits,
  100*SUM(retailer_disc)/SUM(gross_sales)        AS disc_rate_pct
FROM transactions
GROUP BY household_key
HAVING SUM(gross_sales) > 0;

-- Q3b: Segment households by spend quartile and deal-dependence
-- spend_quartile 1 = top 25% spenders; deal_group based on discount rate quartile
CREATE TABLE hh_segments AS
SELECT *,
  NTILE(4) OVER (ORDER BY net_sales DESC)    AS spend_quartile,
  CASE NTILE(4) OVER (ORDER BY disc_rate_pct DESC)
    WHEN 1 THEN 'Deal-dependent'
    WHEN 4 THEN 'Full-price leaning'
    ELSE 'Mixed'
  END                                        AS deal_group
FROM hh_summary;

-- Q3c: Aggregated comparison across segments (UNION gives one clean table for Power BI)
CREATE TABLE segment_summary AS
-- First block: spend quartiles
SELECT 'Spend quartile'                                               AS segment_type,
       CONCAT('Q', spend_quartile)                                    AS segment,
       COUNT(*)                                                        AS households,
       ROUND(SUM(net_sales),0)                                        AS net_sales,
       ROUND(SUM(retailer_disc),0)                                    AS retailer_disc,
       ROUND(100*SUM(net_sales)/SUM(SUM(net_sales)) OVER (),1)        AS pct_of_net_sales,
       ROUND(100*SUM(retailer_disc)/SUM(SUM(retailer_disc)) OVER (),1) AS pct_of_retailer_disc,
       ROUND(100*SUM(retailer_disc)/SUM(gross_sales),1)               AS disc_rate_pct
FROM hh_segments
GROUP BY spend_quartile

UNION ALL

-- Second block: deal group labels
SELECT 'Deal group',
       deal_group,
       COUNT(*),
       ROUND(SUM(net_sales),0),
       ROUND(SUM(retailer_disc),0),
       ROUND(100*SUM(net_sales)/SUM(SUM(net_sales)) OVER (),1),
       ROUND(100*SUM(retailer_disc)/SUM(SUM(retailer_disc)) OVER (),1),
       ROUND(100*SUM(retailer_disc)/SUM(gross_sales),1)
FROM hh_segments
GROUP BY deal_group;

SELECT * FROM segment_summary ORDER BY segment_type, segment;

-- ============================================================
-- Q4: Campaign lift – mailed vs not-mailed households
--
-- Logic:
--   For each campaign, we look at a pre-window of the same length
--   as the campaign itself (len days) immediately before start_day.
--   We require: start_day - len >= 1 (pre-window is within the data)
--             AND end_day <= MAX(day) in the dataset.
--
-- mailed = 1 if the household was targeted by this campaign.
-- IMPORTANT NOTE: mailed_pre vs other_pre tests for selection bias.
-- If mailed households already spent more before the campaign,
-- any "lift" is partly or fully a pre-existing difference, not a
-- campaign effect. This analysis shows association, NOT causation.
-- ============================================================
CREATE TABLE hh_campaign_spend AS
SELECT c.campaign,
       c.campaign_type,
       h.household_key,
       (ct.household_key IS NOT NULL)    AS mailed,
       -- pre-window: len days immediately before start_day
       SUM(CASE WHEN t.day <  c.start_day THEN t.sales_value ELSE 0 END) AS pre_spend,
       -- during-window: start_day through end_day
       SUM(CASE WHEN t.day >= c.start_day THEN t.sales_value ELSE 0 END) AS during_spend
FROM (
  -- campaign window metadata; description field = campaign type (e.g., TypeA, TypeB)
  SELECT campaign,
         description  AS campaign_type,
         start_day,
         end_day,
         end_day - start_day + 1 AS len
  FROM campaign_desc
) c
CROSS JOIN hh_summary h     -- every household gets a row for every valid campaign
LEFT JOIN campaign_table ct
       ON ct.campaign       = c.campaign
      AND ct.household_key  = h.household_key
LEFT JOIN transactions t
       ON t.household_key   = h.household_key
      AND t.day BETWEEN c.start_day - c.len AND c.end_day   -- covers both windows
WHERE c.start_day - c.len >= 1
  AND c.end_day <= (SELECT MAX(day) FROM transactions)
GROUP BY c.campaign, c.campaign_type, h.household_key, ct.household_key;

-- Aggregate to campaign level
CREATE TABLE campaign_lift AS
SELECT *,
  -- lift = incremental spend per mailed HH vs control change
  ROUND((mailed_during - mailed_pre) - (other_during - other_pre), 2)  AS lift_usd_per_hh,
  ROUND(100*(mailed_during - mailed_pre)/NULLIF(mailed_pre, 0), 1)     AS mailed_change_pct,
  ROUND(100*(other_during - other_pre)/NULLIF(other_pre, 0), 1)        AS other_change_pct
FROM (
  SELECT campaign,
         campaign_type,
         SUM(mailed)                                                       AS mailed_hh,
         COUNT(*) - SUM(mailed)                                            AS other_hh,
         ROUND(AVG(CASE WHEN mailed = 1 THEN pre_spend    END), 2)         AS mailed_pre,
         ROUND(AVG(CASE WHEN mailed = 1 THEN during_spend END), 2)         AS mailed_during,
         ROUND(AVG(CASE WHEN mailed = 0 THEN pre_spend    END), 2)         AS other_pre,
         ROUND(AVG(CASE WHEN mailed = 0 THEN during_spend END), 2)         AS other_during
  FROM hh_campaign_spend
  GROUP BY campaign, campaign_type
) x;

-- NOTE: mailed_pre vs other_pre reveals selection bias.
-- If mailed_pre > other_pre, better-spending households were targeted.
-- The lift number is an association, not proof the campaign caused the change.

SELECT * FROM campaign_lift ORDER BY campaign;

-- Campaign type summary for README (not stored as a table)
SELECT campaign_type,
       COUNT(*)                              AS campaigns,
       ROUND(AVG(lift_usd_per_hh), 2)       AS avg_lift_usd_per_hh,
       ROUND(AVG(mailed_pre), 2)             AS avg_mailed_pre,
       ROUND(AVG(other_pre), 2)              AS avg_other_pre
FROM campaign_lift
GROUP BY campaign_type;

-- ============================================================
-- RECONCILIATION QUERIES  (unit tests – compare with control_totals.txt)
-- All three should closely match the totals the notebook printed.
-- ============================================================

-- R1: Transaction totals
SELECT COUNT(*)                   AS n_rows,
       ROUND(SUM(sales_value),2)  AS net_sales,
       ROUND(SUM(retailer_disc),2) AS retailer_disc,
       ROUND(SUM(mfr_disc),2)     AS mfr_disc,
       ROUND(SUM(gross_sales),2)  AS gross_sales
FROM transactions;

-- R2: Department net sales should equal transaction net sales (after excluding depts)
SELECT ROUND(SUM(net_sales),0) AS dept_net_sales
FROM dept_summary;

-- R3: Every product_id in transactions must exist in products (expect 0)
SELECT COUNT(*) AS orphan_rows
FROM transactions t
LEFT JOIN products p ON p.product_id = t.product_id
WHERE p.product_id IS NULL;
