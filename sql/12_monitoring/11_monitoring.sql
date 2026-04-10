-- =============================================================
-- 11_MONITORING.SQL — EXPLAIN, ANALYZE, pg_stat_*, VACUUM,
--                     Query Tuning, Connection Pooling Hints
-- =============================================================

-- ─── EXPLAIN — show query plan (no execution) ────────────────
EXPLAIN SELECT * FROM orders WHERE user_id = 1;

-- ─── EXPLAIN ANALYZE — execute and show actual stats ─────────
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT o.id, u.username, o.total
FROM orders o
JOIN users u ON u.id = o.user_id
WHERE o.status = 'confirmed'
ORDER BY o.created_at DESC
LIMIT 20;

-- Reading EXPLAIN output:
-- Seq Scan     → full table scan (bad on large tables without index)
-- Index Scan   → uses index, fetches heap rows
-- Index Only Scan → all data from index (fastest)
-- Bitmap Scan  → combines multiple indexes
-- Hash Join    → builds hash table (good for large unsorted sets)
-- Nested Loop  → good for small inner sets
-- Merge Join   → good for pre-sorted sets
-- cost=X..Y    → X=startup cost, Y=total cost (arbitrary units)
-- rows=N       → estimated rows
-- actual rows=N → real rows (compare with estimate for bad stats)

-- ─── TABLE STATISTICS ────────────────────────────────────────
-- Table sizes
SELECT
    relname AS table_name,
    pg_size_pretty(pg_total_relation_size(oid)) AS total_size,
    pg_size_pretty(pg_relation_size(oid))       AS table_size,
    pg_size_pretty(pg_indexes_size(oid))        AS indexes_size
FROM pg_class
WHERE relkind = 'r' AND relnamespace = 'public'::regnamespace
ORDER BY pg_total_relation_size(oid) DESC;

-- Row counts (fast estimate)
SELECT relname, reltuples::BIGINT AS estimated_rows
FROM pg_class
WHERE relkind = 'r' AND relnamespace = 'public'::regnamespace;

-- ─── pg_stat_user_tables ─────────────────────────────────────
SELECT
    relname,
    seq_scan,          -- sequential scans (high = missing index)
    idx_scan,          -- index scans
    n_live_tup,        -- live rows
    n_dead_tup,        -- dead rows (need VACUUM)
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
ORDER BY seq_scan DESC;

-- ─── pg_stat_user_indexes ────────────────────────────────────
SELECT
    relname AS table,
    indexrelname AS index,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;

-- ─── SLOW QUERIES ────────────────────────────────────────────
-- Enable pg_stat_statements in postgresql.conf:
-- shared_preload_libraries = 'pg_stat_statements'
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

SELECT
    query,
    calls,
    ROUND(total_exec_time::NUMERIC, 2) AS total_ms,
    ROUND(mean_exec_time::NUMERIC, 2)  AS avg_ms,
    ROUND(stddev_exec_time::NUMERIC, 2) AS stddev_ms,
    rows
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 20;

-- Reset stats
SELECT pg_stat_reset();
SELECT pg_stat_statements_reset();

-- ─── ACTIVE CONNECTIONS & QUERIES ────────────────────────────
SELECT
    pid,
    usename,
    application_name,
    client_addr,
    state,
    wait_event_type,
    wait_event,
    now() - query_start AS query_duration,
    LEFT(query, 100) AS query_snippet
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY query_duration DESC NULLS LAST;

-- Kill a long-running query (graceful)
-- SELECT pg_cancel_backend(pid);

-- Kill a connection (forceful)
-- SELECT pg_terminate_backend(pid);

-- ─── LOCKS ───────────────────────────────────────────────────
-- Blocked queries
SELECT
    blocked.pid,
    blocked.query AS blocked_query,
    blocking.pid AS blocking_pid,
    blocking.query AS blocking_query
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking
    ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE blocked.cardinality(pg_blocking_pids(blocked.pid)) > 0;

-- All locks
SELECT pid, locktype, relation::regclass, mode, granted
FROM pg_locks
ORDER BY granted, pid;

-- ─── VACUUM & ANALYZE ────────────────────────────────────────
-- VACUUM: reclaims dead tuple space (doesn't shrink file)
VACUUM orders;

-- VACUUM ANALYZE: reclaim + update statistics
VACUUM ANALYZE orders;

-- VACUUM FULL: rewrites table, reclaims disk space (locks table!)
-- VACUUM FULL orders;  -- use during maintenance window only

-- ANALYZE: update planner statistics only
ANALYZE products;

-- Autovacuum settings (in postgresql.conf):
-- autovacuum = on
-- autovacuum_vacuum_threshold = 50
-- autovacuum_analyze_threshold = 50
-- autovacuum_vacuum_scale_factor = 0.2  (20% of table)

-- ─── BLOAT CHECK ─────────────────────────────────────────────
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    n_dead_tup,
    n_live_tup,
    ROUND(n_dead_tup::NUMERIC / NULLIF(n_live_tup + n_dead_tup, 0) * 100, 2) AS dead_pct
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY dead_pct DESC;

-- ─── CACHE HIT RATIO ─────────────────────────────────────────
-- Should be > 99% for OLTP workloads
SELECT
    SUM(heap_blks_hit) / NULLIF(SUM(heap_blks_hit) + SUM(heap_blks_read), 0) AS table_cache_hit,
    SUM(idx_blks_hit)  / NULLIF(SUM(idx_blks_hit)  + SUM(idx_blks_read),  0) AS index_cache_hit
FROM pg_statio_user_tables;

-- ─── CHECKPOINT & WAL ────────────────────────────────────────
SELECT * FROM pg_stat_bgwriter;

-- ─── REPLICATION STATUS ──────────────────────────────────────
SELECT * FROM pg_stat_replication;  -- on primary
SELECT * FROM pg_stat_wal_receiver; -- on replica

-- ─── OPTIMIZATION TIPS ───────────────────────────────────────
-- 1. shared_buffers = 25% of RAM
-- 2. effective_cache_size = 75% of RAM
-- 3. work_mem = RAM / (max_connections * 2)  — per sort/hash operation
-- 4. maintenance_work_mem = 256MB–1GB for VACUUM/index builds
-- 5. random_page_cost = 1.1 for SSD (default 4.0 is for HDD)
-- 6. effective_io_concurrency = 200 for SSD
-- 7. max_parallel_workers_per_gather = CPU cores / 2
-- 8. wal_buffers = 16MB
-- 9. checkpoint_completion_target = 0.9
-- 10. log_min_duration_statement = 1000  (log queries > 1s)
