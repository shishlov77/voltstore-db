-- ============================================================
-- VoltStore — аналитические запросы
-- ============================================================

SET search_path TO store;


-- 1. Ранжирование товаров по выручке внутри категории
SELECT
    c.name  AS category,
    p.name  AS product,
    sum(oi.quantity * oi.unit_price) AS revenue,
    rank() OVER (
        PARTITION BY c.category_id
        ORDER BY sum(oi.quantity * oi.unit_price) DESC
    ) AS rank_in_category
FROM order_items oi
JOIN products p   USING (product_id)
JOIN categories c USING (category_id)
JOIN orders o     USING (order_id)
WHERE o.status NOT IN ('cancelled', 'refunded')
GROUP BY c.category_id, c.name, p.product_id, p.name
ORDER BY c.name, rank_in_category;


-- 2. Скользящее среднее выручки (7 дней)
WITH daily AS (
    SELECT
        created_at::date   AS day,
        sum(total_amount)  AS revenue
    FROM orders
    WHERE status NOT IN ('cancelled', 'refunded')
    GROUP BY 1
)
SELECT
    day,
    revenue,
    round(avg(revenue) OVER (
        ORDER BY day
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS moving_avg_7d
FROM daily
ORDER BY day;


-- 3. Когортный анализ (retention)
WITH cohort AS (
    SELECT
        c.customer_id,
        date_trunc('month', c.registered_at)::date AS cohort_month,
        date_trunc('month', o.created_at)::date    AS order_month
    FROM customers c
    JOIN orders o USING (customer_id)
),
sizes AS (
    SELECT cohort_month, count(DISTINCT customer_id) AS cnt
    FROM cohort GROUP BY 1
)
SELECT
    co.cohort_month,
    s.cnt                                AS cohort_size,
    (extract(YEAR  FROM age(co.order_month, co.cohort_month)) * 12
   + extract(MONTH FROM age(co.order_month, co.cohort_month)))::int AS months_since,
    count(DISTINCT co.customer_id)       AS active,
    round(
        count(DISTINCT co.customer_id)::numeric / s.cnt * 100, 1
    ) AS retention_pct
FROM cohort co
JOIN sizes s USING (cohort_month)
GROUP BY co.cohort_month, s.cnt,
         extract(YEAR  FROM age(co.order_month, co.cohort_month)),
         extract(MONTH FROM age(co.order_month, co.cohort_month))
ORDER BY 1, 3;


-- 4. Рекурсия: дерево подкатегорий «Электроника»
WITH RECURSIVE sub AS (
    SELECT category_id, name, parent_id, 1 AS lvl
    FROM categories
    WHERE slug = 'electronics'

    UNION ALL

    SELECT c.category_id, c.name, c.parent_id, s.lvl + 1
    FROM categories c
    JOIN sub s ON c.parent_id = s.category_id
)
SELECT
    lpad('', (lvl - 1) * 4) || name AS tree,
    (SELECT count(*) FROM products p
     WHERE p.category_id = sub.category_id) AS products_count
FROM sub
ORDER BY category_id;


-- 5. Нарастающий итог покупок клиента
WITH numbered AS (
    SELECT
        customer_id,
        order_id,
        total_amount,
        created_at,
        row_number() OVER (
            PARTITION BY customer_id ORDER BY created_at
        ) AS order_num
    FROM orders
    WHERE status NOT IN ('cancelled', 'refunded')
)
SELECT
    c.first_name || ' ' || c.last_name AS customer,
    n.order_num,
    n.total_amount,
    sum(n.total_amount) OVER (
        PARTITION BY n.customer_id ORDER BY n.created_at
    ) AS running_total,
    n.total_amount - lag(n.total_amount) OVER (
        PARTITION BY n.customer_id ORDER BY n.created_at
    ) AS diff_vs_prev
FROM numbered n
JOIN customers c USING (customer_id)
ORDER BY c.last_name, n.order_num;


-- 6. Товары, которые покупают вместе
WITH pairs AS (
    SELECT
        a.product_id AS prod_a,
        b.product_id AS prod_b,
        count(DISTINCT a.order_id) AS together
    FROM order_items a
    JOIN order_items b
        ON  a.order_id = b.order_id
        AND a.product_id < b.product_id
    GROUP BY 1, 2
    HAVING count(DISTINCT a.order_id) >= 2
)
SELECT
    pa.name AS product_a,
    pb.name AS product_b,
    pairs.together
FROM pairs
JOIN products pa ON pa.product_id = pairs.prod_a
JOIN products pb ON pb.product_id = pairs.prod_b
ORDER BY together DESC
LIMIT 15;


-- 7. RFM-сегментация
WITH rfm AS (
    SELECT
        customer_id,
        current_date - max(created_at)::date  AS recency,
        count(order_id)                        AS frequency,
        sum(total_amount)                      AS monetary
    FROM orders
    WHERE status NOT IN ('cancelled', 'refunded')
    GROUP BY customer_id
),
scored AS (
    SELECT
        customer_id,
        ntile(5) OVER (ORDER BY recency DESC) AS r,
        ntile(5) OVER (ORDER BY frequency)     AS f,
        ntile(5) OVER (ORDER BY monetary)      AS m
    FROM rfm
)
SELECT
    c.first_name || ' ' || c.last_name AS customer,
    s.r, s.f, s.m,
    s.r + s.f + s.m AS total,
    CASE
        WHEN s.r >= 4 AND s.f >= 4 THEN 'VIP'
        WHEN s.r >= 4 AND s.f <= 2 THEN 'Новый перспективный'
        WHEN s.r <= 2 AND s.f >= 4 THEN 'Уходящий лояльный'
        WHEN s.r <= 2 AND s.f <= 2 THEN 'Потерянный'
        ELSE 'Средний'
    END AS segment
FROM scored s
JOIN customers c USING (customer_id)
ORDER BY total DESC;


-- 8. Доля товара в выручке категории
SELECT
    c.name  AS category,
    p.name  AS product,
    sum(oi.quantity * oi.unit_price) AS revenue,
    round(
        sum(oi.quantity * oi.unit_price)
        / sum(sum(oi.quantity * oi.unit_price))
            OVER (PARTITION BY c.category_id) * 100,
    2) AS pct_of_category
FROM order_items oi
JOIN orders o     USING (order_id)
JOIN products p   USING (product_id)
JOIN categories c USING (category_id)
WHERE o.status NOT IN ('cancelled', 'refunded')
GROUP BY c.category_id, c.name, p.product_id, p.name
ORDER BY c.name, revenue DESC;


-- 9. Ни разу не купленные товары
SELECT p.product_id, p.name, p.sku, p.price, p.stock_qty
FROM products p
LEFT JOIN order_items oi USING (product_id)
WHERE oi.item_id IS NULL
  AND p.is_active = true
ORDER BY p.created_at;


-- 10. Помесячная динамика и рост
WITH monthly AS (
    SELECT
        date_trunc('month', created_at)::date AS month,
        sum(total_amount) AS revenue,
        count(*)          AS orders_count
    FROM orders
    WHERE status NOT IN ('cancelled', 'refunded')
    GROUP BY 1
)
SELECT
    month,
    revenue,
    orders_count,
    lag(revenue) OVER (ORDER BY month) AS prev_revenue,
    CASE
        WHEN lag(revenue) OVER (ORDER BY month) > 0
        THEN round(
            (revenue - lag(revenue) OVER (ORDER BY month))
            / lag(revenue) OVER (ORDER BY month) * 100,
        1)
    END AS growth_pct
FROM monthly
ORDER BY month;