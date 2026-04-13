-- =============================================================
-- 20_INHERITANCE_COPY_TABLESAMPLE.SQL
-- Covers: Table Inheritance, COPY bulk I/O, TABLESAMPLE,
--         Lateral joins deep-dive, GROUPING SETS / ROLLUP / CUBE
-- =============================================================

-- ═══════════════════════════════════════════════════════════════
-- PART 1: TABLE INHERITANCE
-- ═══════════════════════════════════════════════════════════════
-- PostgreSQL supports OOP-style table inheritance.
-- Child tables inherit all columns from parent.
-- Queries on parent include rows from all children.
-- Use case: polymorphic entities (vehicles, payments, notifications)

CREATE TABLE vehicles (
    id          SERIAL PRIMARY KEY,
    make        VARCHAR(100) NOT NULL,
    model       VARCHAR(100) NOT NULL,
    year        INT NOT NULL,
    price       NUMERIC(12,2) NOT NULL
);

CREATE TABLE cars (
    doors       INT NOT NULL DEFAULT 4,
    fuel_type   VARCHAR(20) NOT NULL DEFAULT 'petrol'
) INHERITS (vehicles);

CREATE TABLE motorcycles (
    engine_cc   INT NOT NULL
) INHERITS (vehicles);

CREATE TABLE trucks (
    payload_tons NUMERIC(6,2) NOT NULL
) INHERITS (vehicles);

INSERT INTO cars (make, model, year, price, doors, fuel_type)
VALUES ('Toyota', 'Camry', 2024, 28000, 4, 'hybrid');

INSERT INTO motorcycles (make, model, year, price, engine_cc)
VALUES ('Honda', 'CBR600', 2024, 12000, 600);

INSERT INTO trucks (make, model, year, price, payload_tons)
VALUES ('Ford', 'F-150', 2024, 45000, 1.5);

-- Query parent: returns ALL vehicles (cars + motorcycles + trucks)
SELECT * FROM vehicles;

-- Query only cars (ONLY keyword excludes children)
SELECT * FROM ONLY vehicles;  -- only rows directly in vehicles table

-- Find which table a row belongs to
SELECT tableoid::regclass AS source_table, make, model
FROM vehicles;

-- ═══════════════════════════════════════════════════════════════
-- PART 2: COPY — Bulk Import/Export
-- ═══════════════════════════════════════════════════════════════

-- Export to CSV (server-side file path)
-- COPY products TO '/tmp/products_export.csv'
--     WITH (FORMAT CSV, HEADER TRUE, DELIMITER ',', NULL 'NULL');

-- Export specific columns
-- COPY (SELECT id, sku, name, price FROM products WHERE is_active = true)
--     TO '/tmp/active_products.csv' WITH (FORMAT CSV, HEADER TRUE);

-- Import from CSV
-- COPY products (sku, name, price, stock)
--     FROM '/tmp/products_import.csv'
--     WITH (FORMAT CSV, HEADER TRUE, NULL 'NULL');

-- Binary format (fastest, not human-readable)
-- COPY products TO '/tmp/products.bin' WITH (FORMAT BINARY);
-- COPY products FROM '/tmp/products.bin' WITH (FORMAT BINARY);

-- \COPY (client-side, works from psql without superuser)
-- \copy products TO 'C:/tmp/products.csv' WITH (FORMAT CSV, HEADER)
-- \copy products FROM 'C:/tmp/products.csv' WITH (FORMAT CSV, HEADER)

-- COPY with transformation via CTE
-- COPY (
--     WITH enriched AS (
--         SELECT p.sku, p.name, p.price, c.name AS category
--         FROM products p LEFT JOIN categories c ON c.id = p.category_id
--     )
--     SELECT * FROM enriched
-- ) TO '/tmp/enriched_products.csv' WITH (FORMAT CSV, HEADER);

-- ═══════════════════════════════════════════════════════════════
-- PART 3: TABLESAMPLE — Random sampling
-- ═══════════════════════════════════════════════════════════════

-- SYSTEM: block-level sampling (fast, less random)
SELECT * FROM orders TABLESAMPLE SYSTEM(10);    -- ~10% of rows

-- BERNOULLI: row-level sampling (slower, truly random)
SELECT * FROM orders TABLESAMPLE BERNOULLI(5);  -- ~5% of rows

-- Repeatable sampling (same seed = same rows)
SELECT * FROM orders TABLESAMPLE SYSTEM(10) REPEATABLE(42);

-- Use case: quick statistics on large tables
SELECT AVG(total), STDDEV(total), COUNT(*)
FROM orders TABLESAMPLE BERNOULLI(1);  -- 1% sample for fast stats

-- ═══════════════════════════════════════════════════════════════
-- PART 4: GROUPING SETS, ROLLUP, CUBE
-- ═══════════════════════════════════════════════════════════════

-- GROUPING SETS: multiple GROUP BY in one query
SELECT
    COALESCE(c.name, 'ALL CATEGORIES') AS category,
    COALESCE(o.status, 'ALL STATUSES') AS status,
    COUNT(DISTINCT o.id) AS order_count,
    SUM(oi.quantity * oi.unit_price) AS revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.id
JOIN products p ON p.id = oi.product_id
LEFT JOIN categories c ON c.id = p.category_id
GROUP BY GROUPING SETS (
    (c.name, o.status),   -- by category AND status
    (c.name),             -- by category only
    (o.status),           -- by status only
    ()                    -- grand total
)
ORDER BY category NULLS LAST, status NULLS LAST;

-- ROLLUP: hierarchical subtotals (year → month → day)
SELECT
    DATE_PART('year',  created_at)::INT AS year,
    DATE_PART('month', created_at)::INT AS month,
    COUNT(*) AS orders,
    SUM(total) AS revenue
FROM orders
WHERE status != 'cancelled'
GROUP BY ROLLUP (
    DATE_PART('year',  created_at),
    DATE_PART('month', created_at)
)
ORDER BY year NULLS LAST, month NULLS LAST;

-- CUBE: all combinations of dimensions
SELECT
    COALESCE(c.name, 'ALL') AS category,
    COALESCE(o.status, 'ALL') AS status,
    SUM(o.total) AS revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.id
JOIN products p ON p.id = oi.product_id
LEFT JOIN categories c ON c.id = p.category_id
GROUP BY CUBE (c.name, o.status)
ORDER BY category NULLS LAST, status NULLS LAST;

-- GROUPING() function: detect which columns are aggregated
SELECT
    CASE WHEN GROUPING(c.name) = 1 THEN 'ALL' ELSE c.name END AS category,
    CASE WHEN GROUPING(o.status) = 1 THEN 'ALL' ELSE o.status END AS status,
    SUM(o.total) AS revenue,
    GROUPING(c.name, o.status) AS grouping_id
FROM orders o
JOIN order_items oi ON oi.order_id = o.id
JOIN products p ON p.id = oi.product_id
LEFT JOIN categories c ON c.id = p.category_id
GROUP BY CUBE (c.name, o.status);

-- ─── PITFALLS ────────────────────────────────────────────────
-- 1. Table inheritance does NOT support FK references to parent table
-- 2. COPY requires superuser or pg_read_server_files role for server-side files
-- 3. TABLESAMPLE SYSTEM can return 0 rows on small tables (block-level)
-- 4. ROLLUP/CUBE can produce many rows — use HAVING to filter
-- 5. GROUPING SETS with many dimensions = exponential row count with CUBE
