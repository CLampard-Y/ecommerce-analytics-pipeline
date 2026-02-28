/*
 * @title: User First Order Models
 * @description:
 *   Canonical user-grain tables derived from delivered orders.
 *
 *   1) analysis.analysis_user_first_order
 *      - Grain: 1 row per user_id
 *      - Definition: user's first delivered order in analysis.analysis_orders_obt
 *        using deterministic tie-breaker ORDER BY (purchase_ts, order_id).
 *
 *   2) analysis.analysis_user_first_order_categories
 *      - Grain: 1 row per (user_id, category)
 *      - Definition: distinct item categories present in the user's first delivered order.
 *      - Source: analysis.analysis_items_atomic joined by order_id.
 */

DROP TABLE IF EXISTS analysis.analysis_user_first_order_categories;
DROP TABLE IF EXISTS analysis.analysis_user_first_order;

-- -------------------------------------------------
-- 1) Canonical first delivered order per user
-- -------------------------------------------------
CREATE TABLE analysis.analysis_user_first_order AS
WITH ranked AS (
    SELECT
        user_id,
        order_id,
        purchase_ts,
        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY purchase_ts, order_id
        ) AS rn
    FROM analysis.analysis_orders_obt
)
SELECT
    user_id,
    order_id AS first_order_id,
    purchase_ts AS first_purchase_ts
FROM ranked
WHERE rn = 1;

CREATE INDEX IF NOT EXISTS idx_aufou_user_id
    ON analysis.analysis_user_first_order(user_id);
CREATE INDEX IF NOT EXISTS idx_aufou_first_order_id
    ON analysis.analysis_user_first_order(first_order_id);

-- -------------------------------------------------
-- 2) Bridge: first-order categories (distinct users)
-- -------------------------------------------------
CREATE TABLE analysis.analysis_user_first_order_categories AS
SELECT DISTINCT
    u.user_id,
    COALESCE(i.category, 'unknown') AS category
FROM analysis.analysis_user_first_order u
INNER JOIN analysis.analysis_items_atomic i
    ON u.first_order_id = i.order_id;

CREATE INDEX IF NOT EXISTS idx_aufoc_user_id
    ON analysis.analysis_user_first_order_categories(user_id);
CREATE INDEX IF NOT EXISTS idx_aufoc_category
    ON analysis.analysis_user_first_order_categories(category);
