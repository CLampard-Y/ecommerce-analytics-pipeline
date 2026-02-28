# Data Dictionary (Interview-Friendly)

目标：把“在业务上讲的每一个指标”落到可追溯的表、粒度（grain）、主键（PK）和口径。

本项目的分析层主要依赖以下表：
- `analysis.analysis_orders_obt`：订单粒度 OBT（体验归因主干）
- `analysis.analysis_items_atomic`：商品粒度 atomic（钩子品类 / 供给侧治理输入）
- `analysis.analysis_user_metrics`：用户粒度指标汇总（RFM/LTV 基础）
- `analysis.analysis_user_rfm`：用户粒度 RFM/LTV + scoring（复购诊断输入）

raw 层表（默认 schema=`olist`）：
- `olist.olist_orders_dataset`
- `olist.olist_customers_dataset`
- `olist.olist_order_items_dataset`
- `olist.olist_order_payments_dataset`
- `olist.olist_order_reviews_dataset`
- `olist.olist_products_dataset`
- `olist.olist_sellers_dataset`
- `olist.product_category_name_translation`

---

## Conventions | 统一约定

- **Time**：raw 入库时 timestamp 字段为 TEXT；在 OBT 中统一转为 `timestamp`，并派生 `_ts` 字段。
- **Delay sign**：`delay_days > 0` 表示晚到；`<= 0` 表示准时或提前（在相关性分析中常会将负数 clip 到 0）。
- **Grain guard**：orders 粒度的表，任何来自 item/payment/review 的信息必须先聚合到 `order_id` 再 JOIN，避免 fan-out。

---

## `analysis.analysis_orders_obt` (Order-grain OBT)

**Grain**：1 row per `order_id`（仅保留 `order_status='delivered'` 且 `order_delivered_customer_date IS NOT NULL` 的订单）。

**Primary key**：`order_id`

**Built from**：
- `olist.olist_orders_dataset` (base)
- `olist.olist_customers_dataset` (map `customer_id` -> `customer_unique_id`)
- `olist.olist_order_items_dataset` (aggregated to order)
- `olist.olist_order_payments_dataset` (aggregated to order)
- `olist.olist_order_reviews_dataset` (aggregated to order)

**Join keys**：
- orders -> customers: `customer_id`
- orders -> items/payments/reviews: `order_id`

**Key columns (Business)**：
- `user_id`：`customer_unique_id`，用于用户层分析（RFM/LTV/复购）
- `customer_state`：用户州信息（分层防御/公平性校准）
- `purchase_ts` / `approved_ts` / `carrier_ts` / `delivered_ts` / `estimated_ts`：履约链路关键时间点

**Key metrics (Definitions)**：
- `gmv`：订单 GMV（payments 聚合）
  - 口径：`SUM(payment_value)` by `order_id`
  - 用途：作为订单金额主口径，并在 DQ 中与 raw payments 做一致性校验
- `items_cnt`：订单 item 行数（items 聚合）
- `sellers_cnt`：订单涉及卖家数（`COUNT(DISTINCT seller_id)`）
- `items_value` / `freight_value`：items 粒度价格与运费聚合
- `freight_ratio`：`freight_value / gmv`（`gmv<=0` 则为 0）
- `avg_item_price`：`gmv / items_cnt`（用 `NULLIF(items_cnt, 0)` 保护分母）
- `review_score`：订单评分（取最小值）
  - 业务解释：一个订单可能多次被评价；用 `MIN(review_score)` 体现“木桶效应”（低分更容易主导体验判断）
- `delay_days`：`delivered_ts - estimated_ts`（天）
  - 正数：晚到；负数/0：提前或准时
  - 注意：很多分析任务（相关性/归因）会用 `delay_days_clipped = max(delay_days, 0)` 过滤“提前送达的无效变异”
- `delivery_status`：履约分层
  - `OnTime`：`delivered_ts <= estimated_ts`
  - `Late_Small`：晚到且 `<= 3 days`
  - `Late_Severe`：晚到且 `> 3 days`

**Operational decomposition (Hours/Days)**：
- `approve_hours`：`approved_ts - purchase_ts`（小时）
- `handling_days`：`carrier_ts - approved_ts`（天，近似卖家处理/出库）
- `shipping_days`：`delivered_ts - carrier_ts`（天，近似运输时长）
- `total_fulfill_days`：`delivered_ts - purchase_ts`（天）

**Edge cases to defend in interviews**：
- `carrier_ts` 可能为空，导致 handling/shipping 指标为 NULL（OBT 仍保留订单；分析时需要显式处理）
- `delay_days` 为负：提前送达不等于“越早越好”，否则相关性/模型会被“无效变异”稀释
- `gmv` 与 `items_value` 不一定严格一致（折扣/分摊/退款/运费口径差异）；本项目以 payments 聚合的 `gmv` 为主口径

---

## `analysis.analysis_items_atomic` (Item-grain atomic)

**Grain**：1 row per `(order_id, order_item_id)`（订单中的每一件商品）。

**Primary key**：`(order_id, order_item_id)`

**Built from**：
- `olist.olist_order_items_dataset` (base)
- `analysis.analysis_orders_obt` (attach review/delay)
- `olist.olist_products_dataset` + `olist.product_category_name_translation` (attach category)

**Join keys**：
- items -> obt: `order_id`
- items -> products: `product_id`
- products -> translation: `product_category_name`

**Key columns (Business)**：
- `seller_id`：供给侧主体
- `category`：英文品类（用于钩子品类分析）
- `review_score` / `delay_days`：把体验标签带到商品/卖家粒度
- `is_late`：`delay_days > 0` 的二元标记（方便分组与聚合）

**Edge cases**：
- Mixed basket：一个订单可能包含多个卖家；所以“订单晚到”无法直接归责到卖家（需要 SLA 解耦，见 notebook 03）
- `category` 可能为空（翻译缺失）；分析时通常要做缺失处理或过滤

---

## `analysis.analysis_user_metrics` (User-grain metrics)

**Grain**：1 row per `user_id`

**Primary key**：`user_id`

**Built from**：`analysis.analysis_orders_obt`

**Key columns**：
- `first_order_date` / `last_order_date`
- `frequency`：订单数
- `monetary`：总 GMV
- `avg_delay_days`：用户历史订单的平均延迟（允许为负，代表提前送达）
- `severe_late_rate`：`delivery_status='Late_Severe'` 的比例
- `primary_state`：用户主州（取最近订单州，避免一个用户多地址导致 fan-out）
- `monetary_90d` / `monetary_365d`：LTV 窗口（从首单开始滚动）

**Edge cases**：
- 用户可能跨州下单：直接 JOIN 会导致用户行重复；本项目用 `DISTINCT ON (user_id) ORDER BY purchase_ts DESC` 固化主州

---

## `analysis.analysis_user_rfm` (RFM + LTV scoring)

**Grain**：1 row per `user_id`

**Primary key**：`user_id`

**Built from**：`analysis.analysis_user_metrics`

**Key columns**：
- `recency_days`：以数据集最大下单日 + 1 作为分析时点，避免出现 0 天歧义
- `r_score` / `f_score`：规则分箱
- `m_score`：`NTILE(5)`（按 monetary 分位数打分）
- `ltv90_score` / `ltv365_score` / `ltvlong_score`：LTV 分位数打分

**Edge cases**：
- R 的计算避免 `INTERVAL -> INT` 强转陷阱：用 `DATE - DATE` 得到稳定的整数天数

---

## Where definitions live | 口径来源

- OBT 建表：`sql/models/20_obt/create_obt.sql`
- atomic 建表：`sql/models/10_atomic/create_items_atomic.sql`
- RFM/LTV：`sql/analyses/analysis_rfm.sql`
- OBT 质量门禁：`sql/dq/check_obt.sql`
