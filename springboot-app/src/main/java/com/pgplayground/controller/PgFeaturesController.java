package com.pgplayground.controller;

import jakarta.persistence.EntityManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

/**
 * Demonstrates raw PostgreSQL features: window functions, CTEs,
 * EXPLAIN, locking, advisory locks, monitoring queries.
 */
@RestController
@RequestMapping("/api/pg-features")
public class PgFeaturesController {

    private final EntityManager em;

    public PgFeaturesController(EntityManager em) {
        this.em = em;
    }

    // Window functions: rank users by total spend
    @GetMapping("/user-rankings")
    public List<?> userRankings() {
        return em.createNativeQuery("""
            SELECT u.username,
                   COALESCE(SUM(o.total), 0) AS total_spent,
                   RANK() OVER (ORDER BY COALESCE(SUM(o.total), 0) DESC) AS rank
            FROM users u
            LEFT JOIN orders o ON o.user_id = u.id AND o.status != 'cancelled'
            GROUP BY u.id, u.username
            ORDER BY rank
            """).getResultList();
    }

    // CTE: top products with category
    @GetMapping("/top-products")
    public List<?> topProducts(@RequestParam(defaultValue = "5") int limit) {
        return em.createNativeQuery("""
            WITH sales AS (
                SELECT oi.product_id, SUM(oi.quantity) AS total_sold
                FROM order_items oi
                JOIN orders o ON o.id = oi.order_id AND o.status != 'cancelled'
                GROUP BY oi.product_id
            )
            SELECT p.name, p.sku, c.name AS category, COALESCE(s.total_sold, 0) AS total_sold
            FROM products p
            LEFT JOIN categories c ON c.id = p.category_id
            LEFT JOIN sales s ON s.product_id = p.id
            ORDER BY total_sold DESC
            LIMIT :limit
            """).setParameter("limit", limit).getResultList();
    }

    // Running total (window function)
    @GetMapping("/running-revenue")
    public List<?> runningRevenue() {
        return em.createNativeQuery("""
            SELECT DATE_TRUNC('day', created_at) AS day,
                   SUM(total) AS daily_revenue,
                   SUM(SUM(total)) OVER (ORDER BY DATE_TRUNC('day', created_at)
                       ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total
            FROM orders
            WHERE status != 'cancelled'
            GROUP BY DATE_TRUNC('day', created_at)
            ORDER BY day
            """).getResultList();
    }

    // EXPLAIN ANALYZE output
    @GetMapping("/explain")
    public List<?> explainQuery(@RequestParam(defaultValue = "SELECT * FROM products WHERE is_active = true") String sql) {
        return em.createNativeQuery("EXPLAIN (ANALYZE, FORMAT TEXT) " + sql).getResultList();
    }

    // Table sizes
    @GetMapping("/table-sizes")
    public List<?> tableSizes() {
        return em.createNativeQuery("""
            SELECT relname AS table_name,
                   pg_size_pretty(pg_total_relation_size(oid)) AS total_size,
                   pg_size_pretty(pg_relation_size(oid)) AS table_size,
                   pg_size_pretty(pg_indexes_size(oid)) AS indexes_size
            FROM pg_class
            WHERE relkind = 'r' AND relnamespace = 'public'::regnamespace
            ORDER BY pg_total_relation_size(oid) DESC
            """).getResultList();
    }

    // Active connections
    @GetMapping("/active-connections")
    public List<?> activeConnections() {
        return em.createNativeQuery("""
            SELECT pid, usename, application_name, state,
                   now() - query_start AS duration,
                   LEFT(query, 100) AS query_snippet
            FROM pg_stat_activity
            WHERE state != 'idle' AND pid != pg_backend_pid()
            ORDER BY duration DESC NULLS LAST
            """).getResultList();
    }

    // Index usage stats
    @GetMapping("/index-stats")
    public List<?> indexStats() {
        return em.createNativeQuery("""
            SELECT relname AS table_name, indexrelname AS index_name,
                   idx_scan, idx_tup_read, idx_tup_fetch
            FROM pg_stat_user_indexes
            ORDER BY idx_scan DESC
            """).getResultList();
    }

    // Cache hit ratio
    @GetMapping("/cache-hit-ratio")
    public List<?> cacheHitRatio() {
        return em.createNativeQuery("""
            SELECT
                ROUND(SUM(heap_blks_hit)::NUMERIC /
                    NULLIF(SUM(heap_blks_hit) + SUM(heap_blks_read), 0) * 100, 2) AS table_cache_hit_pct,
                ROUND(SUM(idx_blks_hit)::NUMERIC /
                    NULLIF(SUM(idx_blks_hit) + SUM(idx_blks_read), 0) * 100, 2) AS index_cache_hit_pct
            FROM pg_statio_user_tables
            """).getResultList();
    }

    // Advisory lock demo (session-level)
    @PostMapping("/advisory-lock/{key}")
    @Transactional
    public Map<String, Object> tryAdvisoryLock(@PathVariable long key) {
        Object result = em.createNativeQuery("SELECT pg_try_advisory_xact_lock(:key)")
            .setParameter("key", key)
            .getSingleResult();
        return Map.of("key", key, "acquired", result);
    }

    // Demonstrate SELECT FOR UPDATE (row-level lock)
    @GetMapping("/locked-product/{id}")
    @Transactional
    public List<?> getProductWithLock(@PathVariable Long id) {
        return em.createNativeQuery("SELECT * FROM products WHERE id = :id FOR UPDATE NOWAIT")
            .setParameter("id", id)
            .getResultList();
    }

    // Vacuum stats
    @GetMapping("/vacuum-stats")
    public List<?> vacuumStats() {
        return em.createNativeQuery("""
            SELECT relname, n_live_tup, n_dead_tup,
                   ROUND(n_dead_tup::NUMERIC / NULLIF(n_live_tup + n_dead_tup, 0) * 100, 2) AS dead_pct,
                   last_vacuum, last_autovacuum, last_analyze
            FROM pg_stat_user_tables
            ORDER BY n_dead_tup DESC
            """).getResultList();
    }
}
