-- =============================================================================
-- 02_external_table_and_join.sql — Task 2: external table + enrichment join
-- =============================================================================

-- 2a. External table over carrier_rates.csv. The data STAYS in GCS; BigQuery
-- stores only the definition and reads the file at query time. Good fit for a
-- small reference file that ops may re-upload — the next query sees the new
-- version with no reload. Trade-offs: no caching of results, no partitioning/
-- clustering, and bytes processed can't be estimated precisely in a dry run.
--
-- Schema is explicit (matches the file's header exactly) so the rate columns
-- are numeric and effective_date is a DATE.
CREATE OR REPLACE EXTERNAL TABLE swifthaul.carrier_rates_ext (
  carrier              STRING,
  mode                 STRING,
  base_rate_per_kg_usd FLOAT64,
  fuel_surcharge_pct   FLOAT64,   -- stored as a fraction: 0.18 = 18%
  min_charge_usd       FLOAT64,
  effective_date       DATE
)
OPTIONS (
  format            = 'CSV',
  uris              = ['gs://swifthaul-bigquery-data/raw/carrier_rates.csv'],
  skip_leading_rows = 1
);

-- Quick check: expect 6 carriers (Skyliner Air, BlueLine Freight,
-- Continental Cargo, SwiftHaul Ground, OceanLink, MetroCourier).
SELECT * FROM swifthaul.carrier_rates_ext ORDER BY carrier;


-- 2b. Join-key check BEFORE trusting the join: any shipment carrier that
-- doesn't match the rate card (spelling, trailing space, case) would drop out
-- of an INNER JOIN. Expect zero rows here.
SELECT DISTINCT s.carrier
FROM swifthaul.shipments AS s
LEFT JOIN swifthaul.carrier_rates_ext AS r
  ON s.carrier = r.carrier
WHERE r.carrier IS NULL;


-- 2c. Enrichment query: each shipment with its carrier's mode and rate.
-- LEFT JOIN keeps every shipment even if a carrier were missing from the rate
-- card (2b proves none are). LIMIT only shortens the result display; BigQuery
-- still scans the referenced columns, so this is NOT a cost-saving device.
SELECT
  s.shipment_id,
  s.ship_date,
  s.carrier,
  r.mode,
  r.base_rate_per_kg_usd,
  r.fuel_surcharge_pct,
  r.min_charge_usd,
  s.origin_region,
  s.destination_region,
  s.weight_kg,
  s.distance_km,
  s.freight_cost_usd,
  s.on_time
FROM swifthaul.shipments AS s
LEFT JOIN swifthaul.carrier_rates_ext AS r
  ON s.carrier = r.carrier
LIMIT 100;


-- 2d. (Optional) Save the enriched result as a view so later tasks can reuse
-- mode without repeating the join.
CREATE OR REPLACE VIEW swifthaul.v_shipments_enriched AS
SELECT
  s.*,
  r.mode,
  r.base_rate_per_kg_usd,
  r.fuel_surcharge_pct,
  r.min_charge_usd
FROM swifthaul.shipments AS s
LEFT JOIN swifthaul.carrier_rates_ext AS r
  ON s.carrier = r.carrier;


-- 2e. (Optional) Billed-cost reconciliation using the project's freight cost
-- model: max(min_charge, weight × rate × (1 + fuel) + distance × 0.012).
-- A large mismatch share would mean billing errors or rate-card drift —
-- worth a sentence in your summary if you find any.
SELECT
  carrier,
  COUNT(*) AS shipments,
  COUNTIF(ABS(freight_cost_usd - expected_cost_usd) > 0.01) AS mismatched,
  ROUND(AVG(freight_cost_usd - expected_cost_usd), 4)        AS avg_diff_usd
FROM (
  SELECT
    carrier,
    freight_cost_usd,
    GREATEST(
      min_charge_usd,
      weight_kg * base_rate_per_kg_usd * (1 + fuel_surcharge_pct) + distance_km * 0.012
    ) AS expected_cost_usd
  FROM swifthaul.v_shipments_enriched
)
GROUP BY carrier
ORDER BY mismatched DESC;
