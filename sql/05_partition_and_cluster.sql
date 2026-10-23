-- =============================================================================
-- 05_partition_and_cluster.sql — Task 5: optimized copy of the fact table
-- =============================================================================

-- 5a. Partitioned + clustered copy (CTAS).
-- PARTITION BY ship_date  -> one physical partition per day of ship_date.
-- CLUSTER BY carrier, destination_region -> inside each partition, rows are
--   sorted into storage blocks by carrier, then destination_region. Column
--   ORDER matters: put the column you filter on most often first.
CREATE OR REPLACE TABLE swifthaul.shipments_optimized
PARTITION BY ship_date
CLUSTER BY carrier, destination_region
OPTIONS (
  description = 'shipments, partitioned by ship_date and clustered by carrier, destination_region'
)
AS
SELECT *
FROM swifthaul.shipments;

-- Confirm the layout: should list ship_date as the partitioning column and
-- carrier, destination_region as clustering columns (in that order).
SELECT column_name, is_partitioning_column, clustering_ordinal_position
FROM swifthaul.INFORMATION_SCHEMA.COLUMNS
WHERE table_name = 'shipments_optimized'
  AND (is_partitioning_column = 'YES' OR clustering_ordinal_position IS NOT NULL);

-- Pick a real destination_region value for the test below:
SELECT DISTINCT destination_region FROM swifthaul.shipments ORDER BY 1;


-- =============================================================================
-- 5b. The SAME filtered query on both tables. Only the table name differs.
--   Turn OFF "Use cached results" before running each one.
-- =============================================================================

-- Native (unpartitioned) table  -> screenshots/task5_native.png
SELECT
  carrier,
  destination_region,
  COUNT(*)                                AS shipments,
  SAFE_DIVIDE(COUNTIF(on_time), COUNT(*)) AS on_time_rate,
  AVG(freight_cost_usd)                   AS avg_cost_usd
FROM swifthaul.shipments
WHERE ship_date BETWEEN '2025-03-01' AND '2025-03-31'
  AND carrier = 'OceanLink'
  AND destination_region = 'EU-West'
GROUP BY carrier, destination_region;

-- Optimized (partitioned + clustered) table  -> screenshots/task5_optimized.png
SELECT
  carrier,
  destination_region,
  COUNT(*)                                AS shipments,
  SAFE_DIVIDE(COUNTIF(on_time), COUNT(*)) AS on_time_rate,
  AVG(freight_cost_usd)                   AS avg_cost_usd
FROM swifthaul.shipments_optimized
WHERE ship_date BETWEEN '2025-03-01' AND '2025-03-31'
  AND carrier = 'OceanLink'
  AND destination_region = 'EU-West'
GROUP BY carrier, destination_region;

/* -----------------------------------------------------------------------------
   RESULTS (screenshots/task5_native.png, task5_optimized.png)
   | Table                | Dry-run estimate | Bytes processed | Bytes billed |
   |----------------------|------------------|-----------------|--------------|
   | shipments (native)   | 61.75 MB         | 61.75 MB        | 62 MB        |
   | shipments_optimized  |  2.63 MB         |  2.63 MB        | 10 MB        |
   | Reduction            | 95.7%            | 95.7%           | 83.9%        |
   Both queries return the identical result: 1,420 OceanLink shipments to
   EU-West in March 2025, on-time rate 0.7958, avg cost $177.90.

   WHY THE OPTIMIZED TABLE PROCESSES FEWER BYTES
   1. Partition pruning (the source of the saving here). The table is
      physically split into one partition per ship_date. Because the WHERE
      filters ship_date directly with constant values, BigQuery knows before
      reading any data that only the 31 March 2025 partitions can contain
      matches, and never opens the other 703. The data spans 734 ship dates,
      so 31/734 ≈ 4.2% of the table is read — 61.75 MB × 0.0427 ≈ 2.63 MB,
      exactly what was measured. On the native table there are no partitions,
      so every row's columns must be read just to evaluate the date filter.
   2. Cluster skipping (block pruning). Within each partition, rows are stored
      sorted by carrier, then destination_region, and BigQuery keeps min/max
      metadata for those columns per storage block. At run time, blocks whose
      range cannot contain 'OceanLink' / 'EU-West' are skipped unread. The
      dry-run estimate cannot account for this (it's only known at run time),
      so post-run bytes processed is where it would show up.
      OBSERVED: post-run bytes (2.63 MB) equalled the estimate, so clustering
      skipped nothing extra in this test. Each daily partition holds only
      ~2,000 rows (~85 KB) — smaller than one storage block — so there is
      nothing to skip inside it. Clustering pays off when partitions are large
      (hundreds of MB+); at SwiftHaul's production volume, the same layout
      would let the carrier/region filter skip most blocks in each partition.

   Notes:
   - Pruning only works when the filter is on the partition/cluster column
     itself; wrapping it in a function (e.g. WHERE FORMAT_DATE('%Y-%m',
     ship_date) = '2025-03') can defeat it.
   - Column pruning (Task 4) applies on top of both mechanisms.
   - Bytes billed is 10 MB, not 2.63 MB: BigQuery bills a 10 MB minimum per
     query, so for tiny scans the billed saving (62 → 10 MB) is smaller than
     the processed saving.
----------------------------------------------------------------------------- */
