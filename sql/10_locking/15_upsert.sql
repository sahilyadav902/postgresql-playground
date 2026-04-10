-- =============================================================
-- 15_UPSERT.SQL — ON CONFLICT (INSERT ... ON CONFLICT DO UPDATE/NOTHING)
-- Scenario: Analytics event counters, idempotent writes, sync patterns
-- =============================================================

-- ─── BASIC UPSERT: DO NOTHING ────────────────────────────────
-- Silently skip if the row already exists (idempotent insert)
INSERT INTO categories (name)
VALUES ('Electronics')
ON CONFLICT (name) DO NOTHING;

-- ─── UPSERT: DO UPDATE (MERGE / upsert) ──────────────────────
-- Insert or update if conflict on unique key
-- EXCLUDED refers to the row that was proposed for insertion
INSERT INTO products (sku, name, price, stock)
VALUES ('SKU-001', 'iPhone 15', 999.99, 50)
ON CONFLICT (sku)
DO UPDATE SET
    name  = EXCLUDED.name,
    price = EXCLUDED.price,
    stock = EXCLUDED.stock,
    updated_at = NOW()
RETURNING id, sku, name, price, stock;

-- ─── UPSERT: conditional update ──────────────────────────────
-- Only update price if the new price is lower (price protection)
INSERT INTO products (sku, name, price, stock)
VALUES ('SKU-001', 'iPhone 15', 899.99, 60)
ON CONFLICT (sku)
DO UPDATE SET
    price = LEAST(products.price, EXCLUDED.price),  -- keep lower price
    stock = products.stock + EXCLUDED.stock          -- accumulate stock
WHERE products.price > EXCLUDED.price;              -- only if new price is lower

-- ─── UPSERT: atomic counter (rate limiter, analytics) ────────
CREATE TABLE IF NOT EXISTS page_views (
    page        VARCHAR(500) NOT NULL,
    view_date   DATE NOT NULL DEFAULT CURRENT_DATE,
    view_count  BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (page, view_date)
);

-- Atomic increment — safe under concurrent load
INSERT INTO page_views (page, view_date, view_count)
VALUES ('/home', CURRENT_DATE, 1)
ON CONFLICT (page, view_date)
DO UPDATE SET view_count = page_views.view_count + 1
RETURNING view_count;

-- ─── UPSERT: sync from external source ───────────────────────
-- Bulk upsert from a staging table
CREATE TEMP TABLE staging_products (
    sku   VARCHAR(100),
    name  VARCHAR(255),
    price NUMERIC(12,2),
    stock INT
);

INSERT INTO staging_products VALUES
    ('SKU-001', 'iPhone 15 Updated', 949.99, 55),
    ('SKU-NEW', 'New Product',        29.99, 200);

INSERT INTO products (sku, name, price, stock)
SELECT sku, name, price, stock FROM staging_products
ON CONFLICT (sku)
DO UPDATE SET
    name  = EXCLUDED.name,
    price = EXCLUDED.price,
    stock = EXCLUDED.stock,
    updated_at = NOW();

-- ─── UPSERT with RETURNING ───────────────────────────────────
-- Know whether it was an INSERT or UPDATE
INSERT INTO users (email, username, display_name, role)
VALUES ('new@example.com', 'newuser', 'New User', 'customer')
ON CONFLICT (email)
DO UPDATE SET display_name = EXCLUDED.display_name
RETURNING id, email, (xmax = 0) AS was_inserted;
-- xmax = 0 means it was a fresh INSERT; xmax != 0 means UPDATE

-- ─── PITFALLS ────────────────────────────────────────────────
-- 1. ON CONFLICT requires a unique/PK constraint — not just any column
-- 2. DO UPDATE SET fires triggers; DO NOTHING does not
-- 3. EXCLUDED.col refers to the proposed (rejected) row's value
-- 4. Concurrent upserts can still deadlock — use consistent ordering
-- 5. xmax trick for INSERT vs UPDATE detection is an internal detail — use carefully
