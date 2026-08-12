-- Test schema for the query-count regression test.
--
-- Mirrors db/02-schema.sql but without the seed volume: the test asserts how
-- many SQL statements a request issues, and that number does not depend on how
-- many rows exist. Keeping this small keeps CI fast.

CREATE TABLE customers (
    id          BIGSERIAL PRIMARY KEY,
    email       TEXT        NOT NULL UNIQUE,
    full_name   TEXT        NOT NULL,
    country     TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE products (
    id          BIGSERIAL PRIMARY KEY,
    sku         TEXT        NOT NULL UNIQUE,
    name        TEXT        NOT NULL,
    category    TEXT        NOT NULL,
    price_cents INTEGER     NOT NULL
);

CREATE TABLE orders (
    id          BIGSERIAL   PRIMARY KEY,
    customer_id BIGINT      NOT NULL REFERENCES customers (id),
    order_ref   TEXT        NOT NULL,
    status      TEXT        NOT NULL,
    total_cents BIGINT      NOT NULL,
    placed_at   TIMESTAMPTZ NOT NULL,
    notes       TEXT        NOT NULL
);

CREATE TABLE order_items (
    id               BIGSERIAL PRIMARY KEY,
    order_id         BIGINT    NOT NULL REFERENCES orders (id),
    product_id       BIGINT    NOT NULL REFERENCES products (id),
    quantity         INTEGER   NOT NULL,
    unit_price_cents INTEGER   NOT NULL
);

CREATE INDEX idx_orders_customer_id ON orders (customer_id);
CREATE INDEX idx_order_items_order_id ON order_items (order_id);

-- Note: orders (status, placed_at) is intentionally absent here too, so the
-- test schema matches the demo's starting state.

INSERT INTO customers (email, full_name, country)
SELECT 'user' || i || '@example.test', 'Customer ' || i, 'US'
FROM generate_series(1, 40) AS i;

INSERT INTO products (sku, name, category, price_cents)
SELECT 'SKU-' || i, 'Product ' || i, 'general', 100 + i
FROM generate_series(1, 40) AS i;

INSERT INTO orders (customer_id, order_ref, status, total_cents, placed_at, notes)
SELECT ((i % 40) + 1),
       'ORD-' || i,
       (ARRAY['NEW', 'PAID', 'SHIPPED', 'CANCELLED'])[(i % 4) + 1],
       1000 + i,
       now() - (i || ' minutes')::interval,
       'test order'
FROM generate_series(1, 40) AS i;

INSERT INTO order_items (order_id, product_id, quantity, unit_price_cents)
SELECT o.id, ((o.id + n) % 40) + 1, 1 + n, 500
FROM orders o
CROSS JOIN generate_series(1, 3) AS n;
