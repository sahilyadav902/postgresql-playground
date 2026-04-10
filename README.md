# PostgreSQL Playground — A to Z

A complete learning environment for PostgreSQL covering every major feature,
paired with a Spring Boot API and Postman collection.

---

## Project Structure

```
postgresql-playground/
├── sql/
│   ├── 01_basics/          01_create_tables.sql      — DDL, data types, CRUD
│   ├── 02_constraints/     02_constraints.sql         — PK, FK, UNIQUE, CHECK, EXCLUSION
│   ├── 03_joins/           03_joins.sql               — INNER, LEFT, RIGHT, FULL, LATERAL, SELF
│   ├── 04_views/           04_views.sql               — Views, Materialized Views, Recursive Views
│   ├── 05_indexes/         05_indexes.sql             — B-Tree, GIN, GiST, BRIN, Partial, Covering
│   ├── 06_transactions/    06_transactions.sql        — ACID, Isolation, Savepoints, Locking
│   ├── 07_triggers/        07_triggers.sql            — BEFORE/AFTER, Audit Log, Business Rules
│   ├── 08_schemas/         08_schemas.sql             — Schemas, Multi-Tenant, Search Path
│   ├── 09_permissions/     09_permissions.sql         — Roles, Grants, RLS, Column Security
│   ├── 10_advanced/        10_advanced.sql            — CTEs, Window Functions, JSONB, Arrays, Dates
│   ├── 11_monitoring/      11_monitoring.sql          — EXPLAIN, pg_stat_*, VACUUM, Optimization
│   ├── 12_sharding/        12_sharding_partitioning.sql — RANGE/LIST/HASH partitioning, FDW
│   ├── 13_pgvector/        13_pgvector.sql            — Vector search, HNSW, hybrid search
│   └── 14_system_designs/  14_system_designs.sql      — URL shortener, rate limiter, job queue, etc.
│
├── springboot-app/
│   ├── build.gradle
│   ├── settings.gradle
│   └── src/
│       ├── main/
│       │   ├── java/com/pgplayground/
│       │   │   ├── PgPlaygroundApplication.java
│       │   │   ├── entity/         User, Product, Order, OrderItem, Category
│       │   │   ├── dto/            UserRequest, ProductRequest, OrderRequest, OrderSummary
│       │   │   ├── repository/     UserRepository, ProductRepository, OrderRepository, CategoryRepository
│       │   │   ├── service/        UserService, ProductService, OrderService
│       │   │   └── controller/     UserController, ProductController, OrderController,
│       │   │                       CategoryController, PgFeaturesController
│       │   └── resources/
│       │       ├── application.properties
│       │       ├── schema.sql
│       │       └── data.sql
│       └── test/
│           ├── java/com/pgplayground/
│           │   ├── UserServiceTest.java
│           │   ├── ProductServiceTest.java
│           │   └── OrderServiceTest.java
│           └── resources/
│               ├── application-test.properties
│               ├── schema-test.sql
│               └── data-test.sql
│
└── pg-playground.postman_collection.json
```

---

## Quick Start

### 1. PostgreSQL Setup

```sql
-- In psql or pgAdmin Query Tool:
CREATE DATABASE pg_playground;
\c pg_playground

-- Run scripts in order:
\i sql/01_basics/01_create_tables.sql
\i sql/02_constraints/02_constraints.sql
-- ... continue through all scripts
```

### 2. Spring Boot App

```bash
cd springboot-app

# Update credentials in src/main/resources/application.properties:
# spring.datasource.username=postgres
# spring.datasource.password=your_password

# Run
./gradlew bootRun

# Run tests (uses H2 in-memory, no PostgreSQL needed)
./gradlew test
```

### 3. Postman

Import `pg-playground.postman_collection.json` into Postman.
Set the `baseUrl` variable to `http://localhost:8080`.

---

## SQL Scripts — What Each Covers

| Script | Key Concepts |
|--------|-------------|
| 01_create_tables | CREATE TABLE, data types, ALTER TABLE, INSERT, UPDATE, DELETE, DROP |
| 02_constraints | PRIMARY KEY, FOREIGN KEY, UNIQUE, CHECK, NOT NULL, EXCLUSION, DEFERRABLE |
| 03_joins | INNER, LEFT, RIGHT, FULL OUTER, CROSS, SELF, LATERAL, anti-join, semi-join |
| 04_views | Regular views, WITH CHECK OPTION, security views, materialized views, REFRESH CONCURRENTLY |
| 05_indexes | B-Tree, Hash, GIN, GiST, BRIN, partial, covering (INCLUDE), expression, CONCURRENTLY |
| 06_transactions | BEGIN/COMMIT/ROLLBACK, SAVEPOINT, isolation levels, SELECT FOR UPDATE, SKIP LOCKED, advisory locks |
| 07_triggers | BEFORE/AFTER, FOR EACH ROW/STATEMENT, WHEN clause, audit log, business rules |
| 08_schemas | CREATE SCHEMA, search_path, schema-per-tenant, cross-schema queries |
| 09_permissions | CREATE ROLE, GRANT/REVOKE, RLS policies, column-level grants, SECURITY DEFINER |
| 10_advanced | CTEs, recursive CTEs, window functions (RANK, LAG, LEAD, running totals), stored functions, procedures, JSONB, arrays, date/time, COPY, GENERATE_SERIES |
| 11_monitoring | EXPLAIN ANALYZE, pg_stat_user_tables, pg_stat_statements, slow queries, VACUUM, cache hit ratio |
| 12_sharding | RANGE/LIST/HASH partitioning, sub-partitioning, partition management, FDW |
| 13_pgvector | vector type, HNSW/IVFFlat indexes, cosine/L2/dot product search, hybrid search, RRF |
| 14_system_designs | URL shortener, rate limiter, job queue (SKIP LOCKED), leaderboard, chat system, inventory |

---

## API Endpoints

| Method | Path | Feature Demonstrated |
|--------|------|---------------------|
| GET | /api/users | SELECT all, JPA findAll |
| GET | /api/users/{id} | SELECT by PK |
| GET | /api/users/no-orders | NOT EXISTS anti-join |
| POST | /api/users | INSERT, UNIQUE constraint |
| PUT | /api/users/{id} | UPDATE |
| DELETE | /api/users/{id} | Soft delete |
| POST | /api/users/{id}/loyalty-points | Bulk UPDATE |
| GET | /api/products | Paginated SELECT |
| GET | /api/products/search?q= | Full-text search (tsvector) |
| GET | /api/products/price-range | BETWEEN range query |
| POST | /api/products/{id}/decrement-stock | Atomic stock UPDATE |
| GET | /api/orders | JOIN + GROUP BY + DTO projection |
| POST | /api/orders | Atomic transaction (order + stock) |
| PATCH | /api/orders/{id}/status | Status transition validation |
| GET | /api/categories/tree | Recursive CTE |
| GET | /api/pg-features/user-rankings | RANK() window function |
| GET | /api/pg-features/running-revenue | SUM() OVER cumulative |
| GET | /api/pg-features/explain | EXPLAIN ANALYZE |
| GET | /api/pg-features/table-sizes | pg_class monitoring |
| GET | /api/pg-features/cache-hit-ratio | Buffer cache stats |
| POST | /api/pg-features/advisory-lock/{key} | Advisory locking |
| GET | /api/pg-features/locked-product/{id} | SELECT FOR UPDATE |
| GET | /api/pg-features/vacuum-stats | VACUUM monitoring |

---

## Key PostgreSQL Concepts by Category

### Performance
- Use `EXPLAIN (ANALYZE, BUFFERS)` to understand query plans
- `shared_buffers` = 25% RAM, `effective_cache_size` = 75% RAM
- `random_page_cost = 1.1` for SSD
- Partial indexes for hot-path queries (e.g., `WHERE is_active = true`)
- Covering indexes (`INCLUDE`) for index-only scans
- `VACUUM ANALYZE` regularly; monitor `n_dead_tup` in `pg_stat_user_tables`

### Concurrency
- `SELECT FOR UPDATE SKIP LOCKED` — job queue pattern (no blocking)
- `SELECT FOR UPDATE` — pessimistic locking
- Optimistic locking — version column + `WHERE version = ?`
- Advisory locks — distributed coordination without table locks
- Always acquire locks in consistent order to prevent deadlocks

### Multi-Tenancy
- Schema-per-tenant: strong isolation, complex migrations, ~1000 tenant limit
- Row-level (tenant_id): simpler, requires RLS for isolation
- RLS: `ALTER TABLE t ENABLE ROW LEVEL SECURITY` + `CREATE POLICY`

### Partitioning
- RANGE: time-series data (drop old partitions instantly)
- LIST: categorical data (region, status)
- HASH: even distribution when no natural key
- Partition pruning only works when WHERE uses partition key

### pgvector
- HNSW: better recall, slower build — use for most cases
- IVFFlat: faster build, needs data first, tune `lists` ≈ sqrt(rows)
- Hybrid search: combine vector similarity + keyword filters
- Tune `hnsw.ef_search` for accuracy vs speed tradeoff
