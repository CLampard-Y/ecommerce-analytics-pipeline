/*
 * @title: DQ Check (User First Order)
 * @description:
 *   Data-quality checks for:
 *     - analysis.analysis_user_first_order
 *     - analysis.analysis_user_first_order_categories
 */

SELECT
    -- ---------------------------------
    -- 1) Coverage / cardinality
    -- ---------------------------------
    (SELECT COUNT(DISTINCT user_id) FROM analysis.analysis_orders_obt) AS obt_users,
    (SELECT COUNT(*) FROM analysis.analysis_user_first_order) AS first_order_rows,
    (SELECT COUNT(DISTINCT user_id) FROM analysis.analysis_user_first_order) AS first_order_users,

    -- ---------------------------------
    -- 2) Uniqueness
    -- ---------------------------------
    (
        SELECT COUNT(user_id) - COUNT(DISTINCT user_id)
        FROM analysis.analysis_user_first_order
    ) AS first_order_duplicate_users,
    (
        SELECT COUNT(*) - COUNT(DISTINCT (user_id, category))
        FROM analysis.analysis_user_first_order_categories
    ) AS first_order_categories_duplicate_pairs,

    -- ---------------------------------
    -- 3) Nulls / required fields
    -- ---------------------------------
    (
        SELECT COUNT(*)
        FROM analysis.analysis_user_first_order
        WHERE user_id IS NULL OR first_order_id IS NULL OR first_purchase_ts IS NULL
    ) AS first_order_null_required,
    (
        SELECT COUNT(*)
        FROM analysis.analysis_user_first_order_categories
        WHERE user_id IS NULL OR category IS NULL
    ) AS first_order_categories_null_required,

    -- ---------------------------------
    -- 4) Referential integrity
    -- ---------------------------------
    (
        SELECT COUNT(*)
        FROM analysis.analysis_user_first_order u
        LEFT JOIN analysis.analysis_orders_obt o
            ON u.first_order_id = o.order_id
        WHERE o.order_id IS NULL
    ) AS first_order_missing_in_obt,
    (
        SELECT COUNT(*)
        FROM analysis.analysis_user_first_order_categories c
        LEFT JOIN analysis.analysis_user_first_order u
            ON c.user_id = u.user_id
        WHERE u.user_id IS NULL
    ) AS first_order_categories_orphan_users,

    -- ---------------------------------
    -- 5) Definition checks (first delivered order)
    -- ---------------------------------
    (
        SELECT COUNT(*)
        FROM analysis.analysis_user_first_order u
        JOIN (
            SELECT user_id, MIN(purchase_ts) AS min_purchase_ts
            FROM analysis.analysis_orders_obt
            GROUP BY user_id
        ) m
            ON u.user_id = m.user_id
        WHERE u.first_purchase_ts <> m.min_purchase_ts
    ) AS first_order_not_min_purchase_ts,
    (
        SELECT COUNT(*)
        FROM analysis.analysis_user_first_order u
        JOIN analysis.analysis_orders_obt o
            ON u.first_order_id = o.order_id
        WHERE u.user_id <> o.user_id OR u.first_purchase_ts <> o.purchase_ts
    ) AS first_order_fk_mismatch,
    (
        -- If multiple orders share the same first_purchase_ts, tie-breaker is MIN(order_id).
        SELECT COUNT(*)
        FROM analysis.analysis_user_first_order u
        JOIN (
            SELECT
                user_id,
                MIN(order_id) AS expected_first_order_id
            FROM analysis.analysis_orders_obt
            WHERE (user_id, purchase_ts) IN (
                SELECT user_id, MIN(purchase_ts)
                FROM analysis.analysis_orders_obt
                GROUP BY user_id
            )
            GROUP BY user_id
        ) e
            ON u.user_id = e.user_id
        WHERE u.first_order_id <> e.expected_first_order_id
    ) AS first_order_tie_break_mismatch,

    -- ---------------------------------
    -- 6) Bridge coverage (should be ~0)
    -- ---------------------------------
    (
        SELECT COUNT(*)
        FROM analysis.analysis_user_first_order u
        LEFT JOIN analysis.analysis_user_first_order_categories c
            ON u.user_id = c.user_id
        WHERE c.user_id IS NULL
    ) AS users_missing_first_order_categories;
