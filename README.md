# Olist 电商履约与数据分析流水线

> Engineering-style ELT analytics project on the Olist dataset.

本项目基于 Olist 巴西电商数据集，搭建一套端到端的 **ELT 数据架构**：
- Data Ingestion: CSV -> Postgres (raw schema)
- Data Warehousing: SQL models (atomic -> OBT)
- Data Quality: DQ gate SQL
- Analytics: notebooks consuming `analysis.*` tables

## Executive Summary

业务问题：电商体验通常被“履约时效（delay）”主导，但要把它落到业务动作上，需要一条可复现的指标链路：从原始订单流 -> 订单级 OBT -> 复购/流失与供给侧归因。

本项目的交付方式是分 Phase 推进，每个 Phase 都能独立验证（fail-fast），便于在面试中讲清楚“我如何保证正确性、如何让分析可复现”。

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

## Phases

### Phase 1: Ingestion Baseline (CSV -> Postgres)

Objective:
- 把 raw CSV 以“可控、可重复”的方式加载到 Postgres raw schema（默认 `olist`），为后续 SQL 建模提供稳定输入。

Key deliverables:
- Python entrypoint: `src/ecommerce_analytics_pipeline/phase1_ingest.py` (canonical)
- Compatibility entrypoint: `src/ecommerce_analytics_pipeline/ingest.py`

Verification (DoD):
- 能在 DB 中看到 `olist.olist_*` 原始表（或你配置的 `RAW_SCHEMA`），并且不会因为 schema 不存在而报错。

### Phase 2: Warehouse Modeling (Atomic -> OBT) + DQ Gate

Objective:
- 用 SQL 资产构建数仓层次：先订单级 OBT，再商品粒度 atomic；并用 DQ SQL 做质量门禁。

Key deliverables:
- OBT: `sql/models/20_obt/create_obt.sql`
- Atomic: `sql/models/10_atomic/create_items_atomic.sql`
- DQ gate: `sql/dq/check_obt.sql`

Verification (DoD):
- 运行 DQ gate 后，关键约束成立（行数一致性、重复订单为 0、关键字段缺失接近 0）。

### Phase 3: Analytics Delivery (Notebooks + RFM)

Objective:
- 基于 `analysis.*` 宽表与原子表，完成可讲清楚业务含义的分析产出。

Key deliverables:
- Notebook 01: `notebooks/01_obt_feature_analysis.ipynb`
- Notebook 02: `notebooks/02_seller_hook_analysis.ipynb`
- Notebook 03: `notebooks/03_repurchase_diagnosis.ipynb`
- RFM SQL: `sql/analyses/analysis_rfm.sql`

Verification (DoD):
- Notebook 能连库读取 `analysis.analysis_orders_obt`，并生成关键结论/图表（输出建议落在 `outputs/`）。

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
