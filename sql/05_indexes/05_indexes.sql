-- =============================================================
-- 05_INDEXES.SQL — B-Tree, Hash, GIN, GiST, BRIN, Partial,
--                  Composite, Covering, Expression Indexes
-- Scenario: Social Media Platform (posts, likes, search)
-- =============================================================

CREATE TABLE posts (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     BIGINT NOT NULL,
    title       VARCHAR(500) NOT NULL,
    body        TEXT NOT NULL,
    tags        TEXT[],
    metadata    JSONB,
    view_count  INT NOT NULL DEFAULT 0,
    is_deleted  BOOLEAN NOT NULL DEFAULT FALSE,
    published_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE post_likes (
    post_id     BIGINT NOT NULL,
    user_id     BIGINT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (post_id, user_id)
);

-- ─── B-TREE INDEX (default) ───────────────────────────────────
-- Best for: =, <, >, BETWEEN, ORDER BY, range queries
CREATE INDEX idx_posts_user_id ON posts (user_id);
CREATE INDEX idx_posts_published_at ON posts (published_at DESC);

-- ─── COMPOSITE INDEX ─────────────────────────────────────────
-- Column order matters: queries must use leftmost prefix
-- Good for: WHERE user_id = ? AND published_at > ?
CREATE INDEX idx_posts_user_published ON posts (user_id, published_at DESC);

-- ─── PARTIAL INDEX ───────────────────────────────────────────
-- Index only a subset of rows — smaller, faster
-- Only index non-deleted, published posts (the hot path)
CREATE INDEX idx_posts_active ON posts (published_at DESC)
WHERE is_deleted = FALSE AND published_at IS NOT NULL;

-- ─── COVERING INDEX (INCLUDE) ────────────────────────────────
-- Include extra columns so query is satisfied from index alone (index-only scan)
CREATE INDEX idx_posts_user_covering ON posts (user_id)
INCLUDE (title, published_at, view_count);

-- ─── EXPRESSION / FUNCTIONAL INDEX ──────────────────────────
-- Index on a computed expression — query must use same expression
CREATE INDEX idx_posts_title_lower ON posts (LOWER(title));
-- Query must use: WHERE LOWER(title) = 'hello world'

-- ─── HASH INDEX ──────────────────────────────────────────────
-- Best for: equality only (=), slightly faster than B-tree for =
-- NOT useful for range queries or ORDER BY
CREATE INDEX idx_posts_user_hash ON posts USING HASH (user_id);

-- ─── GIN INDEX (Generalized Inverted Index) ──────────────────
-- Best for: arrays, JSONB, full-text search
CREATE INDEX idx_posts_tags_gin ON posts USING GIN (tags);
CREATE INDEX idx_posts_metadata_gin ON posts USING GIN (metadata);

-- Full-text search index
CREATE INDEX idx_posts_fts ON posts USING GIN (
    TO_TSVECTOR('english', title || ' ' || body)
);

-- ─── GiST INDEX ──────────────────────────────────────────────
-- Best for: geometric types, ranges, full-text (alternative to GIN)
-- Used with EXCLUDE constraints (see 02_constraints.sql)
-- CREATE INDEX idx_bookings_range ON room_bookings USING GIST (during);

-- ─── BRIN INDEX (Block Range INdex) ──────────────────────────
-- Best for: very large tables with naturally ordered data (timestamps, IDs)
-- Tiny size, fast to build, less precise (scans block ranges)
CREATE INDEX idx_posts_created_brin ON posts USING BRIN (created_at);

-- ─── UNIQUE INDEX ────────────────────────────────────────────
-- Enforces uniqueness (same as UNIQUE constraint but more flexible)
CREATE UNIQUE INDEX idx_posts_unique_title_user ON posts (user_id, LOWER(title))
WHERE is_deleted = FALSE;

-- ─── CONCURRENT INDEX BUILD ──────────────────────────────────
-- Build index without locking writes (takes longer but safe for production)
CREATE INDEX CONCURRENTLY idx_posts_view_count ON posts (view_count DESC);

-- ─── QUERY EXAMPLES USING INDEXES ────────────────────────────
-- Uses idx_posts_user_published
EXPLAIN ANALYZE
SELECT id, title, published_at FROM posts
WHERE user_id = 1 AND published_at > NOW() - INTERVAL '30 days'
ORDER BY published_at DESC;

-- Uses idx_posts_tags_gin (array containment)
EXPLAIN ANALYZE
SELECT id, title FROM posts WHERE tags @> ARRAY['postgresql'];

-- Uses idx_posts_fts (full-text search)
EXPLAIN ANALYZE
SELECT id, title,
       TS_RANK(TO_TSVECTOR('english', title || ' ' || body),
               TO_TSQUERY('english', 'postgresql & performance')) AS rank
FROM posts
WHERE TO_TSVECTOR('english', title || ' ' || body)
      @@ TO_TSQUERY('english', 'postgresql & performance')
ORDER BY rank DESC;

-- Uses idx_posts_metadata_gin (JSONB)
EXPLAIN ANALYZE
SELECT * FROM posts WHERE metadata @> '{"featured": true}';

-- ─── INDEX MAINTENANCE ───────────────────────────────────────
-- Rebuild bloated index
REINDEX INDEX idx_posts_user_id;
REINDEX TABLE posts;  -- rebuilds all indexes on table

-- View index usage stats
SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
WHERE tablename = 'posts'
ORDER BY idx_scan DESC;

-- Find unused indexes (candidates for removal)
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE idx_scan = 0 AND schemaname = 'public';

-- Index sizes
SELECT indexname, pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE tablename = 'posts';

-- ─── PITFALLS ────────────────────────────────────────────────
-- 1. Too many indexes = slow INSERTs/UPDATEs (each index must be updated)
-- 2. Index on low-cardinality column (e.g., boolean) = often ignored by planner
-- 3. Composite index column order matters — (a,b) != (b,a) for queries on b alone
-- 4. LIKE 'foo%' uses B-tree, but LIKE '%foo' does NOT
-- 5. Function calls in WHERE bypass indexes unless expression index exists
-- 6. VACUUM regularly to prevent index bloat
