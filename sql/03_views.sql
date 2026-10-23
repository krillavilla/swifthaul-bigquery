-- =============================================================================
-- 03_views.sql — Task 3: reusable views + one materialized view
-- =============================================================================

-- 3a. On-time rate by carrier and month.
-- The raw counts (total_shipments, on_time_shipments) are kept alongside the
-- rate on purpose: to get a carrier's OVERALL rate later you must compute
-- SUM(on_time_shipments) / SUM(total_shipments). Averaging the monthly rates
-- would weight a 200-shipment month the same as a 20,000-shipment month.
CREATE OR REPLACE VIEW swifthaul.v_carrier_ontime AS
SELECT
  carrier,
  DATE_TRUNC(ship_date, MONTH)                    AS ship_month,
  COUNT(*)                                        AS total_shipments,
  COUNTIF(on_time)                                AS on_time_shipments,
  SAFE_DIVIDE(COUNTIF(on_time), COUNT(*))         AS on_time_rate   -- NULL instead of error on 0 rows
FROM swifthaul.shipments
GROUP BY carrier, ship_month;


-- 3b. Cost per lane (lane = origin_region -> destination_region).
-- shipment_count lets readers judge whether an average is based on enough
-- shipments to trust; the median-ish approximation guards against a few huge
-- shipments inflating the mean.
CREATE OR REPLACE VIEW swifthaul.v_cost_per_lane AS
SELECT
  origin_region,
  destination_region,
  CONCAT(origin_region, ' → ', destination_region)           AS lane,
  COUNT(*)                                                   AS shipment_count,
  AVG(freight_cost_usd)                                      AS avg_freight_cost_usd,
  APPROX_QUANTILES(freight_cost_usd, 100)[OFFSET(50)]        AS median_freight_cost_usd,
  AVG(SAFE_DIVIDE(freight_cost_usd, weight_kg))              AS avg_cost_per_kg_usd
FROM swifthaul.shipments
GROUP BY origin_region, destination_region;


-- 3c. Materialized view: daily shipment volume.
/* -----------------------------------------------------------------------------
   WHY A MATERIALIZED VIEW IS WORTH THE STORAGE COST HERE

   - The workload: an ops dashboard showing daily volume refreshes many times a
     day for many viewers. As a regular view, every refresh would re-scan the
     ship_date, weight and cost columns of all ~1.5M rows and re-aggregate them.
   - The materialized result is tiny: one row per day (a few hundred to a few
     thousand rows), so its storage cost is negligible next to the base table.
   - BigQuery keeps it fresh incrementally: when new shipments are appended it
     aggregates only the new rows and merges them, instead of recomputing all
     history. Queries always return current data — if the MV is behind, BigQuery
     combines the stored result with the unprocessed changes automatically.
   - Smart tuning: queries against the BASE table that ask for the same
     aggregation (e.g. COUNT(*) GROUP BY ship_date) can be rewritten by BigQuery
     to read the MV instead, so even dashboards not pointed at the MV benefit.
   Net: pay a small, fixed storage cost once to avoid paying full-scan compute
   on every one of many repeated reads.
----------------------------------------------------------------------------- */
CREATE MATERIALIZED VIEW IF NOT EXISTS swifthaul.mv_daily_volume
OPTIONS (
  enable_refresh           = TRUE,
  refresh_interval_minutes = 60
)
AS
SELECT
  ship_date,
  COUNT(*)                 AS shipments,
  COUNTIF(on_time)         AS on_time_shipments,
  SUM(weight_kg)           AS total_weight_kg,
  SUM(freight_cost_usd)    AS total_freight_cost_usd
FROM swifthaul.shipments
GROUP BY ship_date;
-- Note: an MV's SELECT must be built from supported aggregates (COUNT, COUNTIF,
-- SUM, AVG, MIN, MAX, ...). Derived ratios like an on-time rate belong in the
-- query that READS the MV: SAFE_DIVIDE(on_time_shipments, shipments).


-- Quick checks
SELECT * FROM swifthaul.v_carrier_ontime ORDER BY carrier, ship_month LIMIT 20;
SELECT * FROM swifthaul.v_cost_per_lane  ORDER BY avg_freight_cost_usd DESC LIMIT 10;
SELECT * FROM swifthaul.mv_daily_volume  ORDER BY ship_date LIMIT 10;
