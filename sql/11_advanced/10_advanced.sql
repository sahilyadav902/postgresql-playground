-- =============================================================
-- 10_ADVANCED.SQL — CTEs, Window Functions, Stored Procedures,
--                   Functions, Arrays, JSONB, Date/Time, COPY
-- Scenario: Analytics, Reporting, Data Processing
-- =============================================================

-- ─── CTEs (Common Table Expressions) ─────────────────────────
-- Named subqueries — improve readability, reusable within query

-- Simple CTE
WITH top_products AS (
    SELECT product_id, SUM(quantity) AS total_sold
    FROM order_items
    GROUP BY product_id
    ORDER BY total_sold DESC
    LIMIT 5
)
SELECT p.name, p.sku, tp.total_sold
FROM top_products tp
JOIN products p ON p.id = tp.product_id;

-- Multiple CTEs
WITH
revenue AS (
    SELECT user_id, SUM(total) AS lifetime_value
    FROM orders WHERE status != 'cancelled'
    GROUP BY user_id
),
ranked AS (
    SELECT user_id, lifetime_value,
           RANK() OVER (ORDER BY lifetime_value DESC) AS rank
    FROM revenue
)
SELECT u.username, r.lifetime_value, r.rank
FROM ranked r
JOIN users u ON u.id = r.user_id
WHERE r.rank <= 10;

-- ─── RECURSIVE CTE ───────────────────────────────────────────
-- Traverse hierarchical data (org chart, category tree, BOM)
WITH RECURSIVE org_chart AS (
    -- Base: CEO (no manager)
    SELECT id, name, manager_id, name::TEXT AS path, 0 AS level
    FROM employees
    WHERE manager_id IS NULL

    UNION ALL

    -- Recursive: employees with managers
    SELECT e.id, e.name, e.manager_id,
           (oc.path || ' → ' || e.name)::TEXT,
           oc.level + 1
    FROM employees e
    JOIN org_chart oc ON oc.id = e.manager_id
)
SELECT REPEAT('  ', level) || name AS hierarchy, path
FROM org_chart
ORDER BY path;

-- ─── WINDOW FUNCTIONS ────────────────────────────────────────
-- Perform calculations across related rows without collapsing them

-- ROW_NUMBER, RANK, DENSE_RANK
SELECT
    username,
    total_spent,
    ROW_NUMBER() OVER (ORDER BY total_spent DESC)   AS row_num,
    RANK()       OVER (ORDER BY total_spent DESC)   AS rank,       -- gaps on ties
    DENSE_RANK() OVER (ORDER BY total_spent DESC)   AS dense_rank  -- no gaps
FROM (
    SELECT u.username, COALESCE(SUM(o.total), 0) AS total_spent
    FROM users u LEFT JOIN orders o ON o.user_id = u.id
    GROUP BY u.id, u.username
) sub;

-- PARTITION BY: rank within groups
SELECT
    p.name,
    c.name AS category,
    p.price,
    RANK() OVER (PARTITION BY p.category_id ORDER BY p.price DESC) AS price_rank_in_category
FROM products p
JOIN categories c ON c.id = p.category_id;

-- LAG / LEAD: access previous/next row
SELECT
    sale_date,
    daily_revenue,
    LAG(daily_revenue)  OVER (ORDER BY sale_date) AS prev_day_revenue,
    LEAD(daily_revenue) OVER (ORDER BY sale_date) AS next_day_revenue,
    daily_revenue - LAG(daily_revenue) OVER (ORDER BY sale_date) AS day_over_day_change
FROM mv_daily_sales
ORDER BY sale_date;

-- Running total (cumulative sum)
SELECT
    sale_date,
    daily_revenue,
    SUM(daily_revenue) OVER (ORDER BY sale_date
                              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                             ) AS running_total
FROM mv_daily_sales;

-- Moving average (7-day)
SELECT
    sale_date,
    daily_revenue,
    AVG(daily_revenue) OVER (ORDER BY sale_date
                              ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
                             ) AS moving_avg_7d
FROM mv_daily_sales;

-- NTILE: divide into buckets (quartiles)
SELECT username, total_spent,
       NTILE(4) OVER (ORDER BY total_spent) AS quartile
FROM (SELECT u.username, COALESCE(SUM(o.total),0) AS total_spent
      FROM users u LEFT JOIN orders o ON o.user_id = u.id GROUP BY u.id, u.username) s;

-- FIRST_VALUE / LAST_VALUE
SELECT name, price, category_id,
       FIRST_VALUE(name) OVER (PARTITION BY category_id ORDER BY price DESC) AS most_expensive
FROM products;

-- ─── STORED FUNCTIONS ────────────────────────────────────────
-- Returns a value
CREATE OR REPLACE FUNCTION get_user_order_count(p_user_id BIGINT)
RETURNS INT AS $$
    SELECT COUNT(*)::INT FROM orders WHERE user_id = p_user_id;
$$ LANGUAGE sql STABLE;  -- STABLE: same inputs = same output within transaction

SELECT username, get_user_order_count(id) AS orders
FROM users;

-- PL/pgSQL function with logic
CREATE OR REPLACE FUNCTION transfer_funds(
    p_from BIGINT, p_to BIGINT, p_amount NUMERIC
) RETURNS TEXT AS $$
DECLARE
    v_balance NUMERIC;
BEGIN
    SELECT balance INTO v_balance FROM bank_accounts WHERE id = p_from FOR UPDATE;

    IF v_balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient funds: balance=%, requested=%', v_balance, p_amount;
    END IF;

    UPDATE bank_accounts SET balance = balance - p_amount WHERE id = p_from;
    UPDATE bank_accounts SET balance = balance + p_amount WHERE id = p_to;

    INSERT INTO transactions_log (from_acct, to_acct, amount, type)
    VALUES (p_from, p_to, p_amount, 'transfer');

    RETURN FORMAT('Transferred %.2f from account %s to %s', p_amount, p_from, p_to);
END;
$$ LANGUAGE plpgsql;

SELECT transfer_funds(1, 2, 100.00);

-- ─── STORED PROCEDURES (PostgreSQL 11+) ──────────────────────
-- Unlike functions, procedures can COMMIT/ROLLBACK inside
CREATE OR REPLACE PROCEDURE process_daily_settlements()
LANGUAGE plpgsql AS $$
DECLARE
    v_order RECORD;
BEGIN
    FOR v_order IN
        SELECT id FROM orders WHERE status = 'confirmed'
    LOOP
        UPDATE orders SET status = 'shipped' WHERE id = v_order.id;
        COMMIT;  -- commit each update individually (procedures can do this)
    END LOOP;
END;
$$;

CALL process_daily_settlements();

-- ─── JSONB OPERATIONS ────────────────────────────────────────
-- Access
SELECT attributes->'color' AS color_json,          -- returns JSON
       attributes->>'color' AS color_text,          -- returns text
       attributes#>>'{storage}' AS storage          -- nested path
FROM products WHERE attributes IS NOT NULL;

-- Update JSONB field
UPDATE products
SET attributes = attributes || '{"warranty": "1 year"}'::JSONB
WHERE id = 1;

-- Remove a key
UPDATE products
SET attributes = attributes - 'warranty'
WHERE id = 1;

-- JSONB aggregation
SELECT JSONB_AGG(JSONB_BUILD_OBJECT('id', id, 'name', name)) AS products_json
FROM products WHERE is_active = TRUE;

-- ─── ARRAY OPERATIONS ────────────────────────────────────────
SELECT tags,
       tags[1]                  AS first_tag,
       ARRAY_LENGTH(tags, 1)    AS tag_count,
       'apple' = ANY(tags)      AS has_apple,
       tags @> ARRAY['apple']   AS contains_apple,
       tags || ARRAY['new-tag'] AS tags_with_new
FROM products WHERE tags IS NOT NULL;

-- Unnest array into rows
SELECT id, name, UNNEST(tags) AS tag FROM products WHERE tags IS NOT NULL;

-- ─── DATE & TIME ─────────────────────────────────────────────
SELECT
    NOW(),                                          -- current timestamp with TZ
    CURRENT_DATE,                                   -- today's date
    CURRENT_TIME,                                   -- current time with TZ
    NOW() AT TIME ZONE 'America/New_York',          -- convert TZ
    DATE_TRUNC('month', NOW()),                     -- first of current month
    DATE_PART('year', NOW()),                       -- extract year
    EXTRACT(DOW FROM NOW()),                        -- day of week (0=Sun)
    NOW() + INTERVAL '7 days',                     -- add 7 days
    AGE('2000-01-01'::DATE),                        -- interval since date
    TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS'),        -- format as string
    TO_TIMESTAMP('2025-01-15', 'YYYY-MM-DD');       -- parse string to timestamp

-- Date ranges
SELECT * FROM orders
WHERE created_at BETWEEN '2025-01-01' AND '2025-12-31';

-- ─── COPY (bulk import/export) ────────────────────────────────
-- Export to CSV
-- COPY products TO '/tmp/products.csv' WITH (FORMAT CSV, HEADER TRUE);

-- Import from CSV
-- COPY products (sku, name, price, stock) FROM '/tmp/products.csv'
-- WITH (FORMAT CSV, HEADER TRUE);

-- From stdin (useful in scripts)
-- COPY products FROM STDIN WITH (FORMAT CSV);

-- ─── GENERATE_SERIES (test data generation) ──────────────────
-- Generate 1000 test orders
INSERT INTO orders (user_id, status, total)
SELECT
    (RANDOM() * 2 + 1)::INT,
    (ARRAY['pending','confirmed','shipped','delivered'])[FLOOR(RANDOM()*4+1)::INT],
    ROUND((RANDOM() * 500 + 10)::NUMERIC, 2)
FROM GENERATE_SERIES(1, 1000);
