# Runbook

Goal: make the pipeline reproducible end-to-end.

1) Ingest raw CSVs into Postgres (raw schema).
2) Build warehouse models (atomic -> OBT).
3) Run DQ gate SQL and confirm checks pass.
4) Use notebooks to explore/communicate insights.

This repo is intentionally structured so that:
- SQL lives in `sql/` as a first-class asset.
- Notebooks live in `notebooks/` and only depend on warehouse tables.
- Generated artifacts go to `outputs/`.
