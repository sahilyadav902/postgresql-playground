-- =============================================================
-- 13_PGVECTOR.SQL — Vector Similarity Search with pgvector
-- Scenario: AI-Powered Product Recommendations & Semantic Search
-- =============================================================

-- ─── INSTALL EXTENSION ───────────────────────────────────────
-- First install pgvector: https://github.com/pgvector/pgvector
-- On Windows with pgAdmin: download pgvector and copy to PostgreSQL lib/share dirs
-- Or via Docker: pgvector/pgvector:pg16
CREATE EXTENSION IF NOT EXISTS vector;

-- ─── VECTOR DATA TYPE ────────────────────────────────────────
-- vector(N) stores N-dimensional float array
-- Common dimensions: 384 (MiniLM), 768 (BERT), 1536 (OpenAI ada-002), 3072 (text-embedding-3-large)

-- ─── PRODUCT EMBEDDINGS TABLE ────────────────────────────────
CREATE TABLE product_embeddings (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id  BIGINT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    embedding   vector(1536) NOT NULL,              -- OpenAI ada-002 dimensions
    model       VARCHAR(100) NOT NULL DEFAULT 'text-embedding-ada-002',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (product_id, model)
);

-- ─── DOCUMENT SEARCH TABLE ───────────────────────────────────
CREATE TABLE documents (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title       VARCHAR(500) NOT NULL,
    content     TEXT NOT NULL,
    embedding   vector(384),                        -- MiniLM-L6-v2 dimensions
    metadata    JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── VECTOR INDEXES ──────────────────────────────────────────
-- IVFFlat: faster build, slightly less accurate (good for large datasets)
-- HNSW: slower build, more accurate, better recall (recommended for most cases)

-- IVFFlat index (must have data before creating, lists ≈ sqrt(rows))
-- CREATE INDEX idx_product_embeddings_ivfflat
--     ON product_embeddings USING ivfflat (embedding vector_cosine_ops)
--     WITH (lists = 100);

-- HNSW index (can create before inserting data)
CREATE INDEX idx_product_embeddings_hnsw
    ON product_embeddings USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

CREATE INDEX idx_documents_hnsw
    ON documents USING hnsw (embedding vector_l2_ops)
    WITH (m = 16, ef_construction = 64);

-- ─── DISTANCE OPERATORS ──────────────────────────────────────
-- <->  Euclidean distance (L2)
-- <#>  Negative inner product (dot product, for normalized vectors)
-- <=>  Cosine distance (1 - cosine_similarity)
-- <+>  L1 distance (Manhattan)

-- ─── INSERT SAMPLE EMBEDDINGS (using random vectors for demo) ─
-- In real app, embeddings come from ML model (OpenAI, HuggingFace, etc.)
INSERT INTO product_embeddings (product_id, embedding)
SELECT id, ('[' || ARRAY_TO_STRING(ARRAY(
    SELECT ROUND(RANDOM()::NUMERIC - 0.5, 6)::TEXT
    FROM GENERATE_SERIES(1, 1536)
), ',') || ']')::vector
FROM products;

INSERT INTO documents (title, content, embedding)
VALUES
    ('PostgreSQL Performance', 'Tips for optimizing PostgreSQL queries and indexes',
     ('[' || ARRAY_TO_STRING(ARRAY(SELECT ROUND(RANDOM()::NUMERIC - 0.5, 6)::TEXT FROM GENERATE_SERIES(1,384)),',') || ']')::vector),
    ('Vector Databases', 'Introduction to vector similarity search and embeddings',
     ('[' || ARRAY_TO_STRING(ARRAY(SELECT ROUND(RANDOM()::NUMERIC - 0.5, 6)::TEXT FROM GENERATE_SERIES(1,384)),',') || ']')::vector);

-- ─── SIMILARITY SEARCH ───────────────────────────────────────
-- Find 5 most similar products to a query embedding (cosine similarity)
-- In real app: query_embedding comes from embedding model

-- Nearest neighbor search (cosine distance)
SELECT
    p.id,
    p.name,
    p.sku,
    1 - (pe.embedding <=> '[0.1,0.2,...]'::vector) AS cosine_similarity
FROM product_embeddings pe
JOIN products p ON p.id = pe.product_id
ORDER BY pe.embedding <=> '[0.1,0.2,...]'::vector
LIMIT 5;

-- L2 distance search
SELECT id, title,
       embedding <-> '[0.1,0.2,...]'::vector AS l2_distance
FROM documents
ORDER BY embedding <-> '[0.1,0.2,...]'::vector
LIMIT 5;

-- ─── HYBRID SEARCH (vector + keyword) ────────────────────────
-- Combine semantic similarity with keyword filtering
SELECT
    p.id, p.name, p.price,
    pe.embedding <=> '[0.1,0.2,...]'::vector AS distance
FROM product_embeddings pe
JOIN products p ON p.id = pe.product_id
WHERE p.price < 1000                            -- keyword filter
  AND p.is_active = TRUE
ORDER BY pe.embedding <=> '[0.1,0.2,...]'::vector
LIMIT 10;

-- ─── RECIPROCAL RANK FUSION (combine multiple search results) ─
WITH semantic AS (
    SELECT product_id,
           ROW_NUMBER() OVER (ORDER BY embedding <=> '[0.1,0.2,...]'::vector) AS rank
    FROM product_embeddings
    LIMIT 20
),
keyword AS (
    SELECT id AS product_id,
           ROW_NUMBER() OVER (ORDER BY TS_RANK(
               TO_TSVECTOR('english', name || ' ' || COALESCE(description,'')),
               TO_TSQUERY('english', 'laptop')
           ) DESC) AS rank
    FROM products
    WHERE TO_TSVECTOR('english', name || ' ' || COALESCE(description,''))
          @@ TO_TSQUERY('english', 'laptop')
    LIMIT 20
)
SELECT
    COALESCE(s.product_id, k.product_id) AS product_id,
    (COALESCE(1.0/(60+s.rank), 0) + COALESCE(1.0/(60+k.rank), 0)) AS rrf_score
FROM semantic s
FULL OUTER JOIN keyword k ON k.product_id = s.product_id
ORDER BY rrf_score DESC
LIMIT 10;

-- ─── VECTOR AGGREGATION ──────────────────────────────────────
-- Average embedding (centroid) for a category
SELECT AVG(pe.embedding) AS centroid
FROM product_embeddings pe
JOIN products p ON p.id = pe.product_id
WHERE p.category_id = 1;

-- ─── TUNE SEARCH ACCURACY vs SPEED ──────────────────────────
-- For HNSW: higher ef_search = more accurate but slower
SET hnsw.ef_search = 100;  -- default 40

-- For IVFFlat: higher probes = more accurate but slower
-- SET ivfflat.probes = 10;  -- default 1

-- ─── PITFALLS ────────────────────────────────────────────────
-- 1. HNSW index can use significant memory during build
-- 2. Vectors must have same dimensions — validate before insert
-- 3. Cosine similarity requires normalized vectors for <#> operator
-- 4. Index not used if WHERE clause filters too aggressively (use partial index)
-- 5. Large vector dimensions (>2000) = slow; consider dimensionality reduction
-- 6. Always benchmark: exact search vs approximate (HNSW/IVFFlat)
