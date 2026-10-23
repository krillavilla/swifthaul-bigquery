# Task 6 — Data Governance: How BigQuery Secures the Shipments Data

## 1. Encryption

**At rest.** Every byte BigQuery stores — the native `shipments` and `shipments_optimized` tables, the materialized view, and the files in the GCS bucket behind `carrier_rates_ext` — is encrypted automatically before it is written to disk, with no configuration on our part. Google uses AES-256 and envelope encryption: each chunk of data is encrypted with a data encryption key (DEK), and the DEKs are themselves encrypted ("wrapped") by key encryption keys held in Google's key management service, which rotates them on a regular schedule. By default these are **Google-managed keys**.

If SwiftHaul had a compliance requirement to control its own keys, the dataset could use **customer-managed encryption keys (CMEK)** stored in Cloud KMS. With CMEK, SwiftHaul controls rotation and can disable or destroy the key, which makes the data unreadable — a way to revoke access to everything at once. For freight records with no regulated personal data, Google-managed keys are sufficient.

**In transit.** Data moving between clients and BigQuery (the console, `bq` CLI, client libraries, Looker Studio dashboards) travels over **TLS**-encrypted HTTPS connections. Traffic inside Google's network — for example, BigQuery reading `carrier_rates.csv` from Cloud Storage, or the GCS load of `shipments.csv.gz` — is also encrypted and authenticated in transit between Google facilities.

## 2. IAM access control — where permissions can be applied

IAM grants **roles** (bundles of permissions) to **principals** (users, Google Groups, service accounts). Permissions are inherited downward: a role granted on the project applies to every dataset in it; a role on a dataset applies to every table and view in it.

| Level | What it controls | Example use for SwiftHaul |
|---|---|---|
| **Project** | Everything in the project, plus the right to *run* query jobs. | `roles/bigquery.jobUser` lets someone run queries (and be billed for them) without automatically seeing any data. Keep `roles/bigquery.admin` to a very small group. |
| **Dataset** | All tables and views in one dataset. The main unit of access in BigQuery. | `roles/bigquery.dataViewer` on `swifthaul` for analysts; `roles/bigquery.dataEditor` for engineers who load and rebuild tables. |
| **Table** | One table, via its own IAM policy. | Grant a partner team read access to `shipments_optimized` only, without exposing anything else in the dataset. |
| **View** (authorized view) | Lets a view read source tables that its *users* cannot read directly. | Business users query `v_carrier_ontime` and `v_cost_per_lane` — aggregated metrics — but can never open the row-level `shipments` table. |

Finer-grained controls are also available inside a table when needed: **column-level security** (policy tags that restrict sensitive columns) and **row-level security** (row access policies, e.g. a regional manager only sees rows for their `origin_region`).

Note: a user needs **both** a data role (to read the tables) **and** `bigquery.jobUser` on a project (to run the query job). Granting one without the other is a common source of "access denied" confusion.

## 3. Recommended controls for the shipments dataset

**Design:** split raw data from what the business consumes.

- `swifthaul` — raw and engineered tables: `shipments`, `shipments_optimized`, `carrier_rates_ext`, `mv_daily_volume`.
- `swifthaul_reporting` — the views business users need (`v_carrier_ontime`, `v_cost_per_lane`, a daily volume view). These are registered as **authorized views** on the `swifthaul` dataset, so they can read the raw tables on the users' behalf.

**Who gets what** (granted to Google Groups, never to individual accounts, so joiners/leavers are handled by group membership):

| Group | Role(s) | Scope | Why |
|---|---|---|---|
| Data engineering | `bigquery.dataEditor` + `bigquery.jobUser` | `swifthaul` dataset / project | Load, rebuild and optimize tables. |
| Data analysts | `bigquery.dataViewer` + `bigquery.jobUser` | `swifthaul` dataset / project | Ad-hoc analysis on row-level data. |
| Ops managers & leadership | `bigquery.dataViewer` + `bigquery.jobUser` | `swifthaul_reporting` only | See approved metrics; cannot open raw `shipments`. |
| Dashboard service account | `bigquery.dataViewer` + `bigquery.jobUser` | `swifthaul_reporting` only | Powers dashboards with least privilege. |
| Platform admins (1–2 people) | `bigquery.admin` | Project | Break-glass administration only. |
| Ingestion service account | `storage.objectViewer` on the bucket + `bigquery.dataEditor` on `swifthaul` | Bucket / dataset | Can read the source files and load them — nothing else. |

**Supporting practices:** least privilege (start with Viewer, escalate only when needed); no primitive Owner/Editor roles for analysts; uniform bucket-level access on the GCS bucket so the CSVs follow IAM rather than per-object ACLs; and **Cloud Audit Logs** (Data Access logs) to record who queried which tables, so access can be reviewed periodically.
