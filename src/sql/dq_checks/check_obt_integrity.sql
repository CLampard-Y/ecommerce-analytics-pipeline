/*
 * @title: DQ Check(数据质量检查)
 * @description: 验证宽表(obt)的完整性,准确性与一致性
 *               提前计算后续分析需要使用的指标
 */
SELECT
	-- ==========================================
	-- 1. 行数一致性检查
	-- 逻辑:宽表行数必须等于原始orders表中'delivered'且有送达时间的订单数
	-- ======================================================
	(SELECT COUNT(*) FROM analysis.analysis_orders_obt) AS obt_rows,
	(
		SELECT 
			COUNT(*) 
		FROM Olist.olist_orders_dataset
		WHERE 1 = 1
			AND order_status = 'delivered' 
			AND order_delivered_customer_date IS NOT NULL
	) AS raw_rows,
	
	-- ============================
	-- 2. 金额一致性检查
    -- 逻辑：宽表GMV总和应与原始payments表总和接近（允许微小误差，但不能差倍数）
	-- ============================
    (SELECT SUM(gmv) FROM analysis.analysis_orders_obt) AS obt_gmv,
    (
    	SELECT 
    		SUM(payment_value::numeric)
    	FROM Olist.olist_order_payments_dataset
    	-- 只计算包含在宽表中的order_id('delivered'且有送达时间)
    	WHERE order_id IN (SELECT order_id FROM analysis.analysis_orders_obt)
    ) AS raw_gmv,
    
    -- ==============================================
    -- 3. 扇出/重复检查
    -- 逻辑：如果 order_id 不是唯一的，说明发生了扇出
    -- ===============================================
    (
    	SELECT 
    		COUNT(order_id) - COUNT(DISTINCT order_id) 
    	FROM analysis.analysis_orders_obt
    ) AS duplicate_orders,

    -- ==============================================
    -- 4. 关键字段完整性
    -- 逻辑：核心分析字段不应有大量 NULL
    -- ==============================================
    (
    	SELECT 
    		COUNT(*) 
    	FROM analysis.analysis_orders_obt 
    	WHERE user_id IS NULL
    ) AS null_users,
    (
	    SELECT 
	    	COUNT(*) 
	    FROM analysis.analysis_orders_obt 
	    WHERE delay_days IS NULL
    ) AS null_delays;