# Olist E-commerce Analytics Pipeline

> 以 Olist 电商数据为例，先建立 `metric trust`，再定位 `fulfillment cliff`，最后在低复购约束下拆解 `hook category` 与 `seller governance` 两条动作分支。

[![Python](https://img.shields.io/badge/Python-3.10%2B-blue)](https://www.python.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-warehouse-blue)](https://www.postgresql.org/)

Quick navigation: [Start Here](#start-here) · [Key Results](#key-results) · [Decision Snapshot](#decision-snapshot) · [Documentation Map](#documentation-map) · [Quickstart](#quickstart) · [Limitations](#limitations)

## Overview

本仓库围绕一条可复现的批处理分析链路展开：本地 `CSV` -> `Postgres` -> `SQL models` -> `DQ gates` -> `notebooks`。重点不是把所有现象都简化成“物流慢”，而是先把指标口径、粒度和分母控制住，再解释结果。

当前仓库更适合按以下顺序理解：

- `Metric trust`：先拆开 order / item / user 三层粒度，用 [`sql/dq/check_obt.sql`](sql/dq/check_obt.sql) 和 [`sql/dq/check_user_first_order.sql`](sql/dq/check_user_first_order.sql) 守住行数、金额、唯一性和首单桥表口径。
- `Fulfillment cliff`：在 delivered-order 范围内，最稳定的体验损伤信号不是“越早越好”，而是延迟从 `Late_Small` 跨到 `Late_Severe` 时评分明显恶化。
- `Low-repurchase reality`：`90d` 复购必须基于 `eligible_repurchase_90d` 解释；仓库证据支持的是低复购现实，而不是高频复购平台假设。
- `Action branches`：在这个约束下，把首单品类用于获客入口筛选，把卖家分群用于治理队列优先级；二者都是 prioritization 工具，不是直接的因果归因。

执行故事、详细定义与复现路径已分别拆分到 [`docs/execution_report.md`](docs/execution_report.md)、[`docs/data_dictionary.md`](docs/data_dictionary.md) 与 [`docs/runbook.md`](docs/runbook.md)，避免主 README 同时承担入口、执行归档、执行手册和指标字典四种角色。

## Start Here

- `30 sec`: 先看 [Key Results](#key-results) 和 [Decision Snapshot](#decision-snapshot)，快速把握仓库主线。
- `2 min`: 阅读 [`docs/execution_report.md`](docs/execution_report.md)，先理解这条主线是如何从原始推进思路收敛成当前仓库叙事的。
- `5 min`: 阅读 [`docs/data_dictionary.md`](docs/data_dictionary.md)、[`sql/dq/check_obt.sql`](sql/dq/check_obt.sql)、[`sql/dq/check_user_first_order.sql`](sql/dq/check_user_first_order.sql)、[`sql/analyses/analysis_rfm.sql`](sql/analyses/analysis_rfm.sql)，再确认粒度、分母和 `90d` 窗口口径。
- `10 min`: 按顺序看 [`notebooks/01_obt_feature_analysis.ipynb`](notebooks/01_obt_feature_analysis.ipynb)、[`notebooks/02_repurchase_diagnosis.ipynb`](notebooks/02_repurchase_diagnosis.ipynb)、[`notebooks/03_seller_hook_analysis.ipynb`](notebooks/03_seller_hook_analysis.ipynb)，并结合 [`outputs/figures/fig_01_odds_ratio.png`](outputs/figures/fig_01_odds_ratio.png)、[`outputs/figures/fig_02_ltv90_vs_ltvlong.png`](outputs/figures/fig_02_ltv90_vs_ltvlong.png)、[`outputs/figures/fig_03_hook_category_matrix.png`](outputs/figures/fig_03_hook_category_matrix.png)、[`outputs/figures/fig_03_seller_governance_matrix.png`](outputs/figures/fig_03_seller_governance_matrix.png)、[`outputs/figures/fig_03_roi_sensitivity_heatmap.png`](outputs/figures/fig_03_roi_sensitivity_heatmap.png)。
- `Reproduce locally`: 从 [`docs/runbook.md`](docs/runbook.md) 开始，再配合 [`.env.example`](.env.example)、[`requirements.txt`](requirements.txt) 和 [`setup.py`](setup.py) 配置本地环境。

## Key Results

下表只保留仓库中可直接核验的核心结果，详细定义见 [`docs/data_dictionary.md`](docs/data_dictionary.md)，执行路径见 [`docs/runbook.md`](docs/runbook.md)。这些数字按当前仓库已提交的 notebook 输出与图表快照整理，若未来重跑 notebook，应以最新产物为准。

| 模块 | 已核验结果 | 证据 |
|---|---|---|
| 指标可信性 | [`sql/dq/check_obt.sql`](sql/dq/check_obt.sql) 守住 `obt_rows == raw_rows`、GMV 一致性、重复订单、评价域和延迟/状态一致性；[`sql/dq/check_user_first_order.sql`](sql/dq/check_user_first_order.sql) 守住用户首单映射与首单品类桥表口径 | [`sql/dq/check_obt.sql`](sql/dq/check_obt.sql), [`sql/dq/check_user_first_order.sql`](sql/dq/check_user_first_order.sql) |
| 履约断崖 | 评价覆盖率 `99.33%`；`delay_days_clipped` 与评分负相关（`Pearson=-0.2719`，`Spearman=-0.2999`）；`Late_Small` 到 `Late_Severe` 的评分中位数从 `4.0` 降到 `1.0` | [`notebooks/01_obt_feature_analysis.ipynb`](notebooks/01_obt_feature_analysis.ipynb) |
| 差评风险基线 | 在标准化数值特征上，`delay_days` 是差评模型里最强的解释变量之一（`OR=2.2048`）；当前 `ROC-AUC=0.6987` 仅表示仓库内的 in-sample 描述性基线 | [`notebooks/01_obt_feature_analysis.ipynb`](notebooks/01_obt_feature_analysis.ipynb), [`outputs/figures/fig_01_odds_ratio.png`](outputs/figures/fig_01_odds_ratio.png), [`outputs/figures/fig_01_roc_curve.png`](outputs/figures/fig_01_roc_curve.png) |
| 低复购现实 | 在 `eligible_repurchase_90d=1` 的用户分母上，`90d` 复购率为 `1.30%`；`monetary_90d` 与 `monetary_long` 均值接近（`163.53` vs `165.20`） | [`sql/analyses/analysis_rfm.sql`](sql/analyses/analysis_rfm.sql), [`notebooks/02_repurchase_diagnosis.ipynb`](notebooks/02_repurchase_diagnosis.ipynb), [`outputs/figures/fig_02_ltv90_vs_ltvlong.png`](outputs/figures/fig_02_ltv90_vs_ltvlong.png) |
| 钩子品类 | 相对 `1.30%` 大盘基线，`fashion_bags_accessories=2.50% (36/1442)`、`bed_bath_table=2.00% (144/7183)`、`sports_leisure=1.65% (100/6070)` 更像首单入口筛选候选，而不是品类因果 lift | [`sql/models/30_user/create_user_first_order.sql`](sql/models/30_user/create_user_first_order.sql), [`notebooks/03_seller_hook_analysis.ipynb`](notebooks/03_seller_hook_analysis.ipynb), [`outputs/figures/fig_03_hook_category_matrix.png`](outputs/figures/fig_03_hook_category_matrix.png) |
| 卖家治理 | 在 notebook 当前规则下（`order_volume > 30`、`performance_gap > 5pp`、按卖家 item `price` 汇总中位数分层），`58/611` 活跃卖家 (`9.5%`) 落入 `Bad`；其 breach-concentration proxy 约 `15.4%`，item-price exposure proxy 为 `263,811.44`，平均 breach rate 为 `29.6%` | [`notebooks/03_seller_hook_analysis.ipynb`](notebooks/03_seller_hook_analysis.ipynb), [`outputs/figures/fig_03_seller_governance_matrix.png`](outputs/figures/fig_03_seller_governance_matrix.png), [`outputs/figures/fig_03_roi_sensitivity_heatmap.png`](outputs/figures/fig_03_roi_sensitivity_heatmap.png) |

## Decision Snapshot

- `Metric trust`：先过 [`sql/dq/check_obt.sql`](sql/dq/check_obt.sql) 和 [`sql/dq/check_user_first_order.sql`](sql/dq/check_user_first_order.sql)，再解释图表；否则很容易把 fan-out、缺失值和分母漂移误当成业务信号。
- `Fulfillment cliff`：当前更值得监控的是 `Late_Small -> Late_Severe` 的恶化边界，而不是把“更提前送达”直接当作单一 KPI。
- `Low-repurchase reality`：[`sql/analyses/analysis_rfm.sql`](sql/analyses/analysis_rfm.sql) 用 `eligible_repurchase_90d` 守住右删失边界，说明这个样本更像低复购平台，后续动作应回到入口质量和供给稳定性。
- `Action branches`：首单品类分支用于筛选更值得继续实验的获客入口；卖家治理分支用 seller-side SLA proxy、州内基准和情景敏感性分析收缩治理队列，二者都不直接承诺固定 uplift。

## Documentation Map

| 如果你想看 | 去哪里 | 为什么从这里开始 |
|---|---|---|
| 仓库主线和核心结果 | [`README.md`](README.md) | 先把问题定义、证据层级和边界看清楚 |
| 执行故事与方法取舍 | [`docs/execution_report.md`](docs/execution_report.md) | 这里把旧推进思路提炼成当前仓库真正保留的 execution story |
| 指标定义、粒度和分母 | [`docs/data_dictionary.md`](docs/data_dictionary.md) | 这里是表结构、字段口径和解释边界的定义源 |
| DQ 门禁与 `90d` 口径 | [`sql/dq/check_obt.sql`](sql/dq/check_obt.sql), [`sql/dq/check_user_first_order.sql`](sql/dq/check_user_first_order.sql), [`sql/analyses/analysis_rfm.sql`](sql/analyses/analysis_rfm.sql) | 在进 notebook 之前，先确认 grain、分母和 right-censoring 定义 |
| notebook 结果 | [`notebooks/01_obt_feature_analysis.ipynb`](notebooks/01_obt_feature_analysis.ipynb), [`notebooks/02_repurchase_diagnosis.ipynb`](notebooks/02_repurchase_diagnosis.ipynb), [`notebooks/03_seller_hook_analysis.ipynb`](notebooks/03_seller_hook_analysis.ipynb) | 分别对应履约断崖、低复购现实和两条动作分支 |
| 执行路径与命令 | [`docs/runbook.md`](docs/runbook.md) | 最后回到这里做完整复现，按阶段执行导入、建模、DQ 和 notebook |
| OBT 建表逻辑 | [`sql/models/20_obt/create_obt.sql`](sql/models/20_obt/create_obt.sql) | 订单粒度体验主干与 delivered-only 范围都在这里定义 |
| 首单桥表与钩子品类口径 | [`sql/models/30_user/create_user_first_order.sql`](sql/models/30_user/create_user_first_order.sql) | 明确“首单”是首个 delivered 订单，以及品类桥表如何去重 |

## Repository Guide

```text
configs/   配置与 schema 约定（见 configs/config.yml）
data/      本地 CSV 工作目录；当前仓库可能保留了快照文件便于浏览
docs/      README 之外的执行说明与指标字典
notebooks/ 三个分析 notebook，03 额外读取 raw Olist.* 表
outputs/   notebook 导出的图表快照
sql/       建模 SQL、分析 SQL 与 DQ 门禁
src/       可安装的 Python 包与 ingestion 入口
tests/     轻量 smoke tests
```

## Quickstart

在仓库根目录执行：

### 1) Install dependencies

```bash
python -m pip install -r requirements.txt
python -m pip install -e .
```

说明：`pip install -e .` 用于让 [`src/ecommerce_analytics_pipeline/ingest.py`](src/ecommerce_analytics_pipeline/ingest.py) 这类模块入口可直接通过 `python -m ecommerce_analytics_pipeline.ingest` 调用；如果你只打算使用兼容入口 `python src/ingest/load_data.py`，则可以不安装 editable package。

### 2) Configure environment

- 复制 [`.env.example`](.env.example) 到本地 `.env`
- 本项目的 Python 执行链路并不强依赖 `DATABASE_URL`；它只是一个为了降低本地配置摩擦的可选统一入口
- 如果不用 `DATABASE_URL`，也可以设置 `DB_USER`、`DB_PASS`、`DB_HOST`、`DB_PORT`、`DB_NAME`
- 详细字段说明见 [`docs/runbook.md`](docs/runbook.md)

### 3) Follow the runbook

- 执行数据导入、SQL 建模、DQ 检查与 notebook 复现，请直接按 [`docs/runbook.md`](docs/runbook.md) 的阶段顺序操作
- Phase 1 的 raw baseline 以 8 个 core CSV 为完整输入；当前 ingestion 已改为 fail-fast，缺任意一个文件都会直接退出，不再允许 silent partial load
- 如果只想做无数据库 smoke check，可先运行 `python -m compileall src` 和 `python -m unittest discover -s tests`（`tests/` 是轻量 contract tests：校验关键资产存在、ingestion fail-fast、schema guardrails）

## Limitations

- 当前 `analysis.analysis_orders_obt` 只覆盖 delivered orders；因此“首单”在本仓库里指首个 delivered 订单，而不是首个下单事件。
- 履约分析目前是历史诊断视角，不是实时监控系统；若未来接入在途履约事件，现有口径可继续扩展，但当前仓库并未实现。
- 卖家治理分支依赖 `shipping_limit_date` vs `carrier_date` 的 seller-side SLA proxy、州内平均基准和 item `price` exposure proxy；它是优先级工具，不是完美归责。
- notebook 01 中的 `ROC-AUC=0.6987` 是 in-sample 描述性结果，不应直接当作可上线的泛化表现。
- 自动化测试较轻；本仓库更依赖 SQL DQ 门禁与 notebook 结果快照来支撑解释。
- `data/` 与 `outputs/` 通常作为本地工作目录使用；当前仓库保留了部分快照资产便于直接浏览，但复现仍应以 [`docs/runbook.md`](docs/runbook.md) 为准。
- Phase 1 的“导入完成”只在 8 个 core CSV 全部存在且成功落库时成立；若 ingestion 提前失败，应先修复 raw baseline，再继续 SQL / notebook。

## References

- Olist dataset (Kaggle): https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
- Reproduction guide: [`docs/runbook.md`](docs/runbook.md)
- Metric definitions: [`docs/data_dictionary.md`](docs/data_dictionary.md)
