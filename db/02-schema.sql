-- Demo schema: a small order-management domain.
--
-- Two things about this schema are DELIBERATE and are the point of the demo.
--
--   1. order_items.order_id and orders.customer_id ARE indexed. Scenario 1 is
--      about running too many *fast* queries (N+1 amplification), not about
--      slow ones. Keeping these indexed isolates the variable.
--
--   2. orders.status and orders.placed_at are NOT indexed. Scenario 2 is about
--      one *slow* query (sequential scan). Do not "fix" this by hand before
--      running the demo.
--
-- PostgreSQL does not create indexes on foreign key columns automatically, so
-- the indexes below are explicit on purpose.

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
    -- Free-text field. Present so the orders table occupies enough pages that a
    -- sequential scan is measurably expensive, which is what scenario 2 needs.
    notes       TEXT        NOT NULL
);

CREATE TABLE order_items (
    id               BIGSERIAL PRIMARY KEY,
    order_id         BIGINT    NOT NULL REFERENCES orders (id),
    product_id       BIGINT    NOT NULL REFERENCES products (id),
    quantity         INTEGER   NOT NULL,
    unit_price_cents INTEGER   NOT NULL
);

-- Intentionally present: keeps scenario 1 about query COUNT, not query COST.
CREATE INDEX idx_orders_customer_id ON orders (customer_id);
CREATE INDEX idx_order_items_order_id ON order_items (order_id);

-- Intentionally ABSENT: orders (status, placed_at).
-- That is scenario 2. Let Copilot find it.
