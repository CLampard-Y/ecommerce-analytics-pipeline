# Olist E-commerce Analytics Pipeline

> DA case study: **Fulfillment experience -> Reviews -> Retention/Repurchase** (Olist dataset, Postgres as an analytics warehouse).

[![Python](https://img.shields.io/badge/Python-3.9%2B-blue)](https://www.python.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-13%2B-blue)](https://www.postgresql.org/)

---

## Executive Summary

**Business Problem:** Decision-makers need defensible answers to:
- "(客户) 体验下降悬崖"在哪里? (which orders to rescue)?
- 在低复购率的情况下如何寻找增长点? (which categories to invest)?
- 卖家如何进行进一步优化治理? (which sellers to govern)?

业务侧常把“差评/投诉/退款/低复购”简化为“物流慢”。如果没有一条稳定的指标链路（raw -> warehouse -> analysis），这些问题很容易被错误 JOIN、口径漂移与脏数据放大成“漂亮但错的结论”。

**Solution:** 用工程化 ELT 固化口径，把“体验 -> 增长/治理”拆成三条可落地的分析主线：
- **Fulfillment -> Review:** 用订单级 OBT 把履约拆解为可解释的时间段，并识别非线性断崖
- **Hook Category -> Retention:** 在低复购约束下，用“首单品类 -> 后续复购”衡量获客质量与入口品类
- **Seller SLA -> Risk/ROI:** 把“晚到”从卖家与物流中解耦，定位责任方，并估算治理的风险敞口与回报

**Impact Framing (Interview-ready):**
- **Nonlinearity cliff:** 重点防止订单跨过 `Late_Small -> Late_Severe` 的断崖（断崖附近的体验 ROI 往往是“凸”的）
- **Metric decoupling:** 在追责前先拆分“卖家导致的延迟”和“物流导致的延迟”，避免治理对象错配
- **Exposure/ROI sensitivity:** 用风险敞口 + 情景敏感性（breach reduction x margin - cost）做治理决策，而不是拍脑袋承诺固定 uplift

**Key Findings (Reproducible):**
- Experience: "延迟交付时间 vs 评分" 是负相关的非线性关系  (`Pearson=-0.2609`, `Spearman=-0.3157`)
- Ops: 延迟交付时间中"评分悬崖"的存在 
(`Late_Small median=4.0` -> `Late_Severe median=1.0`)
- Growth: 低复购率的存在; 用户的 90 天 LTV 和长期 LTV 极其接近
- Acquisition: 通过探索 "first-order category -> 90d repurchase" 这个链路, 发现了购买之后复购率高于基线的品类-- "钩子品类" (详细见 notebooks/03_seller_hook_analysis.ipynb)
- Supply: 通过`shipping_limit_date`（SLA）+ 公平性校准对违约卖家进行分析；存在风险的商品交易额（GMV）敞口达到 `263,811.44`，平均违约率`29.6%`

---

## Project Overview

**Dataset:** Kaggle 的 Olist Brazilian E-commerce Public Dataset。

**Goal:** 输出“业务侧可辩护的结论”，而不是“堆技术名词”。通过工程化 ELT 固化口径，确保每一句业务结论都能追溯到：
- 哪张表、什么粒度（grain）、用什么主键（PK）
- 为什么不会被 fan-out 复制放大（尤其是 GMV）
- 哪些 DQ gate 约束会先行卡住（fail-fast）

**Interview Checklist (Buzzwords With Receipts):**
- `DQ gate`：`sql/dq/check_obt.sql` 做行数/金额一致性与 anti-fan-out 约束；`sql/dq/check_user_first_order.sql` 验证 user-grain 衍生模型
- `Grain`：order-level OBT (`order_id`), item-level atomic (`order_id, order_item_id`), user-category bridge（首单品类桥表，避免分母错误）
- `Right-censoring`：复购用 90d eligible window 口径，避免样本尾部低估
- `Nonlinearity cliff`：迟到分桶的评分断崖驱动运营优先级
- `Metric decoupling`：用 `shipping_limit_date` vs `carrier_date` 做卖家 vs 物流归因
- `Fairness calibration`：州内基准校准卖家表现（`performance_gap`）
- `Exposure/ROI sensitivity`：治理用“风险敞口 x 违约率改进 x 成本”做敏感性分析

**Notes:** 项目推进依据包括：ELT 取舍、入库策略、OBT 验收、履约归因、RFM/LTV 与供给侧诊断思路。

---

## Table of Contents

- [Repo Structure](#repo-structure)
- [Stakeholder-ready Summary](#stakeholder-ready-summary)
- [Business Questions Answered](#business-questions-answered)
- [Architecture (Phases)](#architecture-phases)
- [Reproducibility (Optional)](#reproducibility-optional)
- [Warehouse Models](#warehouse-models)
- [Data Quality Gate (DoD)](#data-quality-gate-dod)
- [Analytics Notebooks](#analytics-notebooks)
- [Important Gotchas](#important-gotchas)

---

## Repo Structure

```
configs/     # centralized config (non-secret)
data/        # local CSVs (gitignored by default)
docs/        # runbook + data dictionary + project notes
notebooks/   # analysis notebooks (mainly analysis.*; 03 also reads raw Olist.* for seller SLA inputs)
outputs/     # generated artifacts (gitignored)
sql/         # warehouse models + analyses + dq gates
src/         # installable python package
tests/       # lightweight smoke tests
```

---

## Architecture (Phases)

### Phase 0: Data Download & Validation

**Engineering Notes:**
- **ELT trade-off:** 先全量入库 raw，再用 SQL 清洗/建模，迭代更快、可溯源
- **Integrity check:** 推荐为 CSV 生成 `SHA256` 清单（用于二次下载/迁移比对）

### Phase 1: Ingestion Baseline (CSV -> Postgres raw)

**Entrypoints:**
- **Canonical:** `src/ecommerce_analytics_pipeline/phase1_ingest.py`
- **Stable wrapper:** `src/ecommerce_analytics_pipeline/ingest.py`（保持 `python -m` 入口稳定）

**Engineering Guards:**
- `pd.read_csv(..., dtype=str)`：防止 ID/邮编等字段 **前导零丢失**
- `to_sql(..., chunksize=20000, method="multi")`：分块写入 + 批量插入，提升稳定性与速度
- `ensure_schema_exists()`：schema 幂等创建，避免“第一次运行就爆炸”

**DoD:**
- raw schema（默认 `olist`）存在，并能看到 `olist.olist_*` 原始表

### Phase 2: Warehouse Modeling (Atomic -> OBT) + DQ Gate

**SQL Assets:**
- Order-grain OBT: `sql/models/20_obt/create_obt.sql`
- Item-grain atomic: `sql/models/10_atomic/create_items_atomic.sql`
- User-grain models (first-order + bridge): `sql/models/30_user/create_user_first_order.sql`
- RFM/LTV：`sql/analyses/analysis_rfm.sql`
- DQ gates：`sql/dq/check_obt.sql` + `sql/dq/check_user_first_order.sql`

**DoD (Quality Gate):**
- `obt_rows == raw_rows`
- `duplicate_orders == 0`（防 fan-out）
- `null_users`、`null_delays` 约为 0

### Phase 3: Analytics Delivery (Notebooks)

**Notebooks:** 主要依赖 `analysis.*`；其中 03 的卖家 SLA 治理会额外读取 raw `Olist.*` 的 `shipping_limit_date` / `seller_state` 作为输入。
- `notebooks/01_obt_feature_analysis.ipynb`：履约延迟 vs 评分（相关 + Logit 归因）
- `notebooks/02_repurchase_diagnosis.ipynb`：复购率（含 90d 窗口右删失）、LTV90 vs 长期 LTV、T-Test（含分层防御）
- `notebooks/03_seller_hook_analysis.ipynb`：钩子品类（首单 -> 复购）与供给侧诊断入口 + 供给侧治理/ROI

---

## Stakeholder-ready Summary

Fast takeaways: what to fix, what to do, and how to measure it.

**1) Fulfillment experience (OnTime -> Late_Small -> Late_Severe)**
- **Finding:** 评分存在明显 **nonlinearity cliff**：`Late_Small (median=4.0)` -> `Late_Severe (median=1.0)`。
- **Action:** 运营资源优先投入“避免恶化”（重点拯救 `Late_Small`），而不是把“提前送达”当作 KPI。
- **KPI:** `Late_Severe` 占比、`Late_Small -> Late_Severe` 转化率、差评率（`has_review=1` 且 `review_score <= 2`）。

**2) Growth under low repurchase constraint**
- **Finding:** 在 **90d window + right-censoring defense** 口径下，平台复购偏低，“高频复购”不是安全假设。
- **Action:** 用“首单品类 -> 90d 复购”衡量获客质量，对钩子品类倾斜预算（如 `fashion_bags_accessories`, `bed_bath_table`, `sports_leisure`）。
- **KPI:** 新客 cohort 的复购率/LTV90、钩子品类的新客占比、获客渠道的 LTV/CAC。

**3) Supply governance (metric decoupling + seller SLA)**
- **Finding:** 晚到不等于卖家有责；`shipping_limit_date` vs `carrier_date` 可以做 **metric decoupling**（卖家 vs 物流）。
- **Action:** 先做州内 **fairness calibration**，再用“GMV 贡献 x 相对违约率”治理矩阵做分层治理。
- **Exposure:** 坏卖家经手 `price` 汇总（GMV proxy）`263,811.44`，平均 SLA 违约率 `29.6%`（治理收益在 notebook 做了敏感性分析）。

**Execution Plan (From Analysis to Action)**
- Product/Ops: 上线 `Late_Small` 预警队列与干预策略（改地址/补偿/加急），并以“避免恶化”为目标函数
- Growth: 在投放侧引入钩子品类的质量权重（cohort 复购率/LTV90），做预算倾斜与路径实验
- Supply: 按治理矩阵分层执行（清退/监管/扶持），并把 `performance_gap` 纳入卖家评级

**Assumptions & Risks**
- 数据是公开数据集（Olist），可验证方法论与口径，但不等同于线上实时系统；落地需要补充时区、退款/取消订单、客服触达等业务信号

---

## Business Questions Answered

This section maps each question to definitions and actions (question -> metric -> decision).

1) **Fulfillment -> Review: where is the cliff?**
- **Observation:** `Late_Small -> Late_Severe` 评分中位数从 `4.0` 跌到 `1.0`。
- **Decision:** 把资源投在 **避免订单从轻微延迟恶化为严重延迟**（黄金救援期），而不是把“提前送达”当 KPI。

2) **Growth under low repurchase: what is the best acquisition proxy?**
- **Observation:** 以“首单品类 -> 90d 窗口复购”为口径，钩子品类显著高于大盘基准线（见 notebook 输出）。
- **Decision:** 把获客预算从“只看 GMV”升级为“看 **首单带来的留存质量**”，用钩子品类做流量入口。

3) **Accountability: carrier vs seller, and how to govern fairly?**
- **Method:** 用 `shipping_limit_date` vs `carrier_date` 构建 `is_sla_breach`（卖家责任），并按州做基准校准（公平性）。
- **Observation:** 坏卖家经手 `price` 汇总（GMV proxy）`263,811.44`，平均违约率 `29.6%`，存在集中治理空间。
- **Decision:** 建立“**治理矩阵（GMV 贡献 x 相对违约率）**”，区分清退/重点监督/扶持/长尾自动化。

---

## Reproducibility (Optional)

**Delivery style:** notebook-first 交付；关键输出（图表/统计量/结论）已经固化在 notebooks 的执行结果中。

如果你想在本地复现完整链路，请直接看：`docs/runbook.md`。

**Fast path (optional):**
- 配置环境变量（参考 `.env.example`）
- Entrypoint: `python -m ecommerce_analytics_pipeline.ingest`
- 构建数仓与 DQ：`sql/models/*` + `sql/dq/check_obt.sql`

---

## Warehouse Models

### `analysis.analysis_orders_obt` (Order-grain OBT)

**Definition:** 以 `order_id` 为粒度，聚合并连接 orders / customers / items / payments / reviews，产出可直接做分析的订单宽表。

**Key Metrics (precomputed in OBT):**
- `delay_days`：`delivered_ts - estimated_ts`（正数=晚到；负数/0=提前或准时）
- `delivery_status`：`OnTime` / `Late_Small` (<=3 days) / `Late_Severe` (>3 days)
- `gmv`：payments 聚合后的订单 GMV（用于金额一致性校验）

**Design Notes:**
- **Aggregate before join:** items/payments 在 JOIN 前先 `GROUP BY order_id`，避免 fan-out。
- **Defensive computations:** `NULLIF(items_cnt, 0)` 防止分母为 0；`COALESCE` 兜底空值。
- **OLAP-friendly indexes:** `user_id`、`purchase_ts`、`delivery_status`、`purchase_month`。

### `analysis.analysis_items_atomic` (Item-grain atomic)

**Definition:** 以 (order_id, order_item_id) 为粒度，把 item 与 OBT 的体验指标（评分、延迟）拼起来，并带上品类英文名，为钩子品类/供给侧诊断提供最细颗粒度输入。

### `analysis.analysis_user_first_order` / `analysis.analysis_user_first_order_categories` (User-grain + Bridge)

**Definition:**
- `analysis_user_first_order`：每个 `user_id` 的首个已送达订单（deterministic tie-breaker）。
- `analysis_user_first_order_categories`：首单涉及的品类桥表（grain: `user_id, category`），用于“首单品类 -> 复购”分析，避免 item 粒度导致分母错误。

---

## Data Quality Gate (DoD)

**Run:**
- `sql/dq/check_obt.sql`
- `sql/dq/check_user_first_order.sql`（如你要跑“首单品类 -> 复购”链路）

**What to check:** 你应该看到一行结果，重点盯这些字段（核心 + 防御性检查）：
- `obt_rows` vs `raw_rows`：宽表没有“意外丢单”
- `obt_gmv` vs `raw_gmv`：没有“金额被复制放大”
- `duplicate_orders`：必须为 0（否则典型 fan-out）
- `null_users` / `null_delays`：关键分析字段完整
- `invalid_review_score_domain` / `has_review_mismatch`：评价字段口径正确（缺失不等于 0 分）
- `ontime_but_positive_delay` / `late_but_non_positive_delay`：`delay_days` 与 `delivery_status` 一致性（避免 EXTRACT(DAY) 截断导致打架）

---

## Analytics Notebooks

**Canonical order (matches the repo):**
`01_obt_feature_analysis` -> `02_repurchase_diagnosis` -> `03_seller_hook_analysis`.

### 01 - OBT Feature Analysis (Fulfillment -> Review)

**What it answers:** 履约指标如何传导到体验指标，以及 **nonlinearity cliff** 出现在哪个延迟区间。

**Typical outputs & decisions:**
- `Pearson=-0.2609` / `Spearman=-0.3157`：延迟与评分负相关且存在非线性（不要用“线性扣分”的直觉做决策）
- Cliff：`Late_Small (median=4.0)` -> `Late_Severe (median=1.0)`
- Decision：把监控/客服/物流资源优先投入在 **prevent deterioration**（拯救 `Late_Small`），而不是追求“更提前”

### 02 - Repurchase Diagnosis (RFM/LTV + T-Test)

**What it answers:** 在 **right-censoring** 防御下建立复购基线，并检验“体验指标 -> 留存/复购”的关联。

**Typical outputs & decisions:**
- 复购口径使用 **90d eligible window（right-censoring defense）**，避免数据集尾部低估
- Welch's T-Test（`equal_var=False`）：更稳健地比较“复购 vs 流失”的平均延迟差异
- Stratification defense：按州内分层（`primary_state`）降低地理混杂

### 03 - Seller Hook Analysis (Hook Category + Seller Governance)

**What it answers:** 找到获客“钩子”（首单品类 -> 复购），并把分析延伸到供给侧治理（**exposure/ROI sensitivity**）。

**Typical outputs & decisions:**
- Grain control：`analysis.analysis_user_first_order_categories`（user-category bridge）避免 item 粒度导致分母错误
- Hooks：在“首单品类 -> 90d 复购”口径下，钩子品类显著高于基准线（见 notebook 输出）
- Governance：`shipping_limit_date` vs `carrier_date` 构建 `is_sla_breach` 做 **metric decoupling**，再按 `seller_state` 做 **fairness calibration** 得到 `performance_gap`
- ROI：治理矩阵（GMV 贡献 x 相对违约率）+ 对 breach reduction 和 intervention cost 做敏感性分析

---

## Important Gotchas

- **Schema mismatch**：SQL 使用 `Olist.olist_*`（未加引号）。在 Postgres 中，`Olist` 会解析成小写 `olist`。推荐统一使用 `RAW_SCHEMA=olist`。
- **Destructive SQL**：`sql/models/20_obt/create_obt.sql` 会 `DROP SCHEMA IF EXISTS analysis;` 并重建。不要对共享/生产库运行。
- **Secrets**：数据库密码请用环境变量或本地 `.env`；不要提交到版本库。
- **.env template**：见 `.env.example`（只放占位符，不要放真实口令）。
- **Time semantics**：履约链路包含多个 timestamp 字段；如迁移到真实业务数据，需要明确时区与缺失值规则。

---

## References

- Olist dataset (Kaggle): https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
- Project runbook: `docs/runbook.md`
