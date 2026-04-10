-- =============================================================
-- 04_VIEWS.SQL — Regular Views, Materialized Views, Updatable Views
-- Scenario: Analytics & Reporting Layer
-- =============================================================

-- ─── REGULAR VIEW ────────────────────────────────────────────
-- A saved query — always reflects current data, no storage
-- Use case: hide complexity, enforce column-level security

CREATE OR REPLACE VIEW v_order_summary AS
SELECT
    o.id            AS order_id,
    u.username,
    u.email,
    o.status,
    o.total,
    COUNT(oi.id)    AS item_count,
    o.created_at
FROM orders o
JOIN users u        ON u.id = o.user_id
JOIN order_items oi ON oi.order_id = o.id
GROUP BY o.id, u.username, u.email, o.status, o.total, o.created_at;

-- Query the view like a table
SELECT * FROM v_order_summary WHERE status = 'confirmed';

-- ─── VIEW WITH CHECK OPTION ───────────────────────────────────
-- Prevents inserting/updating rows that would disappear from the view
CREATE OR REPLACE VIEW v_active_products AS
SELECT id, sku, name, price, stock
FROM products
WHERE is_active = TRUE
WITH CHECK OPTION;  -- INSERT/UPDATE must satisfy WHERE is_active = TRUE

-- This INSERT will succeed (is_active defaults to TRUE)
-- INSERT INTO v_active_products (sku, name, price, stock) VALUES ('SKU-X', 'Test', 9.99, 10);

-- ─── SECURITY VIEW (column masking) ──────────────────────────
-- Expose users without sensitive fields
CREATE OR REPLACE VIEW v_public_users AS
SELECT id, username, role, created_at
FROM users
WHERE is_active = TRUE;

-- ─── MATERIALIZED VIEW ───────────────────────────────────────
-- Stores the result physically — fast reads, stale until refreshed
-- Use case: expensive aggregations, dashboards, reporting

CREATE MATERIALIZED VIEW mv_product_sales AS
SELECT
    p.id            AS product_id,
    p.name          AS product_name,
    p.sku,
    c.name          AS category,
    COALESCE(SUM(oi.quantity), 0)                   AS total_units_sold,
    COALESCE(SUM(oi.quantity * oi.unit_price), 0)   AS total_revenue,
    COUNT(DISTINCT oi.order_id)                     AS order_count
FROM products p
LEFT JOIN categories c      ON c.id = p.category_id
LEFT JOIN order_items oi    ON oi.product_id = p.id
LEFT JOIN orders o          ON o.id = oi.order_id AND o.status != 'cancelled'
GROUP BY p.id, p.name, p.sku, c.name
WITH NO DATA;  -- don't populate yet

-- Create index on materialized view for fast lookups
CREATE INDEX idx_mv_product_sales_revenue ON mv_product_sales (total_revenue DESC);

-- Populate / refresh the materialized view
REFRESH MATERIALIZED VIEW mv_product_sales;

-- Refresh WITHOUT locking reads (requires unique index)
CREATE UNIQUE INDEX idx_mv_product_sales_id ON mv_product_sales (product_id);
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_product_sales;

-- Query it
SELECT * FROM mv_product_sales ORDER BY total_revenue DESC;

-- ─── DAILY SALES MATERIALIZED VIEW ───────────────────────────
CREATE MATERIALIZED VIEW mv_daily_sales AS
SELECT
    DATE_TRUNC('day', o.created_at) AS sale_date,
    COUNT(DISTINCT o.id)            AS order_count,
    SUM(o.total)                    AS daily_revenue
FROM orders o
WHERE o.status != 'cancelled'
GROUP BY DATE_TRUNC('day', o.created_at)
WITH NO DATA;

REFRESH MATERIALIZED VIEW mv_daily_sales;

-- ─── RECURSIVE VIEW (CTE-based) ──────────────────────────────
-- Show full category hierarchy (parent → child → grandchild)
CREATE OR REPLACE VIEW v_category_tree AS
WITH RECURSIVE cat_tree AS (
    -- Base: top-level categories
    SELECT id, name, parent_id, name::TEXT AS path, 0 AS depth
    FROM categories
    WHERE parent_id IS NULL

    UNION ALL

    -- Recursive: children
    SELECT c.id, c.name, c.parent_id,
           (ct.path || ' > ' || c.name)::TEXT,
           ct.depth + 1
    FROM categories c
    JOIN cat_tree ct ON ct.id = c.parent_id
)
SELECT * FROM cat_tree ORDER BY path;

SELECT * FROM v_category_tree;

-- ─── DROP VIEWS ──────────────────────────────────────────────
-- DROP VIEW IF EXISTS v_order_summary;
-- DROP VIEW IF EXISTS v_active_products;
-- DROP MATERIALIZED VIEW IF EXISTS mv_product_sales;

-- ─── PITFALLS ────────────────────────────────────────────────
-- 1. Materialized views are STALE — must REFRESH after data changes
-- 2. REFRESH MATERIALIZED VIEW (without CONCURRENTLY) locks the view
-- 3. Regular views don't cache — complex views on large tables = slow
-- 4. Circular view dependencies are not allowed
-- 5. WITH CHECK OPTION only works on simple (updatable) views
