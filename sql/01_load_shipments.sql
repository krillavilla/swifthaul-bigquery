-- =============================================================================
-- 01_load_shipments.sql — Task 1: create dataset and load shipments (native)
-- Bucket: gs://swifthaul-bigquery-data. Run each statement separately
-- in the BigQuery console (highlight it, then Run) so you can read each result.
-- =============================================================================

-- 1a. Dataset in the US multi-region (skip if you already ran `bq mk` in 00_).
CREATE SCHEMA IF NOT EXISTS swifthaul
OPTIONS (
  location    = 'US',
  description = 'SwiftHaul Logistics analytics warehouse'
);

-- 1b. Load the CSV into a native table with an EXPLICIT schema.
--
-- The column list below matches the file's header row exactly, in order.
-- That matters: with an explicit schema, BigQuery maps CSV columns BY
-- POSITION, not by name — a reordered column would fail the load or silently
-- put data in the wrong column.
--
-- Why explicit instead of autodetect? Autodetect samples rows and guesses;
-- it can type a date as STRING or a boolean column as STRING if one sampled
-- value is odd. The rubric asks you to confirm DATE and BOOL typing, and an
-- explicit schema makes that a guarantee rather than a guess.
--
-- LOAD DATA OVERWRITE replaces the table if you need to rerun it;
-- LOAD DATA INTO appends (rerunning INTO would double your row count).
LOAD DATA OVERWRITE swifthaul.shipments (
  shipment_id         STRING,    -- e.g. SHP-00000001
  customer_id         STRING,    -- e.g. CUST-02739
  order_date          DATE,      -- CSV dates are YYYY-MM-DD, which DATE parses directly
  ship_date           DATE,
  delivery_date       DATE,
  origin_region       STRING,    -- 8 regions: US-East, EU-Central, APAC-East, ...
  destination_region  STRING,
  carrier             STRING,    -- 6 carriers, same names as carrier_rates.csv
  service_level       STRING,    -- Economy / Standard / Express
  weight_kg           FLOAT64,
  distance_km         INT64,     -- whole numbers in the file (300 – 15000)
  freight_cost_usd    FLOAT64,   -- (NUMERIC would be exact for money; FLOAT64 is fine for averages)
  on_time             BOOL,      -- file holds lowercase true/false
  status              STRING     -- Delivered / Delayed / In Transit / Returned
)
FROM FILES (
  format            = 'CSV',
  uris              = ['gs://swifthaul-bigquery-data/raw/shipments.csv'],
  skip_leading_rows = 1           -- skip the header row
);
-- Loaded from the uncompressed shipments.csv (201 MB). The gzipped
-- shipments.csv.gz would load the same way with uri .../shipments.csv.gz —
-- BigQuery detects and decompresses gzip automatically.
-- Expected results (from profiling the source file): 1,500,000 rows; ship_date
-- 2024-01-01 to 2026-01-03; 1,345,166 on_time = true, 154,834 false, 0 null.


-- =============================================================================
-- 1c. Validation queries — screenshot or note these results for your README.
-- =============================================================================

-- Row count: expect ~1.5M. Reading table metadata is free (0 bytes).
SELECT COUNT(*) AS row_count
FROM swifthaul.shipments;

-- Column types: confirm ship_date/delivery_date = DATE and on_time = BOOL.
SELECT column_name, data_type
FROM swifthaul.INFORMATION_SCHEMA.COLUMNS
WHERE table_name = 'shipments'
ORDER BY ordinal_position;

-- Sanity checks on the loaded values: date range, boolean split, nulls.
-- Note the MIN/MAX ship_date — you'll need a real date range for Tasks 4 & 5.
SELECT
  MIN(ship_date)                     AS first_ship_date,
  MAX(ship_date)                     AS last_ship_date,
  COUNTIF(on_time)                   AS on_time_true,
  COUNTIF(NOT on_time)               AS on_time_false,
  COUNTIF(on_time IS NULL)           AS on_time_null,
  COUNT(DISTINCT carrier)            AS carriers,
  COUNT(DISTINCT origin_region)      AS origin_regions,
  COUNT(DISTINCT destination_region) AS destination_regions
FROM swifthaul.shipments;
