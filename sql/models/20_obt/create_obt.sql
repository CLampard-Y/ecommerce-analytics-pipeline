/*
 * @title: Obt Creation(宽表创建)
 * @description: 将已有事实表中的信息进行聚合、连接,创建以订单为粒度的详细信息宽表
 */

-- 表初始化,保证幂等性
DROP TABLE IF EXISTS analysis.analysis_orders_obt;
DROP SCHEMA IF EXISTS analysis;

CREATE SCHEMA analysis;
CREATE TABLE analysis.analysis_orders_obt AS
WITH

-- -------------------------------------------------
-- 1. 将订单表与用户表连接,记录顾客数据
-- -------------------------------------------------
-- 目的: 将订单中的非主键的顾客id(即同一个顾客在不同订单中的id是不一样的)替换为一一对应的顾客id
--       记录顾客所在州,为后续物流分析作数据准备
base_orders AS (
    SELECT
        o.order_id,
        c.customer_unique_id AS user_id,
        o.order_status,
        o.order_purchase_timestamp,
        o.order_approved_at,
        o.order_delivered_carrier_date,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        c.customer_state
    FROM Olist.olist_orders_dataset o
    LEFT JOIN Olist.olist_customers_dataset c
        ON o.customer_id = c.customer_id
    WHERE 1 = 1
    	AND o.order_status = 'delivered'
        AND o.order_delivered_customer_date IS NOT NULL
),

-- ---------------------------------------------
-- 2. 把items表聚合到orders粒度(避免连接导致扇出)
-- ---------------------------------------------
-- 目的: 记录每个订单的总信息
order_items_agg AS (
    SELECT
        oi.order_id,

        -- 订单商品数
        COUNT(*) AS items_cnt,

        -- 涉及卖家数量
        COUNT(DISTINCT oi.seller_id) AS sellers_cnt,

        -- 订单总GMV
        SUM(oi.price::numeric) AS items_value,

        -- 订单总运费
        SUM(oi.freight_value::numeric) AS freight_value
    FROM Olist.olist_order_items_dataset oi
    GROUP BY oi.order_id
),

-- ---------------------------------------------
-- 3.把payments表聚合到订单粒度(避免连接导致扇出)
-- ---------------------------------------------
-- 目的: 计算每个order_id支付的GMV,并列出支付方式
order_payments AS (
    SELECT
        order_id,
        SUM(payment_value::numeric) AS gmv,

        -- 运用字符串聚合函数,把一个订单id里的所有支付方式列出,用'+'作为间隔
        -- 固定顺序(,'+' ORDER BY payment_type),去掉ORDER则不保证顺序
        STRING_AGG(DISTINCT payment_type, '+' ORDER BY payment_type) AS payment_method,

        -- 给用户打上布尔标记(是否有使用优惠券)
        -- 使用MAX原因:只要支付方式中有一次为`voucher`就打上标记
        MAX(CASE WHEN payment_type = 'voucher' THEN 1 ELSE 0 END) AS is_voucher_user	
    FROM Olist.olist_order_payments_dataset
    GROUP BY order_id
),

-- ----------------------------------
-- 4. 把reviews表聚合到订单粒度
-- ----------------------------------
order_reviews AS (
    SELECT
        order_id,

        -- 一个订单可能会有多个调查问卷,因此可能会有多个不同评价评分
        -- 方法:选取所有评分的最低分作为该订单评分
        -- 原因:评分存在严重木板效应,用户会倾向于查看评分低的商品
        MIN(review_score::int) AS review_score
    FROM Olist.olist_order_reviews_dataset
    GROUP BY order_id
)

-- ---------------------------------
-- 5. 生成综合所有信息的订单粒度宽表
-- ---------------------------------
SELECT
    b.user_id,
    b.order_id,
    b.customer_state,

    -- 将时间类型信息转换时间类型(原本导入时为TEXT类型)
    -- 这里没有导入平台规定的发货截止时间(SLA截止时间)
    -- 原因:同一个订单的购买,通过,卖家发货,送达,预计送达时间都是一致的
    --     同一个订单不同商品,SLA截止时间不一样(即SLA是以商品为粒度).需要后续专门创建表记录
    b.order_purchase_timestamp::timestamp AS purchase_ts,
    b.order_approved_at::timestamp AS approved_ts,
    b.order_delivered_carrier_date::timestamp AS carrier_ts,
    b.order_delivered_customer_date::timestamp AS delivered_ts,
    b.order_estimated_delivery_date::timestamp AS estimated_ts,

    -- 履约链路拆解:订单通过所需时间,卖家发货所需时间,货物运输所需时间,货物交付总时间
    EXTRACT(EPOCH FROM (b.order_approved_at::timestamp - b.order_purchase_timestamp::timestamp)) / 3600 AS approve_hours,
    EXTRACT(DAY FROM (b.order_delivered_carrier_date::timestamp - b.order_approved_at::timestamp)) AS handling_days,
    EXTRACT(DAY FROM (b.order_delivered_customer_date::timestamp - b.order_delivered_carrier_date::timestamp)) AS shipping_days,
    EXTRACT(DAY FROM (b.order_delivered_customer_date::timestamp - b.order_purchase_timestamp::timestamp)) AS total_fulfill_days,

    -- 送达和预计送达时间差(延迟送达天数)
    -- 晚送达:差值为正
    -- 提前或按时送达:差值为负或0
    EXTRACT(DAY FROM (b.order_delivered_customer_date::timestamp - b.order_estimated_delivery_date::timestamp)) AS delay_days,

    -- 根据延迟送达天数不同情况进行标记
    -- OnTime:提前或按时送达
    -- Late_Small:不能按时送达,但延迟天数在3天内
    -- Late_Severe:延迟天数超过3天
    CASE
        WHEN b.order_delivered_customer_date::timestamp <= b.order_estimated_delivery_date::timestamp THEN 'OnTime'
        WHEN (b.order_delivered_customer_date::timestamp - b.order_estimated_delivery_date::timestamp) <= INTERVAL '3 days' THEN 'Late_Small'
        ELSE 'Late_Severe'
    END AS delivery_status,

    -- 对数值类字段进行防NULL处理
    COALESCE(i.items_cnt, 0) AS items_cnt,
    COALESCE(i.sellers_cnt, 0) AS sellers_cnt,
    COALESCE(i.items_value, 0) AS items_value,
    COALESCE(i.freight_value, 0) AS freight_value,
	COALESCE(p.is_voucher_user,0) AS is_voucher_user,
    COALESCE(p.gmv, 0) AS gmv,

    -- 订单运费占比 = 订单运费 / 订单GMV
    CASE WHEN p.gmv > 0 THEN 
    	i.freight_value / p.gmv
    	ELSE 0
    END AS freight_ratio,

    -- 件单价 = 订单GMV / 订单商品数
    p.gmv / NULLIF(i.items_cnt,0) AS avg_item_price,

    -- 防NULL处理
    COALESCE(p.payment_method, 'unknown') AS payment_method,
    COALESCE(r.review_score, 0) AS review_score,

    -- 先行计算,方便后续直接做Month-Over-Month(MoM)分析(如果需要)
    TO_CHAR(b.order_purchase_timestamp::timestamp,'YYYY-MM') AS purchase_month,
    -- 先行计算,方便分析"周末下单是否发货更慢"(如果需要)
    EXTRACT(ISODOW FROM b.order_purchase_timestamp::timestamp) AS purchase_dow

FROM base_orders b
LEFT JOIN order_items_agg i ON b.order_id = i.order_id
LEFT JOIN order_payments p ON b.order_id = p.order_id
LEFT JOIN order_reviews r ON b.order_id = r.order_id;


-- 为创建的详细表创建索引:user_id,purchase_ts,delivery_status,purchase_month
CREATE INDEX IF NOT EXISTS idx_aoobt_user_id ON analysis.analysis_orders_obt(user_id);
CREATE INDEX IF NOT EXISTS idx_aoobt_purchase_ts ON analysis.analysis_orders_obt(purchase_ts);
CREATE INDEX IF NOT EXISTS idx_aoobt_delivery_status ON analysis.analysis_orders_obt(delivery_status);
CREATE INDEX IF NOT EXISTS idx_aoobt_month ON analysis.analysis_orders_obt(purchase_month)
