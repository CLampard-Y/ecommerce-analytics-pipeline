/*
 * @title:RFM Creation(用户RFM表的创建)
 * @description:从obt表出发,先按用户维度进行汇总,随后创建RFM表
 */

-- ===================================
-- 一. 用户维度汇总	
-- ===================================
DROP TABLE IF EXISTS analysis.analysis_user_metrics;

CREATE TABLE analysis.analysis_user_metrics AS
WITH 

-- ----------------------------------
-- 1. 记录用户州信息
-- ----------------------------------
-- 目的: 记录用户的州信息,为后续对延迟交付天数与复购率关系的深层T-Test做数据准备
-- 逻辑: 选取用户最近订单对应的州定为主州
user_state AS (
	-- PostgreSQL特有语法
	-- 逻辑:对每个user_id分组,只保留一行(不是随机保留,而是根据ORDER BY决定)
	SELECT DISTINCT ON (user_id)
		user_id,
		customer_state AS primary_state
	FROM analysis.analysis_orders_obt
	WHERE customer_state IS NOT NULL
	-- 先按user_id排序,让同一个user_id的所有订单都排列在一起
	-- 在同一个user_id内按purchase_ts DESC排序,让最近的订单排在最前面
	ORDER BY user_id,purchase_ts DESC
),

-- --------------------------------
-- 2. 初步创建用户总消费信息表
-- --------------------------------
user_orders AS (
    SELECT
        user_id,
        -- 用户首次下单日期(用于后续定义"90天/365天/长期周期")
        MIN(purchase_ts::date) AS first_order_date,
        -- 用户最近一次下单日期(用于Recency计算)
        MAX(purchase_ts::date) AS last_order_date,
        -- 用户订单数(F)
        COUNT(*) AS frequency,
        -- 用户总GMV(M)
        SUM(gmv) AS monetary,
        -- 每个用户所有订单的平均延迟交付时间(负数代表提前送达)
        AVG(delay_days) AS avg_delay_days,
        -- 严重延迟交付占比
        AVG(CASE WHEN delivery_status='Late_Severe' THEN 1 ELSE 0 END) AS severe_late_rate
    FROM analysis.analysis_orders_obt
    GROUP BY user_id
),

-- ------------------------------------
-- 3. 将用户所在州与总消费信息表连接
-- ------------------------------------
-- 注意: 用户所在州和user_id不是一对一的(一个用户可能会有不同州的订单),如果直接连接会发生扇出
user_base AS (
	SELECT 
		o.*,
		s.primary_state AS primary_state
	FROM user_orders o
	LEFT JOIN user_state s 
		ON o.user_id = s.user_id
),

-- -----------------------------------
-- 4. 初步计算用户LTV
-- -----------------------------------
ltv_calc AS (
    SELECT
        a.user_id,
        -- 90天LTV:反映短期留存价值
        SUM(CASE WHEN a.purchase_ts::date <= (u.first_order_date + INTERVAL '90 days')
        			THEN a.gmv ELSE 0 END) AS monetary_90d,
        -- 365天LTV:反映中长期留存价值
        SUM(CASE WHEN a.purchase_ts::date <= (u.first_order_date + INTERVAL '365 days')
        			THEN a.gmv ELSE 0 END) AS monetary_365d
	FROM analysis.analysis_orders_obt a
	LEFT JOIN user_base u
		ON a.user_id = u.user_id
	-- 防止存在purchase_ts比first_order_date更早的情况
	-- 一般不会存在,但工程上需要添加防御性代码
	WHERE a.purchase_ts::date >= u.first_order_date
	GROUP BY a.user_id
 )

-- ----------------------------------
-- 5. 创建完整用户总消费信息表
-- ----------------------------------
SELECT
    u.*,

    -- 防NULL处理
    COALESCE(l.monetary_90d, 0) AS monetary_90d,
    COALESCE(l.monetary_365d, 0) AS monetary_365d,

    -- 将用户总GMV作为长期LTV
    COALESCE(u.monetary, 0) AS monetary_long
FROM user_base u
LEFT JOIN ltv_calc l
	ON u.user_id = l.user_id;


-- ==================================
-- 二. 建表验收
-- ==================================
-- 逻辑: 创建的用户总信息表行数必须等于distinct user_id
SELECT
	(SELECT COUNT(*) FROM analysis.analysis_user_metrics) AS metrics_rows,
	(SELECT COUNT(DISTINCT user_id) FROM analysis.analysis_orders_obt) AS obt_users;


-- ==================================
-- 三. 创建RFM表
-- ==================================
DROP TABLE IF EXISTS analysis.analysis_user_rfm;

CREATE TABLE analysis.analysis_user_rfm AS

WITH 
base AS (
    SELECT
        *,
        -- 取分析时间点为数据集最大时间 + 1天
        -- 窗口函数 + interval "1 day"
        -- 错误方法1:EXTRACT(DAY FROM (MAX(last_order_date) OVER () + INTERVAL '1 day' - last_order_date))
        -- 错误方法2:(MAX(last_order_date) OVER () + INTERVAL '1 day' - last_order_date)::int AS recency_days
        (MAX(last_order_date) OVER ()::date - last_order_date::date + 1) AS recency_days
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
    NTILE(5) OVER (ORDER BY monetary_365d ASC) AS ltv365_score,
    NTILE(5) OVER (ORDER BY monetary_long ASC) AS ltvlong_score
FROM base;
