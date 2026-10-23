-- =============================================================================
-- 07_analysis.sql — Task 7: business questions
-- Cite these labels (Q1, Q2, …) next to every figure in your PDF summary.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Q1. Reliability: carriers ranked by OVERALL on-time rate (from v_carrier_ontime)
-- Re-aggregate the counts, don't average the monthly rates (see 03_views.sql).
-- -----------------------------------------------------------------------------
SELECT
  carrier,
  SUM(total_shipments)                                          AS total_shipments,
  SUM(on_time_shipments)                                        AS on_time_shipments,
  ROUND(SAFE_DIVIDE(SUM(on_time_shipments), SUM(total_shipments)) * 100, 2)
                                                                AS on_time_rate_pct,
  -- consistency: worst and best month tell you whether a carrier is reliably
  -- reliable or just good on average
  ROUND(MIN(on_time_rate) * 100, 2)                             AS worst_month_pct,
  ROUND(MAX(on_time_rate) * 100, 2)                             AS best_month_pct
FROM swifthaul.v_carrier_ontime
GROUP BY carrier
ORDER BY on_time_rate_pct DESC;


-- Q1b. (Optional, for a chart) monthly trend per carrier — is anyone improving
-- or slipping? Plot ship_month vs on_time_rate, one line per carrier.
SELECT carrier, ship_month, ROUND(on_time_rate * 100, 2) AS on_time_rate_pct
FROM swifthaul.v_carrier_ontime
ORDER BY carrier, ship_month;


-- -----------------------------------------------------------------------------
-- Q2. Expense: most expensive lanes on average (from v_cost_per_lane)
-- shipment_count is shown so you can flag lanes whose average rests on few
-- shipments. avg_cost_per_kg distinguishes "expensive because far/heavy"
-- from "expensive per unit of freight".
-- -----------------------------------------------------------------------------
SELECT
  lane,
  shipment_count,
  ROUND(avg_freight_cost_usd, 2)    AS avg_freight_cost_usd,
  ROUND(median_freight_cost_usd, 2) AS median_freight_cost_usd,
  ROUND(avg_cost_per_kg_usd, 3)     AS avg_cost_per_kg_usd
FROM swifthaul.v_cost_per_lane
ORDER BY avg_freight_cost_usd DESC
LIMIT 10;

-- Q2b. Cheapest lanes, for contrast.
SELECT lane, shipment_count, ROUND(avg_freight_cost_usd, 2) AS avg_freight_cost_usd
FROM swifthaul.v_cost_per_lane
ORDER BY avg_freight_cost_usd ASC
LIMIT 3;


-- -----------------------------------------------------------------------------
-- Q3. Cost vs. reliability scorecard per carrier
-- Cost per kg = AVG(freight_cost_usd / weight_kg) per the project definition.
-- Uses the enriched view from 02_ so mode is available (or join
-- carrier_rates_ext directly).
-- -----------------------------------------------------------------------------
SELECT
  carrier,
  mode,
  COUNT(*)                                                        AS shipments,
  ROUND(SAFE_DIVIDE(COUNTIF(on_time), COUNT(*)) * 100, 2)         AS on_time_rate_pct,
  ROUND(AVG(SAFE_DIVIDE(freight_cost_usd, weight_kg)), 3)         AS avg_cost_per_kg_usd,
  ROUND(AVG(freight_cost_usd), 2)                                 AS avg_cost_per_shipment_usd,
  -- rank within mode: comparing Air carriers to Ocean carriers on price alone
  -- is apples-to-oranges, so rank each carrier against its peers
  RANK() OVER (PARTITION BY mode ORDER BY AVG(SAFE_DIVIDE(freight_cost_usd, weight_kg)))
                                                                  AS cost_rank_in_mode,
  RANK() OVER (PARTITION BY mode ORDER BY SAFE_DIVIDE(COUNTIF(on_time), COUNT(*)) DESC)
                                                                  AS reliability_rank_in_mode
FROM swifthaul.v_shipments_enriched
WHERE weight_kg > 0          -- guard: cost/kg undefined for zero weight
GROUP BY carrier, mode
ORDER BY mode, avg_cost_per_kg_usd;


-- Q3b. Cost of a late shipment: what does each carrier charge per kg for the
-- on-time shipments vs the late ones? Lets you phrase the recommendation as
-- "you pay $X/kg more for Y points of reliability".
SELECT
  carrier,
  ROUND(AVG(IF(on_time,     SAFE_DIVIDE(freight_cost_usd, weight_kg), NULL)), 3) AS cost_per_kg_on_time,
  ROUND(AVG(IF(NOT on_time, SAFE_DIVIDE(freight_cost_usd, weight_kg), NULL)), 3) AS cost_per_kg_late
FROM swifthaul.shipments
WHERE weight_kg > 0
GROUP BY carrier
ORDER BY carrier;


-- Q3c. Lane-level "best value" carrier: on each of the 10 most expensive lanes,
-- which carrier is cheapest per kg, and what's its on-time rate? Turns the
-- recommendation into something ops can act on lane by lane.
-- Only carriers with >= 100 shipments on a lane are considered (tune this).
WITH lane_carrier AS (
  SELECT
    origin_region, destination_region, carrier,
    COUNT(*)                                                AS shipments,
    AVG(SAFE_DIVIDE(freight_cost_usd, weight_kg))           AS cost_per_kg,
    SAFE_DIVIDE(COUNTIF(on_time), COUNT(*))                 AS on_time_rate
  FROM swifthaul.shipments
  WHERE weight_kg > 0
  GROUP BY origin_region, destination_region, carrier
  HAVING COUNT(*) >= 100
),
top_lanes AS (
  SELECT origin_region, destination_region
  FROM swifthaul.v_cost_per_lane
  ORDER BY avg_freight_cost_usd DESC
  LIMIT 10
)
SELECT
  CONCAT(lc.origin_region, ' → ', lc.destination_region) AS lane,
  lc.carrier,
  lc.shipments,
  ROUND(lc.cost_per_kg, 3)          AS cost_per_kg_usd,
  ROUND(lc.on_time_rate * 100, 2)   AS on_time_rate_pct
FROM lane_carrier AS lc
JOIN top_lanes    AS tl USING (origin_region, destination_region)
ORDER BY lane, cost_per_kg_usd;
