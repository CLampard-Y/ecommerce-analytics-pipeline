# Data Dictionary

目标：把仓库里出现的核心指标、表、粒度和分母落到可追溯的定义源上。

Quick navigation: [How to Read](#how-to-read) · [Metric Trust Map](#metric-trust-map) · [Raw Layer](#raw-layer) · [Conventions](#conventions) · [Interpretation Boundaries](#interpretation-boundaries) · [Core Models](#core-models) · [DQ Gates](#dq-gates) · [Related Assets](#related-assets)

## How to Read

读这个文档时，建议先回答四个问题：

- 这个指标来自哪个 grain：`order_id`、`(order_id, order_item_id)` 还是 `user_id`
- 它的主键是什么，是否可能被错误 JOIN 放大
- 它的定义源在什么 SQL 文件里
- 它在解释前需要先通过哪道 DQ gate

如果一个结论说不清这四件事，就不应该直接进入业务解释。

## Metric Trust Map

| 资产 | Grain | 定义来源 | DQ / 验证 | 主要用途 |
|---|---|---|---|---|
| raw `olist.*` tables | 原始记录粒度 | [`../src/ecommerce_analytics_pipeline/phase1_ingest.py`](../src/ecommerce_analytics_pipeline/phase1_ingest.py) | 8 core CSV baseline 完整落库 + schema 对齐 | 作为建模输入 |
| `analysis.analysis_orders_obt` | `order_id` | [`../sql/models/20_obt/create_obt.sql`](../sql/models/20_obt/create_obt.sql) | [`../sql/dq/check_obt.sql`](../sql/dq/check_obt.sql) | 履约、评价、订单金额主干 |
| `analysis.analysis_items_atomic` | `(order_id, order_item_id)` | [`../sql/models/10_atomic/create_items_atomic.sql`](../sql/models/10_atomic/create_items_atomic.sql) | 依赖上游 `OBT` 门禁 | 品类与卖家分析输入 |
| `analysis.analysis_user_first_order` | `user_id` | [`../sql/models/30_user/create_user_first_order.sql`](../sql/models/30_user/create_user_first_order.sql) | [`../sql/dq/check_user_first_order.sql`](../sql/dq/check_user_first_order.sql) | 首单映射 |
| `analysis.analysis_user_first_order_categories` | `(user_id, category)` | [`../sql/models/30_user/create_user_first_order.sql`](../sql/models/30_user/create_user_first_order.sql) | [`../sql/dq/check_user_first_order.sql`](../sql/dq/check_user_first_order.sql) | 钩子品类筛选 |
| `analysis.analysis_user_metrics` | `user_id` | [`../sql/analyses/analysis_rfm.sql`](../sql/analyses/analysis_rfm.sql) | 上游门禁 + 用户行数 sanity check | `90d` 复购、LTV、州信息 |
| `analysis.analysis_user_rfm` | `user_id` | [`../sql/analyses/analysis_rfm.sql`](../sql/analyses/analysis_rfm.sql) | 继承上游验证 | RFM / LTV scoring |

## Raw Layer

当前仓库分析主线以以下 8 个 core CSV 为固定 baseline；它们对应 Phase 1 必须完整落库的 8 张 raw tables，缺一不可：

- [`../data/olist_orders_dataset.csv`](../data/olist_orders_dataset.csv)
- [`../data/olist_customers_dataset.csv`](../data/olist_customers_dataset.csv)
- [`../data/olist_order_items_dataset.csv`](../data/olist_order_items_dataset.csv)
- [`../data/olist_order_payments_dataset.csv`](../data/olist_order_payments_dataset.csv)
- [`../data/olist_order_reviews_dataset.csv`](../data/olist_order_reviews_dataset.csv)
- [`../data/olist_products_dataset.csv`](../data/olist_products_dataset.csv)
- [`../data/olist_sellers_dataset.csv`](../data/olist_sellers_dataset.csv)
- [`../data/product_category_name_translation.csv`](../data/product_category_name_translation.csv)

补充说明：

- [`../src/ecommerce_analytics_pipeline/phase1_ingest.py`](../src/ecommerce_analytics_pipeline/phase1_ingest.py) 当前对这 8 个 core CSV 采用 fail-fast；任意文件缺失或导入失败，Phase 1 都不应被视为完成。
- [`../data/olist_geolocation_dataset.csv`](../data/olist_geolocation_dataset.csv) 当前不在导入脚本的 core CSV baseline 中，也没有进入当前 README 主线中的下游模型。

## Conventions

- `Time`：raw 导入时时间字段先按字符串读取；在 [`../sql/models/20_obt/create_obt.sql`](../sql/models/20_obt/create_obt.sql) 中统一转为 `timestamp` 并派生 `_ts` 字段。
- `Delay sign`：`delay_days > 0` 表示晚到；`delay_days <= 0` 表示准时或提前。
- `Grain guard`：任何来自 item / payment / review 的信息，进入 order 粒度前都必须先按 `order_id` 聚合，避免 fan-out。
- `Delivered-only scope`：当前 `OBT` 只保留 `order_status='delivered'` 且 `order_delivered_customer_date IS NOT NULL` 的订单，因此“首单”在本仓库中是“首个 delivered 订单”。
- `Denominator control`：所有 `90d` 复购口径都必须明确基于 `eligible_repurchase_90d=1` 的用户分母，否则会被右删失机械压低。
- `Review aggregation`：订单可能存在多条评价，当前 `review_score` 使用 `MIN(review_score)` 聚合，强调低分主导的体验判断。

## Interpretation Boundaries

- `Order-grain OBT` 是当前仓库里最稳定的履约体验信号来源。
- `90d` 复购只能在 eligible 用户分母上解释；不满足观察窗口的用户应视为 `NULL`，而不是 `0`。
- 钩子品类分支服务于获客入口筛选，不是品类层面的因果 lift 证明。
- 卖家治理分支依赖 seller-side SLA proxy 和州内基准校准，不是完美归责。
- 卖家治理里的 exposure 使用 item `price` 汇总形成 proxy，不应与订单支付口径的 `GMV` 混为一谈。

## Core Models

### `analysis.analysis_orders_obt`

- `Grain`：1 row per `order_id`，只保留 delivered 且有送达时间的订单
- `Primary key`：`order_id`
- `Built from`：[`olist_orders_dataset.csv`](../data/olist_orders_dataset.csv)、[`olist_customers_dataset.csv`](../data/olist_customers_dataset.csv)、[`olist_order_items_dataset.csv`](../data/olist_order_items_dataset.csv)、[`olist_order_payments_dataset.csv`](../data/olist_order_payments_dataset.csv)、[`olist_order_reviews_dataset.csv`](../data/olist_order_reviews_dataset.csv)
- `Definition source`：[`../sql/models/20_obt/create_obt.sql`](../sql/models/20_obt/create_obt.sql)
- `Used by`：[`../notebooks/01_obt_feature_analysis.ipynb`](../notebooks/01_obt_feature_analysis.ipynb)、[`../sql/analyses/analysis_rfm.sql`](../sql/analyses/analysis_rfm.sql)、[`../sql/models/10_atomic/create_items_atomic.sql`](../sql/models/10_atomic/create_items_atomic.sql)

关键字段：

- `user_id`：来自 `customer_unique_id`，用于用户层分析
- `customer_state`：用户州信息
- `purchase_ts` / `approved_ts` / `carrier_ts` / `delivered_ts` / `estimated_ts`：履约链路关键时间点

关键指标：

- `gmv`：按 `order_id` 聚合 `SUM(payment_value)`，是订单金额主口径
- `items_cnt` / `sellers_cnt`：订单商品数、卖家数
- `items_value` / `freight_value`：item 粒度金额与运费聚合
- `freight_ratio`：`freight_value / gmv`
- `avg_item_price`：`gmv / items_cnt`
- `review_score`：订单评价最低分，用于表达低分主导的体验信号
- `has_review`：是否存在评价，避免把“未评价”误当成低分
- `delay_days`：`delivered_ts - estimated_ts`，单位为天，可为负值
- `delivery_status`：`OnTime` / `Late_Small` / `Late_Severe`
- `approve_hours` / `handling_days` / `shipping_days` / `total_fulfill_days`：履约链路拆解指标

使用注意：

- `carrier_ts` 可能为空，因此 `handling_days` / `shipping_days` 允许为 `NULL`
- `delay_days` 为负不代表可以线性理解成“越早越好”
- `gmv` 与 `items_value` 不要求严格相等；当前仓库以 payments 聚合得到的 `gmv` 为订单金额主口径

### `analysis.analysis_items_atomic`

- `Grain`：1 row per `(order_id, order_item_id)`
- `Primary key`：`(order_id, order_item_id)`
- `Built from`：[`olist_order_items_dataset.csv`](../data/olist_order_items_dataset.csv)、[`olist_products_dataset.csv`](../data/olist_products_dataset.csv)、[`product_category_name_translation.csv`](../data/product_category_name_translation.csv)、[`analysis.analysis_orders_obt`](../sql/models/20_obt/create_obt.sql)
- `Definition source`：[`../sql/models/10_atomic/create_items_atomic.sql`](../sql/models/10_atomic/create_items_atomic.sql)
- `Used by`：[`../sql/models/30_user/create_user_first_order.sql`](../sql/models/30_user/create_user_first_order.sql)、[`../notebooks/03_seller_hook_analysis.ipynb`](../notebooks/03_seller_hook_analysis.ipynb)

关键字段：

- `seller_id`：供给侧主体
- `category`：商品英文品类名
- `price`：item 价格
- `review_score` / `has_review` / `delay_days`：从订单粒度贴到 item 粒度的体验标签
- `is_late`：`delay_days > 0` 的二元标记

使用注意：

- 一个订单可能包含多个卖家，因此“订单晚到”不能直接等同于“某个卖家有责”
- `category` 可能缺失，后续桥表会用 `unknown` 兜底
- 把订单级标签贴到 item 粒度，更适合做筛选与对齐视图，不适合作为完美的 item-level blame assignment

### `analysis.analysis_user_first_order`

- `Grain`：1 row per `user_id`
- `Primary key`：`user_id`
- `Built from`：[`analysis.analysis_orders_obt`](../sql/models/20_obt/create_obt.sql)
- `Definition source`：[`../sql/models/30_user/create_user_first_order.sql`](../sql/models/30_user/create_user_first_order.sql)
- `Used by`：[`analysis.analysis_user_first_order_categories`](../sql/models/30_user/create_user_first_order.sql)、[`../sql/dq/check_user_first_order.sql`](../sql/dq/check_user_first_order.sql)

关键定义：

- 首单定义为用户的首个 delivered 订单
- 若同一用户有多个订单共享最早 `purchase_ts`，按 `(purchase_ts, order_id)` 做确定性 tie-break

关键字段：

- `first_order_id`：首个 delivered 订单
- `first_purchase_ts`：首单购买时间

### `analysis.analysis_user_first_order_categories`

- `Grain`：1 row per `(user_id, category)`
- `Primary key`：`(user_id, category)`
- `Built from`：[`analysis.analysis_user_first_order`](../sql/models/30_user/create_user_first_order.sql)、[`analysis.analysis_items_atomic`](../sql/models/10_atomic/create_items_atomic.sql)
- `Definition source`：[`../sql/models/30_user/create_user_first_order.sql`](../sql/models/30_user/create_user_first_order.sql)
- `Used by`：[`../notebooks/03_seller_hook_analysis.ipynb`](../notebooks/03_seller_hook_analysis.ipynb)、[`../sql/dq/check_user_first_order.sql`](../sql/dq/check_user_first_order.sql)

关键定义：

- 只取用户首个 delivered 订单中的商品品类
- `category` 缺失时记为 `unknown`
- 同一用户的首单篮子可能映射到多个品类，因此 cohort 会重叠

常见口径：

- `acquisition_users`：首单包含某品类的用户数
- `repurchased_users_90d`：在 eligible 用户中，`90d` 内发生复购且首单包含某品类的用户数

### `analysis.analysis_user_metrics`

- `Grain`：1 row per `user_id`
- `Primary key`：`user_id`
- `Built from`：[`analysis.analysis_orders_obt`](../sql/models/20_obt/create_obt.sql)
- `Definition source`：[`../sql/analyses/analysis_rfm.sql`](../sql/analyses/analysis_rfm.sql)
- `Used by`：[`../notebooks/02_repurchase_diagnosis.ipynb`](../notebooks/02_repurchase_diagnosis.ipynb)、[`analysis.analysis_user_rfm`](../sql/analyses/analysis_rfm.sql)

关键字段：

- `first_order_date` / `last_order_date`
- `frequency`：订单数
- `monetary`：总 `GMV`
- `avg_delay_days`：用户历史订单平均延迟
- `severe_late_rate`：`Late_Severe` 占比
- `primary_state`：用户主州；取最近订单对应的州，避免直接 JOIN 造成 fan-out
- `monetary_90d` / `monetary_365d` / `monetary_long`：不同窗口下的价值口径
- `eligible_repurchase_90d`：是否具备 `90d` 观察资格
- `repurchase_within_90d`：仅对 eligible 用户定义；不具备资格时为 `NULL`

使用注意：

- 所有 `90d` 复购率都应明确基于 `eligible_repurchase_90d=1`
- `primary_state` 是分析约定，不是用户“唯一真实州信息”

### `analysis.analysis_user_rfm`

- `Grain`：1 row per `user_id`
- `Primary key`：`user_id`
- `Built from`：[`analysis.analysis_user_metrics`](../sql/analyses/analysis_rfm.sql)
- `Definition source`：[`../sql/analyses/analysis_rfm.sql`](../sql/analyses/analysis_rfm.sql)
- `Used by`：[`../notebooks/02_repurchase_diagnosis.ipynb`](../notebooks/02_repurchase_diagnosis.ipynb)

关键字段：

- `recency_days`：以数据集最大下单日 `+ 1` 作为分析时点，避免出现 `0` 天歧义
- `r_score` / `f_score` / `m_score`：RFM 打分
- `ltv90_score` / `ltv365_score` / `ltvlong_score`：价值分位打分
- 继承自 `analysis.analysis_user_metrics` 的 `eligible_repurchase_90d`、`repurchase_within_90d` 等字段

使用注意：

- `recency_days` 通过 `DATE - DATE` 计算，避免 `INTERVAL -> INT` 的不稳定强转

## DQ Gates

### `check_obt.sql`

脚本：[`../sql/dq/check_obt.sql`](../sql/dq/check_obt.sql)

主要检查：

- `OBT` 行数是否与 raw delivered orders 对齐
- `gmv` 是否与 raw payments 汇总一致
- `order_id` 是否唯一
- `user_id`、`delay_days` 是否存在大量缺失
- `has_review` 与 `review_score` 的逻辑是否一致
- `review_score` 是否落在 `1..5`
- `delay_days` 与 `delivery_status` 是否自洽

### `check_user_first_order.sql`

脚本：[`../sql/dq/check_user_first_order.sql`](../sql/dq/check_user_first_order.sql)

主要检查：

- 首单表是否做到 1 user 1 row
- 首单品类桥表是否做到 `(user_id, category)` 唯一
- 首单是否确实对应最早 `purchase_ts`
- tie-break 是否稳定落在预期 `order_id`
- 首单桥表是否存在 orphan users

补充说明：`analysis.analysis_user_metrics` / `analysis.analysis_user_rfm` 当前没有单独的 DQ 脚本；若未来扩展仓库，建议在 `90d` 复购和 LTV 口径上补一层更显式的验证脚本。

## Related Assets

| 主题 | 相关资产 |
|---|---|
| 仓库入口 | [`../README.md`](../README.md) |
| 执行路径 | [`runbook.md`](runbook.md) |
| 履约断崖 | [`../notebooks/01_obt_feature_analysis.ipynb`](../notebooks/01_obt_feature_analysis.ipynb), [`../outputs/figures/fig_01_odds_ratio.png`](../outputs/figures/fig_01_odds_ratio.png) |
| 低复购现实 | [`../notebooks/02_repurchase_diagnosis.ipynb`](../notebooks/02_repurchase_diagnosis.ipynb), [`../outputs/figures/fig_02_ltv90_vs_ltvlong.png`](../outputs/figures/fig_02_ltv90_vs_ltvlong.png) |
| 钩子品类与卖家治理 | [`../notebooks/03_seller_hook_analysis.ipynb`](../notebooks/03_seller_hook_analysis.ipynb), [`../outputs/figures/fig_03_hook_category_matrix.png`](../outputs/figures/fig_03_hook_category_matrix.png), [`../outputs/figures/fig_03_seller_governance_matrix.png`](../outputs/figures/fig_03_seller_governance_matrix.png) |
| schema / path 约定 | [`../configs/config.yml`](../configs/config.yml) |
