#!/usr/bin/env bash
# =============================================================================
# 00_environment_setup.sh — SwiftHaul Logistics: environment setup
# Run these in Cloud Shell (top-right ">_" icon in the Cloud console), which is
# already authenticated to your Udacity sandbox. Run line by line the first time
# so you can see each result.
#
# Everything lives in the US multi-region so GCS and BigQuery are co-located.
# BigQuery can only load from / query a bucket whose location is compatible
# with the dataset location — a US multi-region bucket + US dataset is the
# simplest pairing and avoids "location mismatch" errors.
# =============================================================================

# --- 1. Point gcloud at your sandbox project --------------------------------
# Replace with the project ID shown on the console home page (not the name).
export PROJECT_ID="swifthaul-bigquery"
export BUCKET="gs://swifthaul-bigquery-data"   # bucket names are globally unique; if taken, add a suffix and update the SQL uris
gcloud config set project "${PROJECT_ID}"

# --- 2. Create the bucket in the US multi-region -----------------------------
# --uniform-bucket-level-access: IAM-only permissions on the bucket (no per-object
# ACLs) — the recommended, easier-to-audit setting.
gcloud storage buckets create "${BUCKET}" \
  --location=US \
  --uniform-bucket-level-access

# --- 3. Upload the two data files -------------------------------------------
# In Cloud Shell, first upload the files from your computer: "⋮" menu -> Upload.
# They land in your Cloud Shell home directory. Then copy them to the bucket.
# (Console alternative: Cloud Storage -> Buckets -> your bucket -> Upload files.)
#
# Do NOT unzip shipments.csv.gz. BigQuery detects the gzip compression from the
# file and decompresses it while loading. Trade-off worth knowing: a gzipped CSV
# can't be split, so one worker reads it serially — fine at ~39 MB, but for
# multi-GB data you'd upload uncompressed or sharded files for parallel loads.
gcloud storage cp shipments.csv.gz  "${BUCKET}/raw/shipments.csv.gz"
gcloud storage cp carrier_rates.csv "${BUCKET}/raw/carrier_rates.csv"

# Verify both objects are there
gcloud storage ls -l "${BUCKET}/raw/"

# --- 4. Peek at the shipments header (IMPORTANT before Task 1) ---------------
# The explicit schema in 01_load_shipments.sql must list columns in the SAME
# ORDER as this header row. Compare against the data dictionary too.
gcloud storage cat "${BUCKET}/raw/shipments.csv.gz" | gunzip | head -n 3

# --- 5. Create the dataset (US) ---------------------------------------------
# Same as the CREATE SCHEMA statement at the top of 01_load_shipments.sql —
# use one or the other, not both.
bq --location=US mk --dataset \
  --description="SwiftHaul Logistics analytics warehouse" \
  "${PROJECT_ID}:swifthaul"
