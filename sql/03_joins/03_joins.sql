-- =============================================================
-- 03_JOINS.SQL — INNER, LEFT, RIGHT, FULL, CROSS, SELF, LATERAL
-- Scenario: E-Commerce (reusing tables from 01_basics)
-- =============================================================

-- ─── INNER JOIN — only matching rows ─────────────────────────
-- Get all orders with user info (only orders that have a user)
SELECT o.id AS order_id, u.email, u.username, o.status, o.total
FROM orders o
INNER JOIN users u ON u.id = o.user_id;

-- ─── LEFT JOIN — all left rows, NULLs for non-matching right ─
-- All users, even those with no orders
SELECT u.username, u.email, COUNT(o.id) AS order_count
FROM users u
LEFT JOIN orders o ON o.user_id = u.id
GROUP BY u.id, u.username, u.email;

-- ─── RIGHT JOIN — all right rows, NULLs for non-matching left
-- All orders, even if user was deleted (shouldn't happen with FK, but illustrative)
SELECT u.username, o.id AS order_id, o.total
FROM users u
RIGHT JOIN orders o ON o.user_id = u.id;

-- ─── FULL OUTER JOIN — all rows from both sides ───────────────
SELECT u.username, o.id AS order_id
FROM users u
FULL OUTER JOIN orders o ON o.user_id = u.id;

-- ─── CROSS JOIN — cartesian product ──────────────────────────
-- Every user paired with every category (e.g., for recommendation matrix)
SELECT u.username, c.name AS category
FROM users u
CROSS JOIN categories c;

-- ─── SELF JOIN — join table to itself ────────────────────────
-- Find categories and their parent category name
SELECT child.name AS subcategory, parent.name AS parent_category
FROM categories child
LEFT JOIN categories parent ON parent.id = child.parent_id;

-- ─── MULTI-TABLE JOIN ────────────────────────────────────────
-- Full order details: user → order → order_items → product
SELECT
    u.username,
    o.id        AS order_id,
    o.status,
    p.name      AS product_name,
    oi.quantity,
    oi.unit_price,
    (oi.quantity * oi.unit_price) AS line_total
FROM orders o
JOIN users u        ON u.id = o.user_id
JOIN order_items oi ON oi.order_id = o.id
JOIN products p     ON p.id = oi.product_id
ORDER BY o.id, p.name;

-- ─── LATERAL JOIN — correlated subquery as join ───────────────
-- For each user, get their most recent order (lateral allows referencing outer row)
SELECT u.username, latest.id AS latest_order_id, latest.created_at
FROM users u
LEFT JOIN LATERAL (
    SELECT id, created_at
    FROM orders
    WHERE user_id = u.id
    ORDER BY created_at DESC
    LIMIT 1
) latest ON TRUE;

-- ─── ANTI-JOIN — rows in A with no match in B ────────────────
-- Users who have NEVER placed an order
SELECT u.username, u.email
FROM users u
WHERE NOT EXISTS (
    SELECT 1 FROM orders o WHERE o.user_id = u.id
);
-- Alternative using LEFT JOIN:
SELECT u.username
FROM users u
LEFT JOIN orders o ON o.user_id = u.id
WHERE o.id IS NULL;

-- ─── SEMI-JOIN — rows in A that have at least one match in B ─
-- Users who HAVE placed at least one order
SELECT u.username
FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- ─── JOIN with AGGREGATION ───────────────────────────────────
-- Revenue per category
SELECT
    c.name AS category,
    COUNT(DISTINCT o.id) AS total_orders,
    SUM(oi.quantity * oi.unit_price) AS revenue
FROM categories c
LEFT JOIN products p    ON p.category_id = c.id
LEFT JOIN order_items oi ON oi.product_id = p.id
LEFT JOIN orders o      ON o.id = oi.order_id AND o.status != 'cancelled'
GROUP BY c.id, c.name
ORDER BY revenue DESC NULLS LAST;

-- ─── PITFALLS ────────────────────────────────────────────────
-- 1. CROSS JOIN on large tables = huge result set (N*M rows)
-- 2. LEFT JOIN + WHERE on right table = accidentally becomes INNER JOIN
--    WRONG:  FROM users u LEFT JOIN orders o ON ... WHERE o.status = 'pending'
--    RIGHT:  FROM users u LEFT JOIN orders o ON ... AND o.status = 'pending'
-- 3. Joining on non-indexed columns = slow full table scans
-- 4. Forgetting GROUP BY columns when using aggregates
