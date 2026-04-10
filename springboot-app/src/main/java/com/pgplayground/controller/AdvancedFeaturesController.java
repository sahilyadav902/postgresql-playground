package com.pgplayground.controller;

import jakarta.persistence.EntityManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

/**
 * Demonstrates: UPSERT (ON CONFLICT), LISTEN/NOTIFY, sequences,
 * enums, range types, GROUPING SETS/ROLLUP/CUBE, TABLESAMPLE,
 * error handling via PL/pgSQL functions, domains.
 */
@RestController
@RequestMapping("/api/advanced")
public class AdvancedFeaturesController {

    private final EntityManager em;

    public AdvancedFeaturesController(EntityManager em) {
        this.em = em;
    }

    // ─── UPSERT: ON CONFLICT DO UPDATE ───────────────────────
    @PostMapping("/upsert/page-view")
    @Transactional
    public Map<String, Object> upsertPageView(@RequestParam String page) {
        Object count = em.createNativeQuery("""
            INSERT INTO page_views (page, view_date, view_count)
            VALUES (:page, CURRENT_DATE, 1)
            ON CONFLICT (page, view_date)
            DO UPDATE SET view_count = page_views.view_count + 1
            RETURNING view_count
            """)
            .setParameter("page", page)
            .getSingleResult();
        return Map.of("page", page, "viewCount", count);
    }

    // ─── UPSERT: ON CONFLICT DO NOTHING ──────────────────────
    @PostMapping("/upsert/category")
    @Transactional
    public Map<String, Object> upsertCategory(@RequestParam String name) {
        int rows = em.createNativeQuery("""
            INSERT INTO categories (name) VALUES (:name)
            ON CONFLICT (name) DO NOTHING
            """)
            .setParameter("name", name)
            .executeUpdate();
        return Map.of("name", name, "inserted", rows > 0);
    }

    // ─── UPSERT with xmax trick (detect INSERT vs UPDATE) ────
    @PostMapping("/upsert/product-sync")
    @Transactional
    public Map<String, Object> syncProduct(@RequestParam String sku,
                                            @RequestParam String name,
                                            @RequestParam double price) {
        Object[] row = (Object[]) em.createNativeQuery("""
            INSERT INTO products (sku, name, price, stock)
            VALUES (:sku, :name, :price, 0)
            ON CONFLICT (sku)
            DO UPDATE SET name = EXCLUDED.name, price = EXCLUDED.price, updated_at = NOW()
            RETURNING id, sku, (xmax = 0) AS was_inserted
            """)
            .setParameter("sku", sku)
            .setParameter("name", name)
            .setParameter("price", price)
            .getSingleResult();
        return Map.of("id", row[0], "sku", row[1], "wasInserted", row[2]);
    }

    // ─── SEQUENCES ───────────────────────────────────────────
    @GetMapping("/sequence/next-invoice")
    @Transactional
    public Map<String, Object> nextInvoiceNumber() {
        Object val = em.createNativeQuery("SELECT NEXTVAL('invoice_seq')").getSingleResult();
        return Map.of("nextInvoiceNumber", val);
    }

    @GetMapping("/sequence/current-invoice")
    public Map<String, Object> currentInvoiceNumber() {
        Object val = em.createNativeQuery("SELECT last_value FROM invoice_seq").getSingleResult();
        return Map.of("currentValue", val);
    }

    // ─── ENUMS ───────────────────────────────────────────────
    @GetMapping("/enums/priority-values")
    public List<?> enumValues() {
        return em.createNativeQuery("""
            SELECT enumlabel, enumsortorder
            FROM pg_enum
            JOIN pg_type ON pg_type.oid = pg_enum.enumtypid
            WHERE pg_type.typname = 'priority_enum'
            ORDER BY enumsortorder
            """).getResultList();
    }

    @GetMapping("/enums/tickets-by-priority")
    public List<?> ticketsByPriority() {
        return em.createNativeQuery("""
            SELECT priority, COUNT(*) AS count
            FROM support_tickets
            GROUP BY priority
            ORDER BY priority
            """).getResultList();
    }

    // ─── RANGE TYPES ─────────────────────────────────────────
    @GetMapping("/ranges/available-rooms")
    public List<?> availableRooms(@RequestParam String checkIn,
                                   @RequestParam String checkOut) {
        return em.createNativeQuery("""
            SELECT room_no, available::TEXT
            FROM room_availability
            WHERE NOT (available && daterange(:checkIn::date, :checkOut::date))
            """)
            .setParameter("checkIn", checkIn)
            .setParameter("checkOut", checkOut)
            .getResultList();
    }

    @GetMapping("/ranges/price-tier")
    public List<?> priceTier(@RequestParam double price) {
        return em.createNativeQuery("""
            SELECT tier_name, discount
            FROM price_tiers
            WHERE price_range @> :price::NUMERIC
            """)
            .setParameter("price", price)
            .getResultList();
    }

    // ─── GROUPING SETS ────────────────────────────────────────
    @GetMapping("/grouping-sets/revenue")
    public List<?> revenueGroupingSets() {
        return em.createNativeQuery("""
            SELECT
                COALESCE(c.name, 'ALL') AS category,
                COALESCE(o.status, 'ALL') AS status,
                COUNT(DISTINCT o.id) AS order_count,
                COALESCE(SUM(oi.quantity * oi.unit_price), 0) AS revenue
            FROM orders o
            JOIN order_items oi ON oi.order_id = o.id
            JOIN products p ON p.id = oi.product_id
            LEFT JOIN categories c ON c.id = p.category_id
            GROUP BY GROUPING SETS ((c.name, o.status), (c.name), (o.status), ())
            ORDER BY category NULLS LAST, status NULLS LAST
            """).getResultList();
    }

    // ─── ROLLUP ───────────────────────────────────────────────
    @GetMapping("/rollup/monthly-revenue")
    public List<?> monthlyRevenueRollup() {
        return em.createNativeQuery("""
            SELECT
                DATE_PART('year',  created_at)::INT AS year,
                DATE_PART('month', created_at)::INT AS month,
                COUNT(*) AS orders,
                SUM(total) AS revenue
            FROM orders
            WHERE status != 'cancelled'
            GROUP BY ROLLUP (DATE_PART('year', created_at), DATE_PART('month', created_at))
            ORDER BY year NULLS LAST, month NULLS LAST
            """).getResultList();
    }

    // ─── TABLESAMPLE ──────────────────────────────────────────
    @GetMapping("/tablesample/orders")
    public List<?> sampleOrders(@RequestParam(defaultValue = "10") double pct) {
        return em.createNativeQuery(
            "SELECT id, total, status FROM orders TABLESAMPLE BERNOULLI(:pct) REPEATABLE(42)"
        ).setParameter("pct", pct).getResultList();
    }

    // ─── LISTEN/NOTIFY: send a notification ──────────────────
    @PostMapping("/notify")
    @Transactional
    public Map<String, Object> sendNotification(@RequestParam String channel,
                                                 @RequestParam String payload) {
        em.createNativeQuery("SELECT pg_notify(:channel, :payload)")
            .setParameter("channel", channel)
            .setParameter("payload", payload)
            .getSingleResult();
        return Map.of("channel", channel, "payload", payload, "sent", true);
    }

    // ─── ERROR HANDLING: call safe PL/pgSQL function ─────────
    @PostMapping("/safe-transfer")
    @Transactional
    public Map<String, Object> safeTransfer(@RequestParam Long fromId,
                                             @RequestParam Long toId,
                                             @RequestParam double amount) {
        Object result = em.createNativeQuery(
            "SELECT safe_transfer(:from, :to, :amount)"
        )
            .setParameter("from", fromId)
            .setParameter("to", toId)
            .setParameter("amount", amount)
            .getSingleResult();
        return Map.of("result", result.toString());
    }

    // ─── DOMAIN VALIDATION demo ───────────────────────────────
    @PostMapping("/domain/validate-contact")
    @Transactional
    public Map<String, Object> validateContact(@RequestParam String email,
                                                @RequestParam(required = false) String zip) {
        try {
            em.createNativeQuery("""
                INSERT INTO validated_contacts (email, zip)
                VALUES (:email::email_address, :zip::us_zip)
                """)
                .setParameter("email", email)
                .setParameter("zip", zip == null ? "00000" : zip)
                .executeUpdate();
            return Map.of("valid", true, "email", email);
        } catch (Exception e) {
            return Map.of("valid", false, "error", e.getMessage());
        }
    }

    // ─── WINDOW FUNCTIONS: LAG/LEAD ───────────────────────────
    @GetMapping("/window/lag-lead")
    public List<?> lagLead() {
        return em.createNativeQuery("""
            SELECT
                DATE_TRUNC('day', created_at)::DATE AS day,
                SUM(total) AS revenue,
                LAG(SUM(total))  OVER (ORDER BY DATE_TRUNC('day', created_at)) AS prev_day,
                LEAD(SUM(total)) OVER (ORDER BY DATE_TRUNC('day', created_at)) AS next_day,
                SUM(total) - LAG(SUM(total)) OVER (ORDER BY DATE_TRUNC('day', created_at)) AS delta
            FROM orders
            WHERE status != 'cancelled'
            GROUP BY DATE_TRUNC('day', created_at)
            ORDER BY day
            """).getResultList();
    }

    // ─── WINDOW FUNCTIONS: NTILE (quartiles) ─────────────────
    @GetMapping("/window/customer-quartiles")
    public List<?> customerQuartiles() {
        return em.createNativeQuery("""
            SELECT username, total_spent,
                   NTILE(4) OVER (ORDER BY total_spent) AS quartile,
                   PERCENT_RANK() OVER (ORDER BY total_spent) AS pct_rank
            FROM (
                SELECT u.username, COALESCE(SUM(o.total), 0) AS total_spent
                FROM users u LEFT JOIN orders o ON o.user_id = u.id
                GROUP BY u.id, u.username
            ) s
            ORDER BY total_spent DESC
            """).getResultList();
    }

    // ─── MOVING AVERAGE ───────────────────────────────────────
    @GetMapping("/window/moving-average")
    public List<?> movingAverage(@RequestParam(defaultValue = "7") int days) {
        return em.createNativeQuery("""
            SELECT
                DATE_TRUNC('day', created_at)::DATE AS day,
                SUM(total) AS daily_revenue,
                AVG(SUM(total)) OVER (
                    ORDER BY DATE_TRUNC('day', created_at)
                    ROWS BETWEEN :days PRECEDING AND CURRENT ROW
                ) AS moving_avg
            FROM orders
            WHERE status != 'cancelled'
            GROUP BY DATE_TRUNC('day', created_at)
            ORDER BY day
            """).setParameter("days", days - 1).getResultList();
    }
}
