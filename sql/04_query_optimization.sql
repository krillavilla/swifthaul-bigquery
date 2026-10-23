-- =============================================================================
-- 04_query_optimization.sql — Task 4: diagnose and optimize an expensive query
--
-- HOW TO MEASURE (do this for BOTH queries):
--   1. Paste ONE query into the editor. Don't run it yet.
--   2. Top-right of the editor, the validator shows a green check and
--      "This query will process X MB when run." That is the dry-run estimate —
--      it's free. Screenshot it  -> screenshots/task4_before.png / _after.png
--   3. More -> Query settings -> uncheck "Use cached results", then Run.
--      (A cached result reports 0 bytes and would ruin the comparison.)
--   4. In the results pane open "Job information" (Bytes processed / Bytes
--      billed) and "Execution details" (stages, slot time, records read per
--      stage). Note the numbers in the table at the bottom of this file.
--
-- CLI alternative for the estimate:
--   bq query --use_legacy_sql=false --dry_run 'SELECT ...'
-- =============================================================================


-- 4a. BEFORE — the wasteful query.
-- BigQuery is columnar: cost = total size of every column you reference, across
-- every row. SELECT * references all columns; no WHERE means all rows.
-- (Adding LIMIT 10 would NOT reduce the bytes — it trims output, not the scan.)
SELECT *
FROM swifthaul.shipments;


-- 4b. AFTER — only the columns the question needs + a WHERE filter.
-- Business question: "How did OceanLink perform on shipments in Q1 2025?"
SELECT
  shipment_id,
  ship_date,
  destination_region,
  freight_cost_usd,
  on_time
FROM swifthaul.shipments
WHERE carrier = 'OceanLink'
  AND ship_date BETWEEN '2025-01-01' AND '2025-03-31';

/* -----------------------------------------------------------------------------
   WHAT TO EXPECT AND WHY
   - The reduction on THIS native table comes almost entirely from column
     pruning: 6 columns (5 selected + carrier in the WHERE) instead of all of
     them. Strings like shipment_id and region names are the widest columns,
     so dropping them saves the most.
   - The WHERE filter shrinks the RESULT, but on an unpartitioned table it does
     NOT shrink the scan: BigQuery must still read every row's ship_date and
     carrier values to test the filter. That is exactly the gap Task 5 closes.

   RESULTS (dry-run estimates, screenshots/task4_before.png & task4_after.png)
   | Query            | Dry-run estimate |
   |------------------|------------------|
   | 4a SELECT *      | 189.03 MB        |
   | 4b optimized     |  81.78 MB        |
   | Reduction        | 56.7%            |
   The optimized query returned 31,220 rows, but Execution details shows the
   first stage still read all 1,500,000 rows — confirming the saving came from
   column pruning (6 of 14 columns), not from the WHERE filter.
----------------------------------------------------------------------------- */
