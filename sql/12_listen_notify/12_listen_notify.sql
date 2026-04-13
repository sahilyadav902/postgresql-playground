-- =============================================================
-- 17_LISTEN_NOTIFY.SQL — Async Pub/Sub with LISTEN/NOTIFY
-- Scenario: Real-time order status updates, cache invalidation,
--           background job signalling
-- =============================================================

-- ─── WHAT IS LISTEN/NOTIFY? ──────────────────────────────────
-- PostgreSQL has a built-in async messaging system.
-- NOTIFY sends a message on a named channel.
-- LISTEN subscribes to a channel.
-- Messages are delivered after the sending transaction commits.
-- Payload is a text string (max ~8000 bytes).
-- Use cases: cache invalidation, real-time dashboards, job queues,
--            microservice events without a message broker.

-- ─── BASIC USAGE ─────────────────────────────────────────────
-- Terminal / Session 1 (subscriber):
LISTEN order_updates;
LISTEN product_changes;

-- Terminal / Session 2 (publisher):
NOTIFY order_updates, '{"orderId": 42, "status": "shipped"}';
NOTIFY product_changes, '{"productId": 1, "event": "stock_low", "stock": 3}';

-- Session 1 receives:
-- Asynchronous notification "order_updates" with payload "{"orderId": 42, ...}"

-- ─── NOTIFY FROM A TRIGGER ───────────────────────────────────
-- Automatically notify when order status changes
CREATE OR REPLACE FUNCTION fn_notify_order_status()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        PERFORM PG_NOTIFY(
            'order_updates',
            JSON_BUILD_OBJECT(
                'orderId', NEW.id,
                'oldStatus', OLD.status,
                'newStatus', NEW.status,
                'updatedAt', NOW()
            )::TEXT
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_notify_order_status
    AFTER UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION fn_notify_order_status();

-- Now any UPDATE to orders.status fires a NOTIFY automatically
UPDATE orders SET status = 'shipped' WHERE id = 1;
-- → subscribers on 'order_updates' receive the JSON payload

-- ─── NOTIFY FROM A TRIGGER: cache invalidation ───────────────
CREATE OR REPLACE FUNCTION fn_notify_product_change()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM PG_NOTIFY('product_changes',
        JSON_BUILD_OBJECT('id', COALESCE(NEW.id, OLD.id), 'op', TG_OP)::TEXT);
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_notify_product_change
    AFTER INSERT OR UPDATE OR DELETE ON products
    FOR EACH ROW
    EXECUTE FUNCTION fn_notify_product_change();

-- ─── UNLISTEN ────────────────────────────────────────────────
UNLISTEN order_updates;     -- stop listening to one channel
UNLISTEN *;                 -- stop listening to all channels

-- ─── PG_NOTIFY vs NOTIFY ─────────────────────────────────────
-- NOTIFY channel [, payload]  — SQL command
-- PG_NOTIFY(channel, payload) — function, usable inside PL/pgSQL

-- ─── CHECKING PENDING NOTIFICATIONS ─────────────────────────
-- In psql: \watch 1  (re-run last query every 1 second)
-- In application: use JDBC setAutoCommit(false) + getNotifications()
-- In Spring: use PGConnection.getNotifications() in a background thread

-- ─── CHANNEL NAMING CONVENTIONS ─────────────────────────────
-- Use lowercase, underscores: order_updates, cache_invalidate, job_ready
-- Namespace by service: payments.refund_processed, inventory.stock_low

-- ─── PITFALLS ────────────────────────────────────────────────
-- 1. Notifications are NOT persisted — if listener is down, messages are lost
-- 2. Payload limited to ~8000 bytes — send IDs, not full objects
-- 3. Notifications only delivered after COMMIT — not on ROLLBACK
-- 4. No delivery guarantee, no ordering guarantee across channels
-- 5. Not a replacement for Kafka/RabbitMQ for high-throughput systems
-- 6. Connection must stay open to receive notifications (long-lived connection)
-- 7. pg_notify inside a long transaction delays delivery until commit
