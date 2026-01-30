

-- ===================================
-- 1. 用户维度汇总	
-- ===================================
DROP TABLE IF EXISTS analysis.analysis_user_metrics;

CREATE TABLE analysis.analysis_user_metrics AS
WITH user_orders AS (
    SELECT
        user_id,
        -- 用户首次下单日期(用于定义"90天窗口")
        MIN(purchase_ts::date) AS first_order_date,
        -- 用户最近一次下单日期(用于Recency)
        MAX(purchase_ts::date) AS last_order_date,
        -- 用户订单数(F)
        COUNT(*) AS frequency,
        -- 用户总GMV(M)
        SUM(gmv) AS monetary,
        AVG(delay_days) AS avg_delay_days,
        -- 严重延迟占比
        AVG(CASE WHEN delivery_status='Late_Severe' THEN 1 ELSE 0 END) AS severe_late_rate
    FROM analysis.analysis_orders_obt
    GROUP BY user_id
),

-- 计算LTV
ltv_calc AS (
    SELECT
        a.user_id,
        -- 90天LTV:反映短期留存价值
        SUM(CASE WHEN a.purchase_ts::date <= (u.first_order_date + INTERVAL '90 days')
        			THEN a.gmv ELSE 0 END) AS monetary_90d,
        -- 365天LTV:反映长期留存价值
        SUM(CASE WHEN a.purchase_ts::date <= (u.first_order_date + INTERVAL '365 days')
        			THEN a.gmv ELSE 0 END) AS monetary_365d
	FROM analysis.analysis_orders_obt a
	LEFT JOIN user_orders u
		ON a.user_id = u.user_id
	-- 防止存在purchase_ts比first_order_date更早的情况
	-- 一般不会存在,但工程上需要添加防御性代码
	WHERE a.purchase_ts::date >= u.first_order_date
	GROUP BY a.user_id
 )
        
SELECT
    u.*,
    -- 空值处理
    COALESCE(l.monetary_90d, 0) AS monetary_90d,
    COALESCE(l.monetary_365d, 0) AS monetary_365d
FROM user_orders u
LEFT JOIN ltv_calc l
	ON u.user_id = l.user_id;


-- ==================================
-- 2. 创建RFM表
-- ==================================
DROP TABLE IF EXISTS analysis.analysis_user_rfm;

CREATE TABLE analysis.analysis_user_rfm AS

WITH base AS (
    SELECT
        *,
        -- 取分析时间点为数据集最大时间 + 1天
        -- 窗口函数 + interval "1 day"
        --EXTRACT(DAY FROM (MAX(last_order_date) OVER () + INTERVAL '1 day' - last_order_date))
        --(MAX(last_order_date) OVER () + INTERVAL '1 day' - last_order_date)::int AS recency_days
        (MAX(last_order_date) OVER ()::date + 1 - last_order_date::date) AS recency_days
    FROM analysis.analysis_user_metrics
)

SELECT
    *,
    -- R分:按时间切割(30,30-90,90-180,...)
    CASE
    	WHEN recency_days <= 30 THEN 5
    	WHEN recency_days <= 90 THEN 4
    	WHEN recency_days <= 180 THEN 3
    	WHEN recency_days <= 365 THEN 2
    	ELSE 1
    END AS r_score,
    
    -- F分:按订单数切割
    CASE
    	WHEN frequency >= 5 THEN 5
    	WHEN frequency = 4 THEN 4
    	WHEN frequency = 3 THEN 3
    	WHEN frequency = 2 THEN 2
    	ELSE 1
    END AS f_score,
    
    -- M分:金额是连续变量,直接使用NTILE切割
    NTILE(5) OVER (ORDER BY monetary ASC) AS m_score,
    
    -- LTV分:连续变量
    NTILE(5) OVER (ORDER BY monetary_90d ASC) AS ltv90_score,
    NTILE(5) OVER (ORDER BY monetary_365d ASC) AS ltv365_score
FROM base;







