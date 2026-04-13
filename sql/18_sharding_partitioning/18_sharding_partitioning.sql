-- =============================================================
-- 12_SHARDING.SQL — Partitioning (PostgreSQL's native sharding),
--                   Table Inheritance, Foreign Data Wrappers
-- Scenario: IoT Time-Series Data (millions of sensor readings)
-- =============================================================

-- ─── TABLE PARTITIONING ──────────────────────────────────────
-- PostgreSQL supports declarative partitioning (v10+)
-- Types: RANGE, LIST, HASH

-- ─── RANGE PARTITIONING (by date) ────────────────────────────
-- Use case: time-series data, logs, events — prune old partitions easily
CREATE TABLE sensor_readings (
    id          BIGINT GENERATED ALWAYS AS IDENTITY,
    sensor_id   INT NOT NULL,
    temperature NUMERIC(5,2),
    humidity    NUMERIC(5,2),
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (recorded_at);

-- Create monthly partitions
CREATE TABLE sensor_readings_2025_01
    PARTITION OF sensor_readings
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

CREATE TABLE sensor_readings_2025_02
    PARTITION OF sensor_readings
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');

CREATE TABLE sensor_readings_2025_03
    PARTITION OF sensor_readings
    FOR VALUES FROM ('2025-03-01') TO ('2025-04-01');

-- Default partition catches anything not matched
CREATE TABLE sensor_readings_default
    PARTITION OF sensor_readings DEFAULT;

-- Indexes on partitioned table (applied to all partitions)
CREATE INDEX idx_sensor_readings_sensor_id ON sensor_readings (sensor_id);
CREATE INDEX idx_sensor_readings_recorded_at ON sensor_readings (recorded_at DESC);

-- Insert data — PostgreSQL routes to correct partition automatically
INSERT INTO sensor_readings (sensor_id, temperature, humidity, recorded_at)
VALUES
    (1, 22.5, 65.0, '2025-01-15 10:00:00+00'),
    (2, 18.3, 70.2, '2025-02-20 14:30:00+00'),
    (3, 25.1, 55.8, '2025-03-05 09:15:00+00');

-- Query uses partition pruning (only scans relevant partitions)
EXPLAIN SELECT * FROM sensor_readings
WHERE recorded_at BETWEEN '2025-01-01' AND '2025-01-31';

-- ─── LIST PARTITIONING (by category/region) ──────────────────
CREATE TABLE orders_partitioned (
    id          BIGINT GENERATED ALWAYS AS IDENTITY,
    region      VARCHAR(20) NOT NULL,
    user_id     BIGINT NOT NULL,
    total       NUMERIC(12,2),
    created_at  TIMESTAMPTZ DEFAULT NOW()
) PARTITION BY LIST (region);

CREATE TABLE orders_us   PARTITION OF orders_partitioned FOR VALUES IN ('US', 'CA');
CREATE TABLE orders_eu   PARTITION OF orders_partitioned FOR VALUES IN ('UK', 'DE', 'FR');
CREATE TABLE orders_apac PARTITION OF orders_partitioned FOR VALUES IN ('JP', 'AU', 'SG');
CREATE TABLE orders_other PARTITION OF orders_partitioned DEFAULT;

-- ─── HASH PARTITIONING (even distribution) ───────────────────
-- Use case: distribute load evenly when no natural range/list key
CREATE TABLE user_events (
    id          BIGINT GENERATED ALWAYS AS IDENTITY,
    user_id     BIGINT NOT NULL,
    event_type  VARCHAR(50),
    payload     JSONB,
    created_at  TIMESTAMPTZ DEFAULT NOW()
) PARTITION BY HASH (user_id);

-- 4 partitions — user_id % 4 determines partition
CREATE TABLE user_events_p0 PARTITION OF user_events FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE user_events_p1 PARTITION OF user_events FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE user_events_p2 PARTITION OF user_events FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE user_events_p3 PARTITION OF user_events FOR VALUES WITH (MODULUS 4, REMAINDER 3);

-- ─── SUB-PARTITIONING ────────────────────────────────────────
-- Partition by year, then by region within each year
CREATE TABLE sales (
    id      BIGINT GENERATED ALWAYS AS IDENTITY,
    region  VARCHAR(20) NOT NULL,
    amount  NUMERIC(12,2),
    sale_date DATE NOT NULL
) PARTITION BY RANGE (sale_date);

CREATE TABLE sales_2025 PARTITION OF sales
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01')
    PARTITION BY LIST (region);

CREATE TABLE sales_2025_us PARTITION OF sales_2025 FOR VALUES IN ('US');
CREATE TABLE sales_2025_eu PARTITION OF sales_2025 FOR VALUES IN ('EU');

-- ─── PARTITION MANAGEMENT ────────────────────────────────────
-- Detach old partition (fast, no data movement)
ALTER TABLE sensor_readings DETACH PARTITION sensor_readings_2025_01;

-- Attach existing table as partition
-- ALTER TABLE sensor_readings ATTACH PARTITION sensor_readings_2025_01
--     FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

-- Drop old partition (instant, no VACUUM needed)
-- DROP TABLE sensor_readings_2025_01;

-- ─── VIEW PARTITIONS ─────────────────────────────────────────
SELECT
    parent.relname AS parent_table,
    child.relname  AS partition_name,
    pg_size_pretty(pg_relation_size(child.oid)) AS size
FROM pg_inherits
JOIN pg_class parent ON parent.oid = pg_inherits.inhparent
JOIN pg_class child  ON child.oid  = pg_inherits.inhrelid
WHERE parent.relname = 'sensor_readings';

-- ─── FOREIGN DATA WRAPPER (FDW) ──────────────────────────────
-- Connect to remote PostgreSQL as if it's a local table
-- Use case: federated queries across multiple databases/servers

CREATE EXTENSION IF NOT EXISTS postgres_fdw;

-- Create foreign server
-- CREATE SERVER remote_db
--     FOREIGN DATA WRAPPER postgres_fdw
--     OPTIONS (host 'remote-host', port '5432', dbname 'remote_db');

-- Map local user to remote user
-- CREATE USER MAPPING FOR current_user
--     SERVER remote_db
--     OPTIONS (user 'remote_user', password 'remote_pass');

-- Import remote schema
-- IMPORT FOREIGN SCHEMA public
--     FROM SERVER remote_db INTO local_schema;

-- Or create individual foreign table
-- CREATE FOREIGN TABLE remote_orders (
--     id BIGINT, user_id BIGINT, total NUMERIC
-- ) SERVER remote_db OPTIONS (schema_name 'public', table_name 'orders');

-- ─── PITFALLS ────────────────────────────────────────────────
-- 1. Partition key cannot be updated (must DELETE + INSERT)
-- 2. Unique constraints must include partition key
-- 3. Foreign keys TO partitioned tables not supported (only FROM)
-- 4. Too many partitions (>1000) can slow planning
-- 5. Partition pruning only works when WHERE clause uses partition key
-- 6. HASH partitioning: adding partitions requires full data redistribution
