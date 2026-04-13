-- =============================================================
-- 19_FULL_TEXT_SEARCH.SQL — Deep dive into PostgreSQL FTS
-- tsvector, tsquery, ranking, highlighting, dictionaries,
-- custom configurations, phrase search
-- Scenario: Blog / Document search engine
-- =============================================================

-- ─── CORE CONCEPTS ───────────────────────────────────────────
-- tsvector: preprocessed document (stemmed, stop-words removed)
-- tsquery:  search query (AND, OR, NOT, phrase, prefix)
-- @@:       match operator

-- ─── TSVECTOR BASICS ─────────────────────────────────────────
SELECT TO_TSVECTOR('english', 'The quick brown fox jumps over the lazy dog');
-- 'brown':3 'dog':9 'fox':4 'jump':5 'lazi':8 'quick':2
-- Note: "the", "over" removed (stop words); "jumps"→"jump" (stemmed)

-- ─── TSQUERY BASICS ──────────────────────────────────────────
SELECT TO_TSQUERY('english', 'postgresql & performance');   -- AND
SELECT TO_TSQUERY('english', 'postgresql | mysql');         -- OR
SELECT TO_TSQUERY('english', 'postgresql & !oracle');       -- NOT
SELECT PLAINTO_TSQUERY('english', 'postgresql performance'); -- plain text → AND
SELECT PHRASETO_TSQUERY('english', 'full text search');     -- phrase (order matters)
SELECT WEBSEARCH_TO_TSQUERY('english', 'postgresql -oracle "full text"'); -- Google-style

-- ─── MATCH ───────────────────────────────────────────────────
SELECT TO_TSVECTOR('english', 'PostgreSQL full text search is powerful')
    @@ TO_TSQUERY('english', 'postgresql & search');  -- true

-- ─── BLOG POSTS TABLE WITH FTS ───────────────────────────────
CREATE TABLE blog_posts (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title       VARCHAR(500) NOT NULL,
    body        TEXT NOT NULL,
    author      VARCHAR(100),
    tags        TEXT[],
    published   BOOLEAN NOT NULL DEFAULT FALSE,
    -- Stored tsvector column (auto-updated by trigger)
    search_vec  TSVECTOR GENERATED ALWAYS AS (
        SETWEIGHT(TO_TSVECTOR('english', title), 'A') ||
        SETWEIGHT(TO_TSVECTOR('english', COALESCE(body, '')), 'B')
    ) STORED,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- GIN index on the stored tsvector
CREATE INDEX idx_blog_posts_fts ON blog_posts USING GIN (search_vec);

INSERT INTO blog_posts (title, body, author, tags, published) VALUES
    ('PostgreSQL Performance Tuning', 'Learn how to optimize queries with indexes and EXPLAIN ANALYZE', 'Alice', ARRAY['postgresql','performance'], true),
    ('Introduction to Full Text Search', 'Full text search in PostgreSQL uses tsvector and tsquery', 'Bob', ARRAY['postgresql','fts'], true),
    ('Redis vs PostgreSQL for Caching', 'Comparing caching strategies between Redis and PostgreSQL', 'Alice', ARRAY['postgresql','redis','caching'], true),
    ('Getting Started with pgvector', 'Vector similarity search using pgvector extension in PostgreSQL', 'Charlie', ARRAY['postgresql','ai','vectors'], true);

-- ─── BASIC SEARCH ────────────────────────────────────────────
SELECT id, title, author
FROM blog_posts
WHERE search_vec @@ TO_TSQUERY('english', 'postgresql & performance');

-- ─── RANKING ─────────────────────────────────────────────────
-- TS_RANK: frequency-based ranking
-- TS_RANK_CD: cover density (considers proximity of terms)
SELECT
    title,
    TS_RANK(search_vec, query)    AS rank,
    TS_RANK_CD(search_vec, query) AS rank_cd
FROM blog_posts,
     TO_TSQUERY('english', 'postgresql & search') AS query
WHERE search_vec @@ query
ORDER BY rank DESC;

-- ─── HIGHLIGHTING (TS_HEADLINE) ──────────────────────────────
SELECT
    title,
    TS_HEADLINE('english', body,
        TO_TSQUERY('english', 'postgresql & search'),
        'MaxWords=20, MinWords=5, StartSel=<b>, StopSel=</b>'
    ) AS highlighted_snippet
FROM blog_posts
WHERE search_vec @@ TO_TSQUERY('english', 'postgresql & search');

-- ─── PHRASE SEARCH ───────────────────────────────────────────
-- Find "full text" as a phrase (words must be adjacent)
SELECT title FROM blog_posts
WHERE search_vec @@ PHRASETO_TSQUERY('english', 'full text search');

-- ─── PREFIX SEARCH ───────────────────────────────────────────
-- Find words starting with "perform"
SELECT title FROM blog_posts
WHERE search_vec @@ TO_TSQUERY('english', 'perform:*');

-- ─── WEBSEARCH SYNTAX ────────────────────────────────────────
-- Natural Google-like syntax
SELECT title FROM blog_posts
WHERE search_vec @@ WEBSEARCH_TO_TSQUERY('english', 'postgresql -redis "full text"');

-- ─── WEIGHT BOOSTING ─────────────────────────────────────────
-- A=title matches rank higher than B=body matches
SELECT title,
       TS_RANK(search_vec, TO_TSQUERY('english', 'postgresql'),
               1 /* normalization: divide by doc length */) AS rank
FROM blog_posts
WHERE search_vec @@ TO_TSQUERY('english', 'postgresql')
ORDER BY rank DESC;

-- ─── MULTI-LANGUAGE SUPPORT ──────────────────────────────────
SELECT TO_TSVECTOR('spanish', 'El rápido zorro marrón salta sobre el perro perezoso');
SELECT TO_TSVECTOR('french',  'La recherche en texte intégral est puissante');

-- ─── CUSTOM TEXT SEARCH CONFIGURATION ───────────────────────
-- List available configurations
SELECT cfgname FROM pg_ts_config;

-- Create custom config (e.g., no stop words for code search)
CREATE TEXT SEARCH CONFIGURATION code_search (COPY = english);
ALTER TEXT SEARCH CONFIGURATION code_search
    ALTER MAPPING FOR asciiword WITH simple;  -- no stemming

-- ─── PITFALLS ────────────────────────────────────────────────
-- 1. tsvector does not preserve original words — use TS_HEADLINE for display
-- 2. LIKE '%word%' does NOT use FTS indexes — use @@ with tsvector
-- 3. Stored GENERATED tsvector is best for performance (no recompute on query)
-- 4. Different languages need different configurations — don't mix
-- 5. Very short words (< 3 chars) may be stop words — test your config
-- 6. TS_RANK scores are relative — only useful for ordering, not absolute thresholds
