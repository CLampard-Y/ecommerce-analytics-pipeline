# Olist 电商履约与数据分析流水线

本项目基于 Olist 巴西电商数据集，搭建一套端到端的 **ELT 数据架构**：
- Data Ingestion: CSV -> Postgres (raw schema)
- Data Warehousing: SQL models (atomic -> OBT)
- Data Quality: DQ gate SQL
- Analytics: notebooks consuming `analysis.*` tables

## Repo Structure

```
configs/     # centralized config (non-secret)
docs/        # runbook + data dictionary
notebooks/   # analysis notebooks
outputs/     # generated artifacts (figures/tables/logs)
sql/         # warehouse models + analyses + dq gates
src/         # installable python package
tests/       # lightweight smoke tests
```

## Quickstart (local)

1) Install deps
   - `pip install -r requirements.txt`
   - Optional (recommended): `pip install -e .`

2) Configure env
   - Set `DATABASE_URL` (preferred) OR `DB_USER/DB_PASS/DB_HOST/DB_PORT/DB_NAME`
   - Optional: `RAW_SCHEMA` (default: `olist`)

3) Ingest raw CSVs
   - `python -m ecommerce_analytics_pipeline.ingest`

4) Build warehouse models (psql)
   - `psql "$DATABASE_URL" -f sql/models/20_obt/create_obt.sql`
   - `psql "$DATABASE_URL" -f sql/models/10_atomic/create_items_atomic.sql`

5) Run DQ gate
   - `psql "$DATABASE_URL" -f sql/dq/check_obt.sql`
