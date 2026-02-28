/*
 * @title: DQ Check(数据质量检查)
 * @description: 验证宽表(obt)的完整性,准确性与一致性
 *               提前计算后续分析需要使用的指标
 */
SELECT
	-- -----------------------------
	-- 1. 行数一致性检查
	-- -----------------------------
	-- 逻辑: 宽表行数必须等于原始orders表中'delivered'且有送达时间的订单数
	(SELECT COUNT(*) FROM analysis.analysis_orders_obt) AS obt_rows,

	-- 计算符合宽表创建条件的订单数
	(
		SELECT 
			COUNT(*) 
		FROM Olist.olist_orders_dataset

		WHERE 1 = 1
			AND order_status = 'delivered' 
			AND order_delivered_customer_date IS NOT NULL
	) AS raw_rows,
	
	-- -----------------------------
	-- 2. 金额一致性检查
	-- -----------------------------
	-- 逻辑：宽表GMV总和应与原始payments表总和接近（允许微小误差，但不能差倍数）
    (SELECT SUM(gmv) FROM analysis.analysis_orders_obt) AS obt_gmv,

	-- 计算符合宽表创建条件的order_id('delivered'且有送达时间)
    (
    	SELECT
    		SUM(payment_value::numeric)
    	FROM Olist.olist_order_payments_dataset
    	WHERE order_id IN (SELECT order_id FROM analysis.analysis_orders_obt)
    ) AS raw_gmv,
    
    -- -----------------------------
    -- 3. 扇出/重复检查
    -- -----------------------------
	-- 逻辑: 如果存在不唯一的order_id，说明发生扇出
    (
    	SELECT 
			-- 重复order_id数 = 总order_id数 - 去重后的oder_id数
    		COUNT(order_id) - COUNT(DISTINCT order_id) 
    	FROM analysis.analysis_orders_obt
    ) AS duplicate_orders,

    -- ---------------------------------
    -- 4. 关键字段完整性
    -- ---------------------------------
    -- 逻辑: 核心分析字段不应有大量 NULL
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
	) AS null_delays,

	-- ---------------------------------
	-- 5. Review coverage and domain
	-- ---------------------------------
	-- Notes:
	-- - review_score can be NULL when no review exists; use has_review to interpret coverage.
	-- - review_score domain should be 1..5 when not NULL.
	(
		SELECT COUNT(*)
		FROM analysis.analysis_orders_obt
		WHERE has_review NOT IN (0, 1) OR has_review IS NULL
	) AS invalid_has_review,
	(
		SELECT COUNT(*)
		FROM analysis.analysis_orders_obt
		WHERE review_score IS NOT NULL AND (review_score < 1 OR review_score > 5)
	) AS invalid_review_score_domain,
	(
		SELECT COUNT(*)
		FROM analysis.analysis_orders_obt
		WHERE (has_review = 1 AND review_score IS NULL)
			OR (has_review = 0 AND review_score IS NOT NULL)
	) AS has_review_mismatch,

	-- ---------------------------------
	-- 6. Consistency between delay_days and delivery_status
	-- ---------------------------------
	-- delay_days is fractional days (epoch/86400), so small delays (<1 day) should still be > 0.
	(
		SELECT COUNT(*)
		FROM analysis.analysis_orders_obt
		WHERE delivery_status = 'OnTime' AND delay_days > 0
	) AS ontime_but_positive_delay,
	(
		SELECT COUNT(*)
		FROM analysis.analysis_orders_obt
		WHERE delivery_status IN ('Late_Small', 'Late_Severe') AND delay_days <= 0
	) AS late_but_non_positive_delay;
