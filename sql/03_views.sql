-- ============================================================
-- VoltStore — представления (Views)
-- ============================================================

SET search_path TO store;

-- Витрина товаров
CREATE OR REPLACE VIEW v_product_catalog AS
SELECT
    p.product_id,
    p.name                              AS product_name,
    p.sku,
    p.price,
    p.stock_qty,
    c.name                              AS category,
    b.name                              AS brand,
    coalesce(r.avg_rating, 0)           AS avg_rating,
    coalesce(r.review_count, 0)         AS review_count
FROM products p
JOIN categories c USING (category_id)
LEFT JOIN brands b USING (brand_id)
LEFT JOIN (
    SELECT
        product_id,
        round(avg(rating), 1)  AS avg_rating,
        count(*)               AS review_count
    FROM reviews
    GROUP BY product_id
) r USING (product_id)
WHERE p.is_active = true;


-- Статистика клиентов
CREATE OR REPLACE VIEW v_customer_stats AS
SELECT
    c.customer_id,
    c.first_name || ' ' || c.last_name  AS full_name,
    c.email,
    count(o.order_id)                    AS orders_count,
    coalesce(sum(o.total_amount), 0)     AS total_spent,
    max(o.created_at)                    AS last_order_at
FROM customers c
LEFT JOIN orders o USING (customer_id)
WHERE c.is_deleted = false
GROUP BY c.customer_id, c.first_name, c.last_name, c.email;


-- Дерево категорий (рекурсивное)
CREATE OR REPLACE VIEW v_category_tree AS
WITH RECURSIVE tree AS (
    SELECT
        category_id, name, slug, parent_id,
        name::text AS full_path,
        1          AS depth
    FROM categories
    WHERE parent_id IS NULL

    UNION ALL

    SELECT
        c.category_id, c.name, c.slug, c.parent_id,
        t.full_path || ' → ' || c.name,
        t.depth + 1
    FROM categories c
    JOIN tree t ON c.parent_id = t.category_id
)
SELECT * FROM tree ORDER BY full_path;