-- =============================================================
-- 16_ENUMS_RANGES_SEQUENCES.SQL
-- Covers: Custom ENUM types, Range types, Sequences, Tablespaces
-- Scenario: Booking system, financial ledger
-- =============================================================

-- ═══════════════════════════════════════════════════════════════
-- PART 1: CUSTOM ENUM TYPES
-- ═══════════════════════════════════════════════════════════════

-- Create enum type — stored as integer internally, displayed as label
CREATE TYPE order_status_enum AS ENUM (
    'pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled', 'refunded'
);

CREATE TYPE user_role_enum AS ENUM ('customer', 'vendor', 'admin', 'superadmin');

CREATE TYPE priority_enum AS ENUM ('low', 'medium', 'high', 'critical');

-- Use enum in a table
CREATE TABLE support_tickets (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     BIGINT NOT NULL,
    subject     VARCHAR(500) NOT NULL,
    priority    priority_enum NOT NULL DEFAULT 'medium',
    status      VARCHAR(50) NOT NULL DEFAULT 'open',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO support_tickets (user_id, subject, priority)
VALUES (1, 'Cannot login', 'high'),
       (2, 'Wrong invoice', 'critical'),
       (1, 'Feature request', 'low');

-- Enum ordering works naturally
SELECT * FROM support_tickets ORDER BY priority;  -- low < medium < high < critical

-- Add a new value to existing enum (append only, cannot reorder)
ALTER TYPE priority_enum ADD VALUE 'urgent' AFTER 'high';

-- List all enum values
SELECT enumlabel, enumsortorder
FROM pg_enum
JOIN pg_type ON pg_type.oid = pg_enum.enumtypid
WHERE pg_type.typname = 'priority_enum'
ORDER BY enumsortorder;

-- Cast string to enum
SELECT 'high'::priority_enum;

-- ═══════════════════════════════════════════════════════════════
-- PART 2: RANGE TYPES
-- ═══════════════════════════════════════════════════════════════

-- Built-in range types: int4range, int8range, numrange, tsrange, tstzrange, daterange

-- Hotel room availability
CREATE TABLE room_availability (
    id          SERIAL PRIMARY KEY,
    room_no     VARCHAR(20) NOT NULL,
    available   daterange NOT NULL,               -- e.g., [2025-01-01, 2025-01-10)
    EXCLUDE USING GIST (room_no WITH =, available WITH &&)  -- no overlapping bookings
);

CREATE EXTENSION IF NOT EXISTS btree_gist;

INSERT INTO room_availability (room_no, available)
VALUES ('101', '[2025-01-01, 2025-01-10)'),
       ('101', '[2025-01-15, 2025-01-20)'),
       ('102', '[2025-01-01, 2025-01-31)');

-- Range operators
SELECT room_no, available
FROM room_availability
WHERE available @> '2025-01-05'::date;          -- contains a specific date

SELECT room_no, available
FROM room_availability
WHERE available && '[2025-01-08, 2025-01-12)'::daterange;  -- overlaps range

-- Range functions
SELECT
    '[2025-01-01, 2025-01-10)'::daterange,
    LOWER('[2025-01-01, 2025-01-10)'::daterange) AS start_date,
    UPPER('[2025-01-01, 2025-01-10)'::daterange) AS end_date,
    UPPER('[2025-01-01, 2025-01-10)'::daterange)
        - LOWER('[2025-01-01, 2025-01-10)'::daterange) AS duration_days;

-- Numeric range for price bands
CREATE TABLE price_tiers (
    tier_name   VARCHAR(50) NOT NULL,
    price_range numrange NOT NULL,
    discount    NUMERIC(5,2) NOT NULL DEFAULT 0
);

INSERT INTO price_tiers VALUES
    ('budget',   '[0, 100)',      0),
    ('mid',      '[100, 500)',    5),
    ('premium',  '[500, 2000)',  10),
    ('luxury',   '[2000, )',     15);

-- Find tier for a given price
SELECT tier_name, discount
FROM price_tiers
WHERE price_range @> 750::NUMERIC;

-- ═══════════════════════════════════════════════════════════════
-- PART 3: SEQUENCES
-- ═══════════════════════════════════════════════════════════════

-- Create a custom sequence
CREATE SEQUENCE invoice_seq
    START WITH 1000
    INCREMENT BY 1
    MINVALUE 1000
    MAXVALUE 9999999
    CACHE 10           -- pre-allocate 10 values for performance
    NO CYCLE;          -- error when exhausted (vs CYCLE to wrap around)

-- Use sequence
SELECT NEXTVAL('invoice_seq');   -- get next value (irreversible)
SELECT CURRVAL('invoice_seq');   -- current value in this session
SELECT LASTVAL();                -- last value from any sequence this session
SELECT SETVAL('invoice_seq', 2000);  -- reset (careful in production!)

-- Use in a table
CREATE TABLE invoices (
    id          BIGINT DEFAULT NEXTVAL('invoice_seq') PRIMARY KEY,
    order_id    BIGINT NOT NULL,
    amount      NUMERIC(12,2) NOT NULL,
    issued_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO invoices (order_id, amount) VALUES (1, 999.99) RETURNING id;

-- Sequence info
SELECT * FROM pg_sequences WHERE sequencename = 'invoice_seq';

-- Gap-free sequence (for compliance — use with caution, serializes inserts)
-- Use a table-based counter instead:
CREATE TABLE counters (
    name    VARCHAR(100) PRIMARY KEY,
    value   BIGINT NOT NULL DEFAULT 0
);
INSERT INTO counters (name) VALUES ('invoice_no');

-- Atomic increment (gap-free)
UPDATE counters SET value = value + 1 WHERE name = 'invoice_no' RETURNING value;

-- ─── PITFALLS ────────────────────────────────────────────────
-- 1. Sequences can have gaps (rollbacks, cache, crashes) — never assume sequential
-- 2. SERIAL is shorthand for sequence + default — prefer GENERATED ALWAYS AS IDENTITY
-- 3. Range type EXCLUDE constraints require btree_gist extension
-- 4. Enum values cannot be removed or reordered after creation
-- 5. CACHE on sequences means gaps on server restart
