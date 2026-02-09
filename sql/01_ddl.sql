-- ============================================================
-- VoltStore — DDL (Data Definition Language)
-- Создание схемы, таблиц, индексов, триггеров
-- ============================================================

DROP SCHEMA IF EXISTS store CASCADE;
CREATE SCHEMA store;
SET search_path TO store;

-- =========================
--      СПРАВОЧНИКИ
-- =========================

CREATE TABLE brands (
    brand_id    SERIAL PRIMARY KEY,
    name        VARCHAR(100) NOT NULL UNIQUE,
    country     VARCHAR(60)
);

CREATE TABLE categories (
    category_id SERIAL PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    slug        VARCHAR(100) NOT NULL UNIQUE,
    parent_id   INT REFERENCES categories(category_id)
                    ON DELETE SET NULL
);

CREATE INDEX idx_categories_parent ON categories(parent_id);

CREATE TABLE promo_codes (
    promo_id     SERIAL PRIMARY KEY,
    code         VARCHAR(30) NOT NULL UNIQUE,
    discount_pct NUMERIC(5,2) NOT NULL
                     CHECK (discount_pct > 0 AND discount_pct <= 100),
    valid_from   DATE NOT NULL,
    valid_until  DATE NOT NULL,
    max_uses     INT,
    times_used   INT NOT NULL DEFAULT 0,
    CHECK (valid_until >= valid_from)
);

-- =========================
--        КЛИЕНТЫ
-- =========================

CREATE TABLE customers (
    customer_id   SERIAL PRIMARY KEY,
    first_name    VARCHAR(60)  NOT NULL,
    last_name     VARCHAR(60)  NOT NULL,
    email         VARCHAR(120) NOT NULL UNIQUE,
    phone         VARCHAR(20),
    password_hash VARCHAR(256) NOT NULL,
    registered_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    is_deleted    BOOLEAN      NOT NULL DEFAULT false
);

CREATE INDEX idx_customers_email ON customers(email);

CREATE TABLE addresses (
    address_id  SERIAL PRIMARY KEY,
    customer_id INT NOT NULL
                    REFERENCES customers(customer_id) ON DELETE CASCADE,
    city        VARCHAR(100) NOT NULL,
    street      VARCHAR(200) NOT NULL,
    building    VARCHAR(20)  NOT NULL,
    apartment   VARCHAR(20),
    postal_code VARCHAR(10)  NOT NULL,
    is_default  BOOLEAN NOT NULL DEFAULT false
);

CREATE INDEX idx_addresses_customer ON addresses(customer_id);

-- =========================
--         ТОВАРЫ
-- =========================

CREATE TABLE products (
    product_id  SERIAL PRIMARY KEY,
    name        VARCHAR(200) NOT NULL,
    sku         VARCHAR(50)  NOT NULL UNIQUE,
    description TEXT,
    price       NUMERIC(10,2) NOT NULL CHECK (price > 0),
    stock_qty   INT NOT NULL DEFAULT 0 CHECK (stock_qty >= 0),
    category_id INT NOT NULL
                    REFERENCES categories(category_id) ON DELETE RESTRICT,
    brand_id    INT REFERENCES brands(brand_id) ON DELETE SET NULL,
    weight_kg   NUMERIC(7,3),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_active   BOOLEAN NOT NULL DEFAULT true
);

CREATE INDEX idx_products_category ON products(category_id);
CREATE INDEX idx_products_brand    ON products(brand_id);
CREATE INDEX idx_products_name     ON products(name varchar_pattern_ops);

-- частичный индекс: только активные товары
CREATE INDEX idx_products_active ON products(product_id)
    WHERE is_active = true;

CREATE TABLE product_images (
    image_id    SERIAL PRIMARY KEY,
    product_id  INT NOT NULL
                    REFERENCES products(product_id) ON DELETE CASCADE,
    url         VARCHAR(500) NOT NULL,
    sort_order  SMALLINT NOT NULL DEFAULT 0
);

CREATE INDEX idx_images_product ON product_images(product_id);

CREATE TABLE price_history (
    id          SERIAL PRIMARY KEY,
    product_id  INT NOT NULL
                    REFERENCES products(product_id) ON DELETE CASCADE,
    old_price   NUMERIC(10,2) NOT NULL,
    new_price   NUMERIC(10,2) NOT NULL,
    changed_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_price_hist_product
    ON price_history(product_id, changed_at DESC);

-- =========================
--         ЗАКАЗЫ
-- =========================

CREATE TABLE orders (
    order_id     SERIAL PRIMARY KEY,
    customer_id  INT NOT NULL
                     REFERENCES customers(customer_id) ON DELETE RESTRICT,
    address_id   INT REFERENCES addresses(address_id) ON DELETE SET NULL,
    promo_id     INT REFERENCES promo_codes(promo_id) ON DELETE SET NULL,
    status       VARCHAR(30) NOT NULL DEFAULT 'new'
                     CHECK (status IN (
                         'new', 'confirmed', 'processing',
                         'shipped', 'delivered', 'cancelled', 'refunded'
                     )),
    total_amount NUMERIC(12,2) NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    shipped_at   TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ
);

CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_orders_status   ON orders(status);
CREATE INDEX idx_orders_created  ON orders(created_at DESC);

CREATE TABLE order_items (
    item_id    SERIAL PRIMARY KEY,
    order_id   INT NOT NULL
                   REFERENCES orders(order_id) ON DELETE CASCADE,
    product_id INT NOT NULL
                   REFERENCES products(product_id) ON DELETE RESTRICT,
    quantity   INT NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10,2) NOT NULL
);

CREATE INDEX idx_oitems_order   ON order_items(order_id);
CREATE INDEX idx_oitems_product ON order_items(product_id);

-- =========================
--         ОПЛАТА
-- =========================

CREATE TABLE payments (
    payment_id SERIAL PRIMARY KEY,
    order_id   INT NOT NULL UNIQUE
                   REFERENCES orders(order_id) ON DELETE CASCADE,
    method     VARCHAR(30) NOT NULL
                   CHECK (method IN (
                       'card', 'cash', 'online_wallet', 'bank_transfer'
                   )),
    status     VARCHAR(30) NOT NULL DEFAULT 'pending'
                   CHECK (status IN (
                       'pending', 'completed', 'failed', 'refunded'
                   )),
    paid_at    TIMESTAMPTZ,
    amount     NUMERIC(12,2) NOT NULL
);

-- =========================
--         ОТЗЫВЫ
-- =========================

CREATE TABLE reviews (
    review_id   SERIAL PRIMARY KEY,
    product_id  INT NOT NULL
                    REFERENCES products(product_id) ON DELETE CASCADE,
    customer_id INT NOT NULL
                    REFERENCES customers(customer_id) ON DELETE CASCADE,
    rating      SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment     TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (product_id, customer_id)
);

CREATE INDEX idx_reviews_product ON reviews(product_id);

-- =========================
--       ИЗБРАННОЕ
-- =========================

CREATE TABLE wishlists (
    customer_id INT NOT NULL
                    REFERENCES customers(customer_id) ON DELETE CASCADE,
    product_id  INT NOT NULL
                    REFERENCES products(product_id) ON DELETE CASCADE,
    added_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (customer_id, product_id)
);

-- =========================
--  ТРИГГЕР: история цен
-- =========================

CREATE OR REPLACE FUNCTION fn_log_price_change()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.price IS DISTINCT FROM NEW.price THEN
        INSERT INTO price_history(product_id, old_price, new_price)
        VALUES (NEW.product_id, OLD.price, NEW.price);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_price_change
    AFTER UPDATE ON products
    FOR EACH ROW
    EXECUTE FUNCTION fn_log_price_change();