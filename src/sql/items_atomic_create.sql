DROP TABLE IF EXISTS analysis.analysis_items_atomic;

CREATE TABLE analysis.analysis_items_atomic AS 
WITH 
base_joined AS (
    SELECT
        oi.order_id,
        -- 该product_id对应的商品在订单中是第几个商品(序号)
        oi.order_item_id,
        oi.product_id,
        -- 对应卖家
        oi.seller_id,
        oi.price,
        -- 对应商品名称
        t.product_category_name_english as category,
        
        -- 关联订单级的体验指标(评分、延迟)
        o.review_score,
        o.delay_days,
        
        -- 延迟交付标记
        CASE WHEN o.delay_days > 0 THEN 1 ELSE 0 END AS is_late
    FROM Olist.olist_order_items_dataset oi
    -- 关联OBT
    INNER JOIN analysis.analysis_orders_obt o
        ON oi.order_id = o.order_id
    -- 关联商品表
    LEFT JOIN Olist.olist_products_dataset p
        ON oi.product_id = p.product_id
    -- 关联翻译表
    LEFT JOIN Olist.product_category_name_translation t
        ON p.product_category_name = t.product_category_name
)
SELECT * FROM base_joined;

-- 对seller_id创建索引,为后续供给侧分析做准备
CREATE INDEX idx_atomic_seller ON analysis.analysis_items_atomic(seller_id);