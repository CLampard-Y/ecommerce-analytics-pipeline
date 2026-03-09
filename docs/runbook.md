# Runbook

目标：给出从本地 `CSV`、`Postgres` 建模、`DQ gates` 到 notebook 输出的完整复现路径。以下命令均默认在仓库根目录执行。

Quick navigation: [Scope](#scope) · [Prerequisites](#prerequisites) · [Phase 1](#phase-1-ingestion) · [Phase 2](#phase-2-warehouse-models) · [Phase 3](#phase-3-dq-gates) · [Phase 4](#phase-4-analytics-notebooks) · [Verification Checklist](#verification-checklist) · [Troubleshooting](#troubleshooting) · [Related Docs](#related-docs)

## Scope

- 本文只覆盖本地复现：数据导入、SQL 建模、DQ 检查与 notebook 分析。
- 本文不覆盖生产调度、实时监控或线上干预；当前仓库是 batch analytics 形态。
- 当前仓库可能保留了部分 `data/` 与 `outputs/` 快照，便于直接浏览，但复现时仍建议按本文从本地环境重新执行。

## Prerequisites

### Environment

- Python `3.9+`
- 本地可访问的 `Postgres`
- Olist 原始 `CSV` 文件

建议先安装依赖：

```bash
python -m pip install -r requirements.txt
python -m pip install -e .
```

可选的无数据库 smoke check：

```bash
python -m compileall src
python -m unittest
```

相关文件：[`../requirements.txt`](../requirements.txt)、[`../setup.py`](../setup.py)、[`../tests/test_repo_layout.py`](../tests/test_repo_layout.py)

### Local files

导入脚本默认读取仓库根目录下的 `data/`（即 `./data/`）中的以下文件：

- `olist_orders_dataset.csv`
- `olist_customers_dataset.csv`
- `olist_order_items_dataset.csv`
- `olist_order_payments_dataset.csv`
- `olist_order_reviews_dataset.csv`
- `olist_products_dataset.csv`
- `olist_sellers_dataset.csv`
- `product_category_name_translation.csv`

补充说明：`olist_geolocation_dataset.csv` 当前未被导入脚本和下游模型使用，可视为超出当前仓库范围的附加数据。若想看完整 raw-layer 资产说明，请转到 [`data_dictionary.md`](data_dictionary.md)。

### Environment variables

- 本项目的 Python 执行链路并不强依赖 `DATABASE_URL`；它只是一个为了降低本地配置摩擦的可选统一入口
- 若不使用 `DATABASE_URL`，也可以设置 `DB_USER`、`DB_PASS`、`DB_HOST`、`DB_PORT`、`DB_NAME`
- 可选变量：`DATA_DIR`（默认 `./data`）、`RAW_SCHEMA`（默认 `olist`）

建议先参考 [`.env.example`](../.env.example)。相关代码入口：[`../src/ecommerce_analytics_pipeline/ingest.py`](../src/ecommerce_analytics_pipeline/ingest.py)、[`../src/ecommerce_analytics_pipeline/phase1_ingest.py`](../src/ecommerce_analytics_pipeline/phase1_ingest.py)、[`../src/ingest/load_data.py`](../src/ingest/load_data.py)

## Phase 1: Ingestion

目标：把本地 `CSV` 导入 `RAW_SCHEMA`（默认 `olist`）下的 raw tables。

推荐入口：

```bash
python -m ecommerce_analytics_pipeline.ingest
```

兼容入口：

```bash
python src/ingest/load_data.py
```

相关代码：[`../src/ecommerce_analytics_pipeline/ingest.py`](../src/ecommerce_analytics_pipeline/ingest.py)、[`../src/ecommerce_analytics_pipeline/phase1_ingest.py`](../src/ecommerce_analytics_pipeline/phase1_ingest.py)

完成后应看到：

- raw tables 被创建在 `RAW_SCHEMA` 下（默认 `olist`）
- 当前导入脚本会处理上文列出的 8 个核心文件
- `id` 类字段按字符串读取，避免前导零丢失

## Phase 2: Warehouse Models

目标：基于 raw tables 构建 `analysis.*` 表。

如果你想走“一个变量贯穿本地链路”的方式，可以额外导出 `DATABASE_URL`；如果你在 Phase 1 只配置了离散环境变量，到了 `psql` 这一步也可以继续使用你自己的 `libpq` 认证方式或按实际环境改写命令。下方示例命令使用 `DATABASE_URL` 只是为了演示单变量工作流，不代表项目本身强依赖它。

补充说明：`psql "$DATABASE_URL"` 是 Bash 风格写法；如果你在 PowerShell 或 `CMD` 中执行，请按对应 shell 的变量展开方式改写。

执行顺序：

```bash
psql "$DATABASE_URL" -f sql/models/20_obt/create_obt.sql
psql "$DATABASE_URL" -f sql/models/10_atomic/create_items_atomic.sql
psql "$DATABASE_URL" -f sql/models/30_user/create_user_first_order.sql
psql "$DATABASE_URL" -f sql/analyses/analysis_rfm.sql
```

各脚本职责：

- [`../sql/models/20_obt/create_obt.sql`](../sql/models/20_obt/create_obt.sql)：创建 `analysis.analysis_orders_obt`，定义 delivered-only 的订单粒度体验主干
- [`../sql/models/10_atomic/create_items_atomic.sql`](../sql/models/10_atomic/create_items_atomic.sql)：创建 `analysis.analysis_items_atomic`，把品类与卖家信息贴到 item 粒度
- [`../sql/models/30_user/create_user_first_order.sql`](../sql/models/30_user/create_user_first_order.sql)：创建 `analysis.analysis_user_first_order` 与 `analysis.analysis_user_first_order_categories`
- [`../sql/analyses/analysis_rfm.sql`](../sql/analyses/analysis_rfm.sql)：创建 `analysis.analysis_user_metrics` 与 `analysis.analysis_user_rfm`

重要提醒：

- [`../sql/models/20_obt/create_obt.sql`](../sql/models/20_obt/create_obt.sql) 会 `DROP SCHEMA IF EXISTS analysis` 并重新创建 `analysis`
- 其他建表脚本也会执行 `DROP TABLE IF EXISTS`
- 不要把这套 SQL 直接指向共享数据库或含有其他对象的 schema

## Phase 3: DQ Gates

目标：在解释 notebook 之前，先确认关键指标口径没有被 fan-out、缺失值和桥表错误污染。

执行顺序：

```bash
psql "$DATABASE_URL" -f sql/dq/check_obt.sql
psql "$DATABASE_URL" -f sql/dq/check_user_first_order.sql
```

相关脚本：[`../sql/dq/check_obt.sql`](../sql/dq/check_obt.sql)、[`../sql/dq/check_user_first_order.sql`](../sql/dq/check_user_first_order.sql)

通过标准：

- `check_obt.sql`
  - `obt_rows == raw_rows`
  - `duplicate_orders == 0`
  - `null_users` 与 `null_delays` 接近 `0`
  - `invalid_has_review == 0`
  - `invalid_review_score_domain == 0`
  - `has_review_mismatch == 0`
  - `ontime_but_positive_delay == 0`
  - `late_but_non_positive_delay == 0`
- `check_user_first_order.sql`
  - `first_order_rows == first_order_users == obt_users`
  - `first_order_duplicate_users == 0`
  - `first_order_categories_duplicate_pairs == 0`
  - `first_order_null_required == 0`
  - `first_order_missing_in_obt == 0`
  - `first_order_fk_mismatch == 0`
  - `first_order_tie_break_mismatch == 0`
  - `users_missing_first_order_categories` 应接近 `0`

说明：`analysis.analysis_user_metrics` / `analysis.analysis_user_rfm` 没有独立的 DQ 脚本，当前主要依赖上游门禁与 [`../sql/analyses/analysis_rfm.sql`](../sql/analyses/analysis_rfm.sql) 内的用户行数 sanity check。

## Phase 4: Analytics Notebooks

目标：在通过 DQ 门禁后，复现仓库的三个分析主题。

启动：

```bash
jupyter lab
```

推荐顺序：

- [`../notebooks/01_obt_feature_analysis.ipynb`](../notebooks/01_obt_feature_analysis.ipynb)
- [`../notebooks/02_repurchase_diagnosis.ipynb`](../notebooks/02_repurchase_diagnosis.ipynb)
- [`../notebooks/03_seller_hook_analysis.ipynb`](../notebooks/03_seller_hook_analysis.ipynb)

各 notebook 的主要依赖与输出：

- `01_obt_feature_analysis`
  - 主要依赖：`analysis.analysis_orders_obt`
  - 关注主题：履约断崖、差评风险基线
  - 典型图表：[`../outputs/figures/fig_01_odds_ratio.png`](../outputs/figures/fig_01_odds_ratio.png)、[`../outputs/figures/fig_01_roc_curve.png`](../outputs/figures/fig_01_roc_curve.png)
- `02_repurchase_diagnosis`
  - 主要依赖：`analysis.analysis_user_metrics`、`analysis.analysis_user_rfm`
  - 关注主题：`eligible_repurchase_90d` 下的低复购现实、LTV 窗口比较
  - 典型图表：[`../outputs/figures/fig_02_ltv90_vs_ltvlong.png`](../outputs/figures/fig_02_ltv90_vs_ltvlong.png)、[`../outputs/figures/fig_02_top3_state_delay_by_repurchase.png`](../outputs/figures/fig_02_top3_state_delay_by_repurchase.png)
- `03_seller_hook_analysis`
  - 主要依赖：`analysis.analysis_items_atomic`、`analysis.analysis_user_first_order_categories`
  - 额外依赖：raw `olist_order_items_dataset` 中的 `shipping_limit_date`，以及 raw `olist_sellers_dataset` 中的 `seller_state`
  - 关注主题：钩子品类筛选、卖家治理队列、ROI sensitivity
  - 典型图表：[`../outputs/figures/fig_03_hook_category_matrix.png`](../outputs/figures/fig_03_hook_category_matrix.png)、[`../outputs/figures/fig_03_seller_governance_matrix.png`](../outputs/figures/fig_03_seller_governance_matrix.png)、[`../outputs/figures/fig_03_roi_sensitivity_heatmap.png`](../outputs/figures/fig_03_roi_sensitivity_heatmap.png)

## Verification Checklist

- raw tables 已落到 `RAW_SCHEMA`（默认 `olist`）
- `analysis.analysis_orders_obt`、`analysis.analysis_items_atomic`、`analysis.analysis_user_first_order`、`analysis.analysis_user_first_order_categories`、`analysis.analysis_user_metrics`、`analysis.analysis_user_rfm` 全部可查询
- [`../sql/dq/check_obt.sql`](../sql/dq/check_obt.sql) 与 [`../sql/dq/check_user_first_order.sql`](../sql/dq/check_user_first_order.sql) 的关键异常字段为 `0` 或接近 `0`
- 三个 notebook 能按顺序执行，且图表已落到 `../outputs/figures/`
- 若只做仓库级 smoke check，至少确认 [`../tests/test_repo_layout.py`](../tests/test_repo_layout.py) 可通过

## Troubleshooting

- `Schema mismatch`：SQL 中使用 `Olist.olist_*`（未加引号），在 `Postgres` 中通常会解析成小写 `olist`；推荐保持 `RAW_SCHEMA=olist`，避免 raw schema 与 SQL 脱节。
- `DATABASE_URL`：Python 入口并不强依赖它；如果你想减少本地配置摩擦，可以额外导出一个连接串，复用到 `python` 和 `psql` 示例。若没有该变量，请按你的 shell / `libpq` 方式改写命令即可。
- `Destructive SQL`：`create_obt.sql` 会重建整个 `analysis` schema，其他模型脚本也会 drop table；共享环境务必谨慎。
- `Notebook 03 raw dependency`：卖家治理分支不仅依赖 `analysis.*`，还依赖 raw `olist_order_items_dataset` 与 `olist_sellers_dataset`；如果这两张 raw 表不完整，notebook 03 会直接失真。
- `Time semantics`：`carrier_ts` 可能为空，`delay_days` 允许为负；若迁移到真实业务数据，请先明确时区、缺失值和退款/取消规则，再复用当前口径。
- `Secrets`：数据库凭证只放在本地环境变量或 `.env`，不要提交到仓库。

## Related Docs

- 主入口：[`../README.md`](../README.md)
- 执行报告：[`execution_report.md`](execution_report.md)
- 指标定义：[`data_dictionary.md`](data_dictionary.md)
- schema / path 约定：[`../configs/config.yml`](../configs/config.yml)
