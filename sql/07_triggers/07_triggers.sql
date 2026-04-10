-- =============================================================
-- 07_TRIGGERS.SQL — BEFORE/AFTER, ROW/STATEMENT, DDL Triggers,
--                   Trigger Functions, Audit Logging
-- Scenario: Audit Trail & Business Rules Enforcement
-- =============================================================

-- ─── AUDIT LOG TABLE ─────────────────────────────────────────
CREATE TABLE audit_log (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name  VARCHAR(100) NOT NULL,
    operation   VARCHAR(10) NOT NULL,           -- INSERT, UPDATE, DELETE
    old_data    JSONB,
    new_data    JSONB,
    changed_by  VARCHAR(100) DEFAULT CURRENT_USER,
    changed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── TRIGGER FUNCTION: auto-update updated_at ────────────────
CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;  -- RETURN NEW for BEFORE triggers (use the modified row)
END;
$$ LANGUAGE plpgsql;

-- Attach to users table
CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION fn_set_updated_at();

-- Attach to products table
CREATE TRIGGER trg_products_updated_at
    BEFORE UPDATE ON products
    FOR EACH ROW
    EXECUTE FUNCTION fn_set_updated_at();

-- ─── TRIGGER FUNCTION: generic audit log ─────────────────────
CREATE OR REPLACE FUNCTION fn_audit_log()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, operation, new_data)
        VALUES (TG_TABLE_NAME, TG_OP, ROW_TO_JSON(NEW)::JSONB);
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, operation, old_data, new_data)
        VALUES (TG_TABLE_NAME, TG_OP, ROW_TO_JSON(OLD)::JSONB, ROW_TO_JSON(NEW)::JSONB);
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, operation, old_data)
        VALUES (TG_TABLE_NAME, TG_OP, ROW_TO_JSON(OLD)::JSONB);
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Attach audit trigger to orders
CREATE TRIGGER trg_orders_audit
    AFTER INSERT OR UPDATE OR DELETE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION fn_audit_log();

-- ─── TRIGGER: enforce business rule ──────────────────────────
-- Prevent cancelling an order that is already delivered
CREATE OR REPLACE FUNCTION fn_validate_order_status()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status = 'delivered' AND NEW.status = 'cancelled' THEN
        RAISE EXCEPTION 'Cannot cancel a delivered order (order_id: %)', OLD.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_order_status_check
    BEFORE UPDATE ON orders
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)  -- only fires when status changes
    EXECUTE FUNCTION fn_validate_order_status();

-- ─── TRIGGER: auto-calculate order total ─────────────────────
CREATE OR REPLACE FUNCTION fn_recalculate_order_total()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE orders
    SET total = (
        SELECT COALESCE(SUM(quantity * unit_price), 0)
        FROM order_items
        WHERE order_id = COALESCE(NEW.order_id, OLD.order_id)
    )
    WHERE id = COALESCE(NEW.order_id, OLD.order_id);
    RETURN NULL;  -- AFTER trigger on order_items, return NULL for STATEMENT triggers
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_order_items_total
    AFTER INSERT OR UPDATE OR DELETE ON order_items
    FOR EACH ROW
    EXECUTE FUNCTION fn_recalculate_order_total();

-- ─── STATEMENT-LEVEL TRIGGER ─────────────────────────────────
-- Fires once per SQL statement, not per row
CREATE TABLE bulk_import_log (
    id          SERIAL PRIMARY KEY,
    table_name  VARCHAR(100),
    imported_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION fn_log_bulk_import()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO bulk_import_log (table_name) VALUES (TG_TABLE_NAME);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_products_bulk_import
    AFTER INSERT ON products
    FOR EACH STATEMENT
    EXECUTE FUNCTION fn_log_bulk_import();

-- ─── CONDITIONAL TRIGGER (WHEN clause) ───────────────────────
-- Only audit price changes > 10%
CREATE OR REPLACE FUNCTION fn_audit_price_change()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log (table_name, operation, old_data, new_data)
    VALUES ('products', 'PRICE_CHANGE',
            JSONB_BUILD_OBJECT('price', OLD.price),
            JSONB_BUILD_OBJECT('price', NEW.price, 'change_pct',
                ROUND(((NEW.price - OLD.price) / OLD.price * 100)::NUMERIC, 2)));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_product_price_audit
    BEFORE UPDATE ON products
    FOR EACH ROW
    WHEN (ABS(NEW.price - OLD.price) / OLD.price > 0.10)  -- >10% change
    EXECUTE FUNCTION fn_audit_price_change();

-- ─── TEST TRIGGERS ───────────────────────────────────────────
-- Test audit trigger
UPDATE orders SET status = 'shipped' WHERE id = 1;
SELECT * FROM audit_log;

-- Test business rule trigger (should fail)
-- UPDATE orders SET status = 'delivered' WHERE id = 1;
-- UPDATE orders SET status = 'cancelled' WHERE id = 1;  -- ERROR!

-- ─── VIEW / MANAGE TRIGGERS ──────────────────────────────────
SELECT trigger_name, event_manipulation, event_object_table, action_timing
FROM information_schema.triggers
WHERE trigger_schema = 'public'
ORDER BY event_object_table, trigger_name;

-- Disable/enable trigger
ALTER TABLE orders DISABLE TRIGGER trg_orders_audit;
ALTER TABLE orders ENABLE TRIGGER trg_orders_audit;

-- Drop trigger
-- DROP TRIGGER trg_orders_audit ON orders;

-- ─── PITFALLS ────────────────────────────────────────────────
-- 1. Triggers fire recursively if they modify the same table — use pg_trigger_depth()
-- 2. BEFORE triggers can modify NEW row; AFTER triggers cannot
-- 3. Statement triggers don't have access to OLD/NEW rows
-- 4. Heavy triggers on hot tables = performance bottleneck
-- 5. Triggers make debugging harder — document them well
