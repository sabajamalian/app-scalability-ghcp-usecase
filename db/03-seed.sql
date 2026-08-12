-- Seed data, generated rather than checked in so the repository stays small.
--
-- Volumes are tuned so `docker compose up` finishes in well under a minute on a
-- laptop while still being large enough that a sequential scan is measurable:
--
--   customers      30,000
--   products        1,000
--   orders        400,000
--   order_items ~1,600,000
--
-- To shrink the demo for a slower machine, lower the generate_series bounds
-- below. The scenarios still reproduce at roughly half these numbers; below
-- about 100,000 orders the sequential scan in scenario 2 gets too fast to be
-- interesting.

SET synchronous_commit = off;

INSERT INTO customers (email, full_name, country, created_at)
SELECT
    'customer' || g || '@example.test',
    'Customer ' || g,
    (ARRAY['US','CA','GB','DE','FR','JP','AU','BR'])[1 + (g % 8)],
    now() - (g % 900) * INTERVAL '1 day'
FROM generate_series(1, 30000) AS g;

INSERT INTO products (sku, name, category, price_cents)
SELECT
    'SKU-' || lpad(g::text, 6, '0'),
    'Product ' || g,
    (ARRAY['widgets','gadgets','hardware','software','services'])[1 + (g % 5)],
    500 + (g % 40000)
FROM generate_series(1, 1000) AS g;

INSERT INTO orders (customer_id, order_ref, status, total_cents, placed_at, notes)
SELECT
    1 + (g % 30000),
    'ORD-' || lpad(g::text, 9, '0'),
    -- Skewed on purpose. SHIPPED dominates, so a status filter alone is not
    -- selective enough to be interesting; the composite index is what matters.
    (ARRAY['PENDING','PAID','SHIPPED','SHIPPED','SHIPPED','DELIVERED','CANCELLED'])[1 + (g % 7)],
    1000 + (g % 250000),
    now() - (g % 720) * INTERVAL '1 hour',
    'Order note ' || g || ' ' || repeat('x', 280)
FROM generate_series(1, 400000) AS g;

-- Between 2 and 5 line items per order.
INSERT INTO order_items (order_id, product_id, quantity, unit_price_cents)
SELECT
    o.id,
    1 + ((o.id * i) % 1000),
    1 + (i % 4),
    500 + ((o.id + i) % 40000)
FROM orders o
CROSS JOIN LATERAL generate_series(1, 2 + (o.id % 4)) AS i;

-- Planner statistics must be current or EXPLAIN output in scenario 2 will be
-- misleading, and the whole demo is about trusting real measurements.
ANALYZE customers;
ANALYZE products;
ANALYZE orders;
ANALYZE order_items;
