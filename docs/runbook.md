# Runbook

Goal: make the pipeline reproducible end-to-end, with phase-by-phase validation.

## Phase 1: Ingestion Baseline

Inputs:
- Local Olist CSVs under `data/` (gitignored)

Required env vars:
- Preferred: `DATABASE_URL`
- Or: `DB_USER`, `DB_PASS`, `DB_HOST`, `DB_PORT`, `DB_NAME`

Optional env vars:
- `DATA_DIR` (default `./data`)
- `RAW_SCHEMA` (default `olist`)

Run:
- `python -m ecommerce_analytics_pipeline.ingest`

DoD:
- Raw tables are created under `RAW_SCHEMA` (default `olist`).

## Phase 2: Warehouse Models + DQ Gate

Run (psql):
- `psql "$DATABASE_URL" -f sql/models/20_obt/create_obt.sql`
- `psql "$DATABASE_URL" -f sql/models/10_atomic/create_items_atomic.sql`
- `psql "$DATABASE_URL" -f sql/models/30_user/create_user_first_order.sql`
- `psql "$DATABASE_URL" -f sql/analyses/analysis_rfm.sql`
- `psql "$DATABASE_URL" -f sql/dq/check_obt.sql`

Optional DQ:
- `psql "$DATABASE_URL" -f sql/dq/check_user_first_order.sql`

DoD:
- `check_obt.sql` returns a single row with:
  - `obt_rows == raw_rows`
  - `duplicate_orders == 0`
  - `null_users` and `null_delays` are ~0

## Phase 3: Analytics Notebooks

Run:
- `jupyter lab`

Canonical notebooks (in order):
- `notebooks/01_obt_feature_analysis.ipynb`
- `notebooks/02_repurchase_diagnosis.ipynb`
- `notebooks/03_seller_hook_analysis.ipynb`

DoD:
- Notebooks can read `analysis.analysis_orders_obt` and reproduce the analysis outputs.

## Repo Conventions

This repo is intentionally structured so that:
- SQL lives in `sql/` as a first-class asset.
- Notebooks live in `notebooks/` and only depend on warehouse tables.
- Generated artifacts go to `outputs/`.
