-- =============================================================
-- 01_CREATE_TABLES.SQL — DDL Basics: CREATE, ALTER, DROP
-- Scenario: E-Commerce Platform (users, products, orders)
-- =============================================================

-- ─── CREATE DATABASE ─────────────────────────────────────────
-- Run this separately in psql or pgAdmin before running the rest
-- CREATE DATABASE pg_playground;
-- \c pg_playground

-- ─── DATA TYPES OVERVIEW ─────────────────────────────────────
-- INTEGER, BIGINT, SMALLINT       → whole numbers
-- NUMERIC(p,s), DECIMAL           → exact decimals (money)
-- REAL, DOUBLE PRECISION          → floating point
-- VARCHAR(n), TEXT                → strings
-- CHAR(n)                         → fixed-length string
-- BOOLEAN                         → true/false
-- DATE, TIME, TIMESTAMP, TIMESTAMPTZ → date/time
-- UUID                            → universally unique id
-- JSONB                           → binary JSON (indexed)
-- BYTEA                           → binary data (CLOBs/BLOBs)
-- ARRAY                           → array of any type
-- SERIAL, BIGSERIAL               → auto-increment (legacy)
-- GENERATED ALWAYS AS IDENTITY    → modern auto-increment

-- ─── USERS TABLE ─────────────────────────────────────────────
CREATE TABLE users (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email       VARCHAR(255) NOT NULL UNIQUE,
    username    VARCHAR(100) NOT NULL UNIQUE,
    full_name   VARCHAR(255),
    phone       VARCHAR(20),
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    role        VARCHAR(50) NOT NULL DEFAULT 'customer'
                    CHECK (role IN ('customer', 'admin', 'vendor')),
    metadata    JSONB,                          -- flexible extra data
    avatar      BYTEA,                          -- BLOB: profile picture
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── CATEGORIES TABLE ────────────────────────────────────────
CREATE TABLE categories (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(100) NOT NULL UNIQUE,
    parent_id   INT REFERENCES categories(id) ON DELETE SET NULL, -- self-referencing (tree)
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── PRODUCTS TABLE ──────────────────────────────────────────
CREATE TABLE products (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku         VARCHAR(100) NOT NULL UNIQUE,
    name        VARCHAR(255) NOT NULL,
    description TEXT,                           -- large text (CLOB equivalent)
    price       NUMERIC(12, 2) NOT NULL CHECK (price >= 0),
    stock       INT NOT NULL DEFAULT 0 CHECK (stock >= 0),
    category_id INT REFERENCES categories(id) ON DELETE SET NULL,
    tags        TEXT[],                         -- array of tags
    attributes  JSONB,                          -- {"color":"red","size":"M"}
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── ORDERS TABLE ────────────────────────────────────────────
CREATE TABLE orders (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    status      VARCHAR(50) NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','confirmed','shipped','delivered','cancelled')),
    total       NUMERIC(12, 2) NOT NULL DEFAULT 0,
    notes       TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── ORDER ITEMS TABLE ───────────────────────────────────────
CREATE TABLE order_items (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id    BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id  BIGINT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    quantity    INT NOT NULL CHECK (quantity > 0),
    unit_price  NUMERIC(12, 2) NOT NULL,        -- snapshot price at time of order
    UNIQUE (order_id, product_id)               -- no duplicate product in same order
);

-- ─── ALTER TABLE EXAMPLES ────────────────────────────────────
-- Add a column
ALTER TABLE users ADD COLUMN loyalty_points INT NOT NULL DEFAULT 0;

-- Rename a column
ALTER TABLE users RENAME COLUMN full_name TO display_name;

-- Change column type
ALTER TABLE users ALTER COLUMN phone TYPE VARCHAR(30);

-- Add a NOT NULL constraint after the fact
ALTER TABLE products ALTER COLUMN name SET NOT NULL;

-- Add a CHECK constraint
ALTER TABLE products ADD CONSTRAINT chk_price_positive CHECK (price > 0);

-- Drop a constraint
ALTER TABLE products DROP CONSTRAINT chk_price_positive;

-- Add a default
ALTER TABLE orders ALTER COLUMN status SET DEFAULT 'pending';

-- Rename a table
-- ALTER TABLE order_items RENAME TO line_items;  -- commented out to keep name consistent

-- ─── INSERT SEED DATA ────────────────────────────────────────
INSERT INTO categories (name) VALUES ('Electronics'), ('Clothing'), ('Books');
INSERT INTO categories (name, parent_id) VALUES ('Smartphones', 1), ('Laptops', 1);

INSERT INTO users (email, username, display_name, role)
VALUES
    ('alice@example.com', 'alice', 'Alice Smith', 'customer'),
    ('bob@example.com',   'bob',   'Bob Jones',   'vendor'),
    ('admin@example.com', 'admin', 'Admin User',  'admin');

INSERT INTO products (sku, name, description, price, stock, category_id, tags, attributes)
VALUES
    ('SKU-001', 'iPhone 15', 'Latest Apple smartphone', 999.99, 50, 4,
     ARRAY['apple','smartphone','5g'], '{"color":"black","storage":"128GB"}'),
    ('SKU-002', 'MacBook Pro', 'M3 chip laptop', 2499.00, 20, 5,
     ARRAY['apple','laptop'], '{"ram":"16GB","storage":"512GB"}'),
    ('SKU-003', 'Clean Code', 'Book by Robert Martin', 39.99, 100, 3,
     ARRAY['programming','book'], NULL);

INSERT INTO orders (user_id, status, total)
VALUES (1, 'confirmed', 1039.98);

INSERT INTO order_items (order_id, product_id, quantity, unit_price)
VALUES (1, 1, 1, 999.99), (1, 3, 1, 39.99);

-- ─── SELECT BASICS ───────────────────────────────────────────
SELECT * FROM users;
SELECT id, email, role FROM users WHERE is_active = TRUE;
SELECT * FROM products ORDER BY price DESC LIMIT 5;
SELECT * FROM products WHERE tags @> ARRAY['apple'];   -- array contains
SELECT * FROM products WHERE attributes->>'color' = 'black'; -- JSONB field access

-- ─── UPDATE ──────────────────────────────────────────────────
UPDATE products SET stock = stock - 1 WHERE id = 1;
UPDATE users SET updated_at = NOW() WHERE id = 1;

-- ─── DELETE ──────────────────────────────────────────────────
-- DELETE FROM order_items WHERE order_id = 1;  -- cascades handled by FK

-- ─── DROP (careful!) ─────────────────────────────────────────
-- DROP TABLE order_items;
-- DROP TABLE orders;
-- DROP TABLE products;
-- DROP TABLE categories;
-- DROP TABLE users;
-- DROP DATABASE pg_playground;
