-- ============================================================
-- VoltStore — процедуры и функции
-- ============================================================

SET search_path TO store;

-- Процедура: оформление заказа
CREATE OR REPLACE PROCEDURE sp_place_order(
    p_customer_id INT,
    p_address_id  INT,
    p_product_ids INT[],
    p_quantities  INT[],
    p_promo_code  VARCHAR DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_id INT;
    v_total    NUMERIC(12,2) := 0;
    v_promo_id INT;
    v_discount NUMERIC(5,2) := 0;
    v_price    NUMERIC(10,2);
    v_stock    INT;
    i          INT;
BEGIN
    -- массивы должны совпадать по длине
    IF array_length(p_product_ids, 1) != array_length(p_quantities, 1) THEN
        RAISE EXCEPTION 'Длины массивов товаров и количеств не совпадают';
    END IF;

    -- проверяем промокод
    IF p_promo_code IS NOT NULL THEN
        SELECT promo_id, discount_pct
        INTO v_promo_id, v_discount
        FROM promo_codes
        WHERE code = p_promo_code
          AND current_date BETWEEN valid_from AND valid_until
          AND (max_uses IS NULL OR times_used < max_uses);

        IF v_promo_id IS NULL THEN
            RAISE EXCEPTION 'Промокод "%" недействителен или истёк', p_promo_code;
        END IF;
    END IF;

    -- создаём заказ
    INSERT INTO orders (customer_id, address_id, promo_id, status, total_amount)
    VALUES (p_customer_id, p_address_id, v_promo_id, 'new', 0)
    RETURNING order_id INTO v_order_id;

    -- добавляем позиции
    FOR i IN 1..array_length(p_product_ids, 1) LOOP

        SELECT price, stock_qty INTO v_price, v_stock
        FROM products
        WHERE product_id = p_product_ids[i] AND is_active = true
        FOR UPDATE;

        IF v_price IS NULL THEN
            RAISE EXCEPTION 'Товар id=% не найден или неактивен', p_product_ids[i];
        END IF;

        IF v_stock < p_quantities[i] THEN
            RAISE EXCEPTION 'Товар id=%: на складе % шт., запрошено %',
                p_product_ids[i], v_stock, p_quantities[i];
        END IF;

        INSERT INTO order_items (order_id, product_id, quantity, unit_price)
        VALUES (v_order_id, p_product_ids[i], p_quantities[i], v_price);

        UPDATE products
        SET stock_qty = stock_qty - p_quantities[i]
        WHERE product_id = p_product_ids[i];

        v_total := v_total + v_price * p_quantities[i];
    END LOOP;

    -- скидка
    IF v_discount > 0 THEN
        v_total := round(v_total * (1 - v_discount / 100.0), 2);
        UPDATE promo_codes SET times_used = times_used + 1
        WHERE promo_id = v_promo_id;
    END IF;

    UPDATE orders SET total_amount = v_total WHERE order_id = v_order_id;

    RAISE NOTICE 'Заказ #% создан. Сумма: % руб.', v_order_id, v_total;
END;
$$;


-- Функция: полный путь категории
CREATE OR REPLACE FUNCTION fn_category_path(p_category_id INT)
RETURNS TEXT
LANGUAGE sql STABLE
AS $$
    WITH RECURSIVE chain AS (
        SELECT category_id, name, parent_id
        FROM categories
        WHERE category_id = p_category_id

        UNION ALL

        SELECT c.category_id, c.name, c.parent_id
        FROM categories c
        JOIN chain ch ON c.category_id = ch.parent_id
    )
    SELECT string_agg(name, ' → ' ORDER BY category_id)
    FROM chain;
$$;


-- Функция: топ товаров по выручке за период
CREATE OR REPLACE FUNCTION fn_top_products_by_revenue(
    p_from  DATE,
    p_to    DATE,
    p_limit INT DEFAULT 10
)
RETURNS TABLE (
    product_id   INT,
    product_name VARCHAR,
    total_qty    BIGINT,
    revenue      NUMERIC
)
LANGUAGE sql STABLE
AS $$
    SELECT
        p.product_id,
        p.name,
        sum(oi.quantity)::bigint,
        sum(oi.quantity * oi.unit_price)
    FROM order_items oi
    JOIN orders o  USING (order_id)
    JOIN products p USING (product_id)
    WHERE o.created_at::date BETWEEN p_from AND p_to
      AND o.status NOT IN ('cancelled', 'refunded')
    GROUP BY p.product_id, p.name
    ORDER BY 4 DESC
    LIMIT p_limit;
$$;