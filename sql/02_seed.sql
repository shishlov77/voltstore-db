-- ============================================================
-- VoltStore — заполнение тестовыми данными
-- ============================================================

SET search_path TO store;

-- ===================== БРЕНДЫ ===============================

INSERT INTO brands (name, country) VALUES
    ('Samsung',  'Южная Корея'),
    ('Apple',    'США'),
    ('Xiaomi',   'Китай'),
    ('Sony',     'Япония'),
    ('LG',       'Южная Корея'),
    ('Bosch',    'Германия'),
    ('Dyson',    'Великобритания'),
    ('Huawei',   'Китай'),
    ('ASUS',     'Тайвань'),
    ('Philips',  'Нидерланды');

-- ===================== КАТЕГОРИИ ============================
-- корневые
-- корневые (явно задаём id чтобы не зависеть от счётчика)
INSERT INTO categories (category_id, name, slug, parent_id) VALUES
    (1,  'Электроника',     'electronics',  NULL),
    (2,  'Бытовая техника', 'appliances',   NULL),
    (3,  'Аксессуары',      'accessories',  NULL);

-- дочерние
INSERT INTO categories (category_id, name, slug, parent_id) VALUES
    (4,  'Смартфоны',           'smartphones',      1),
    (5,  'Ноутбуки',            'laptops',          1),
    (6,  'Телевизоры',          'tvs',              1),
    (7,  'Наушники',            'headphones',       1),
    (8,  'Пылесосы',            'vacuums',          2),
    (9,  'Стиральные машины',   'washing-machines', 2),
    (10, 'Чехлы',               'cases',            3),
    (11, 'Зарядные устройства', 'chargers',         3),
    (12, 'Планшеты',            'tablets',          1),
    (13, 'Игровые ноутбуки',    'gaming-laptops',   5);

-- сдвигаем счётчик чтобы следующая вставка шла с 14
SELECT setval('store.categories_category_id_seq', 13);

-- ===================== ПРОМОКОДЫ ============================

INSERT INTO promo_codes (code, discount_pct, valid_from, valid_until, max_uses) VALUES
    ('WELCOME10', 10.00, '2024-01-01', '2025-12-31', 1000),
    ('SUMMER25',  25.00, '2024-06-01', '2024-08-31', 500),
    ('NEWYEAR15', 15.00, '2024-12-20', '2025-01-10', 300),
    ('VIP30',     30.00, '2024-01-01', '2025-12-31', 50);

-- ===================== КЛИЕНТЫ (50 шт) ======================

INSERT INTO customers (first_name, last_name, email, phone, password_hash)
SELECT
    (ARRAY[
        'Алексей','Мария','Дмитрий','Анна','Сергей',
        'Екатерина','Иван','Ольга','Андрей','Наталья',
        'Павел','Елена','Михаил','Татьяна','Артём'
    ])[1 + floor(random() * 15)::int],

    (ARRAY[
        'Иванов','Петров','Сидоров','Козлов','Новиков',
        'Морозов','Волков','Соколов','Лебедев','Попов',
        'Кузнецов','Фёдоров','Смирнов','Егоров','Тарасов'
    ])[1 + floor(random() * 15)::int],

    'user' || gs || '_' || substr(md5(random()::text), 1, 4) || '@mail.ru',

    '+7' || lpad(
        (floor(random() * 9000000000) + 1000000000)::bigint::text,
        10, '0'
    ),

    md5(random()::text || clock_timestamp()::text)
FROM generate_series(1, 50) gs;

-- ===================== АДРЕСА ===============================
-- по одному основному адресу каждому
INSERT INTO addresses (customer_id, city, street, building, apartment, postal_code, is_default)
SELECT
    c.customer_id,
    (ARRAY[
        'Москва','Санкт-Петербург','Новосибирск','Екатеринбург',
        'Казань','Нижний Новгород','Самара','Ростов-на-Дону',
        'Краснодар','Воронеж'
    ])[1 + floor(random() * 10)::int],
    'ул. ' || (ARRAY[
        'Ленина','Пушкина','Гагарина','Мира','Советская',
        'Кирова','Строителей','Парковая','Лесная','Центральная'
    ])[1 + floor(random() * 10)::int],
    (1 + floor(random() * 120))::int::text,
    CASE WHEN random() > 0.3
         THEN (1 + floor(random() * 200))::int::text
         ELSE NULL END,
    (100000 + floor(random() * 900000))::int::text,
    true
FROM customers c;

-- второй адрес ~40% клиентов
INSERT INTO addresses (customer_id, city, street, building, apartment, postal_code, is_default)
SELECT
    c.customer_id,
    (ARRAY['Тула','Омск','Пермь','Волгоград','Уфа']
    )[1 + floor(random() * 5)::int],
    'пр-т ' || (ARRAY['Победы','Революции','Октября','Космонавтов','Труда']
    )[1 + floor(random() * 5)::int],
    (1 + floor(random() * 80))::int::text,
    (1 + floor(random() * 150))::int::text,
    (100000 + floor(random() * 900000))::int::text,
    false
FROM customers c
WHERE random() < 0.4;

-- ===================== ТОВАРЫ (80 шт) =======================

INSERT INTO products (name, sku, description, price, stock_qty, category_id, brand_id, weight_kg)
SELECT
    product_name,
    'SKU-' || upper(substr(md5(product_name || gs::text), 1, 8)),
    'Отличный товар. ' || product_name || '. Гарантия производителя.',
    round((500 + random() * 199500)::numeric, 2),
    floor(random() * 200)::int,
    cat_id,
    (1 + floor(random() * 10))::int,
    round((0.1 + random() * 15)::numeric, 3)
FROM (
    SELECT
        gs,
        (ARRAY[
            'Galaxy S24 Ultra','iPhone 15 Pro','Redmi Note 13','Xperia 1 V',
            'MacBook Air M2','ASUS ROG Strix G16','Huawei MateBook 14','LG Gram 17',
            'OLED TV 55"','QLED TV 65"','NanoCell TV 50"','Bravia XR 75"',
            'WH-1000XM5','AirPods Pro 2','Buds3 Pro','FreeBuds Pro 3',
            'Dyson V15 Detect','Jet Bot AI+','Serie 4 WGA25400','Bosch iQ500',
            'Чехол кожаный iPhone','Чехол силиконовый Galaxy','USB-C 65W GaN',
            'MagSafe зарядка','iPad Air 11','Galaxy Tab S9','MatePad Pro',
            'ROG Strix RTX4060','ZenBook 14','ProBook 450 G10',
            'Dyson V12','Bosch BGS5ZOORU','Робот-пылесос Xiaomi','Electrolux Pure i9',
            'Samsung AddWash','LG AI DD 9kg','Candy Smart Pro','Beko WRS 5512',
            'JBL Tune 770NC','Marshall Major IV','Beats Solo 4','Sennheiser HD 660S2',
            'ROG Phone 8 Pro','Nothing Phone 2','Pixel 8 Pro','OnePlus 12',
            'Smart TV 43" LG','Philips Ambilight 58"','Hisense ULED 65"','TCL C845 55"',
            'Кабель HDMI 2.1','USB-C Hub 7-в-1','Мышь Logitech MX','Клавиатура K380',
            'Power Bank 20000','Стабилизатор DJI OM7','Лампа Philips Hue','Колонка JBL Flip 6',
            'Galaxy Watch 6','Apple Watch Ultra 2','Amazfit GTR 4','Huawei Watch GT4',
            'PS5 DualSense','Xbox Controller','Nintendo Pro Controller','Steam Deck OLED',
            'GoPro Hero 12','DJI Mini 4 Pro','Instax Mini 12','Canon EOS R50',
            'Xiaomi Air Purifier','Dyson Pure Cool','Philips AC1215','Samsung AX60',
            'Nespresso Vertuo','DeLonghi Magnifica','Bosch Tassimo','Krups Evidence'
        ])[gs] AS product_name,
        (ARRAY[
            4,4,4,4,  5,13,5,5,  6,6,6,6,  7,7,7,7,
            8,8,9,9,  10,10,11,11,  12,12,12,  13,5,5,
            8,8,8,8,  9,9,9,9,  7,7,7,7,  4,4,4,4,
            6,6,6,6,  3,3,3,3,  3,3,3,3,  3,3,3,3,
            3,3,3,3,  3,3,3,3,  2,2,2,2,  2,2,2,2
        ])[gs] AS cat_id
    FROM generate_series(1, 80) gs
) sub;

-- ===================== ИЗОБРАЖЕНИЯ ==========================

INSERT INTO product_images (product_id, url, sort_order)
SELECT
    p.product_id,
    'https://cdn.voltstore.ru/img/' || p.sku || '_' || n || '.webp',
    n
FROM products p
CROSS JOIN generate_series(1, 2) n;

-- ===================== ЗАКАЗЫ (200 шт) ======================

INSERT INTO orders (customer_id, address_id, promo_id, status, total_amount, created_at)
SELECT
    c_id,
    a_id,
    CASE WHEN random() < 0.2
         THEN (1 + floor(random() * 4))::int
         ELSE NULL END,
    (ARRAY[
        'new','confirmed','processing','shipped',
        'delivered','delivered','delivered'
    ])[1 + floor(random() * 7)::int],
    0,
    now() - (interval '1 day' * floor(random() * 365))
FROM generate_series(1, 200) gs,
LATERAL (
    SELECT customer_id AS c_id FROM customers ORDER BY random() LIMIT 1
) rc,
LATERAL (
    SELECT address_id AS a_id FROM addresses
    WHERE customer_id = c_id LIMIT 1
) ra;

-- ===================== ПОЗИЦИИ ЗАКАЗОВ ======================

INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT
    o.order_id,
    p.product_id,
    (1 + floor(random() * 3))::int,
    p.price
FROM orders o
CROSS JOIN LATERAL (
    SELECT product_id, price
    FROM products
    ORDER BY random()
    LIMIT (1 + floor(random() * 4))::int
) p;

-- пересчёт итоговой суммы
UPDATE orders o
SET total_amount = sub.total
FROM (
    SELECT order_id, sum(quantity * unit_price) AS total
    FROM order_items
    GROUP BY order_id
) sub
WHERE o.order_id = sub.order_id;

-- применяем скидку по промокоду
UPDATE orders o
SET total_amount = round(o.total_amount * (1 - pc.discount_pct / 100.0), 2)
FROM promo_codes pc
WHERE o.promo_id = pc.promo_id
  AND o.promo_id IS NOT NULL;

-- ===================== ОПЛАТЫ ===============================

INSERT INTO payments (order_id, method, status, paid_at, amount)
SELECT
    o.order_id,
    (ARRAY['card','cash','online_wallet','bank_transfer']
    )[1 + floor(random() * 4)::int],
    CASE
        WHEN o.status IN ('delivered','shipped','processing','confirmed')
        THEN 'completed'
        ELSE 'pending'
    END,
    CASE
        WHEN o.status IN ('delivered','shipped','processing','confirmed')
        THEN o.created_at + interval '1 minute' * (5 + floor(random() * 120))
        ELSE NULL
    END,
    o.total_amount
FROM orders o;

-- ===================== ОТЗЫВЫ ===============================

INSERT INTO reviews (product_id, customer_id, rating, comment, created_at)
SELECT DISTINCT ON (pr.product_id, cu.customer_id)
    pr.product_id,
    cu.customer_id,
    (1 + floor(random() * 5))::int,
    (ARRAY[
        'Отличный товар, рекомендую!',
        'Всё пришло в срок, качество хорошее.',
        'Нормально за свои деньги.',
        'Есть мелкие недочёты, но в целом ок.',
        'Не очень понравилось, ожидал большего.',
        'Супер! Пользуюсь каждый день.',
        'Средненько, но работает.',
        'Доставили быстро, упаковка целая.',
        NULL
    ])[1 + floor(random() * 9)::int],
    now() - interval '1 day' * floor(random() * 180)
FROM generate_series(1, 150) gs
CROSS JOIN LATERAL (
    SELECT product_id FROM products ORDER BY random() LIMIT 1
) pr
CROSS JOIN LATERAL (
    SELECT customer_id FROM customers ORDER BY random() LIMIT 1
) cu
ON CONFLICT (product_id, customer_id) DO NOTHING;

-- ===================== ИЗБРАННОЕ ============================

INSERT INTO wishlists (customer_id, product_id)
SELECT cu.customer_id, pr.product_id
FROM generate_series(1, 120) gs
CROSS JOIN LATERAL (
    SELECT customer_id FROM customers ORDER BY random() LIMIT 1
) cu
CROSS JOIN LATERAL (
    SELECT product_id FROM products ORDER BY random() LIMIT 1
) pr
ON CONFLICT DO NOTHING;