-- =============================================================
-- 09_PERMISSIONS.SQL — Roles, Grants, RLS, Column Security
-- Scenario: Healthcare Data Access Control
-- =============================================================

-- ─── ROLES vs USERS ──────────────────────────────────────────
-- In PostgreSQL, users ARE roles (with LOGIN privilege)
-- Roles can be granted to other roles (role hierarchy)

-- ─── CREATE ROLES ────────────────────────────────────────────
CREATE ROLE readonly_role NOLOGIN;          -- group role, no login
CREATE ROLE app_writer NOLOGIN;
CREATE ROLE admin_role NOLOGIN SUPERUSER;   -- careful with superuser!

-- Create actual users (roles with LOGIN)
CREATE ROLE app_user LOGIN PASSWORD 'securepass123';
CREATE ROLE report_user LOGIN PASSWORD 'reportpass456';
CREATE ROLE api_service LOGIN PASSWORD 'apipass789';

-- ─── GRANT ROLE MEMBERSHIP ───────────────────────────────────
GRANT readonly_role TO report_user;         -- report_user inherits readonly_role perms
GRANT app_writer TO app_user;
GRANT app_writer TO api_service;

-- ─── TABLE-LEVEL PERMISSIONS ─────────────────────────────────
-- Grant SELECT on all tables to readonly_role
GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly_role;

-- Grant DML to app_writer
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_writer;

-- Grant sequence usage (needed for SERIAL/IDENTITY inserts)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_writer;

-- Future tables automatically get same permissions
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO readonly_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_writer;

-- ─── COLUMN-LEVEL PERMISSIONS ────────────────────────────────
-- Only allow app_user to see non-sensitive columns of users
REVOKE SELECT ON users FROM app_writer;
GRANT SELECT (id, username, email, role, is_active, created_at) ON users TO app_writer;
-- app_writer cannot SELECT display_name, phone, metadata, avatar

-- ─── ROW LEVEL SECURITY (RLS) ────────────────────────────────
-- Scenario: users can only see their own orders

-- Enable RLS on orders table
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- Policy: users see only their own orders
-- current_setting('app.current_user_id') is set by the application
CREATE POLICY orders_user_isolation ON orders
    FOR ALL
    TO app_writer
    USING (user_id = current_setting('app.current_user_id')::BIGINT);

-- Admin bypass policy
CREATE POLICY orders_admin_all ON orders
    FOR ALL
    TO admin_role
    USING (TRUE);  -- admins see everything

-- Application sets the user context before queries:
-- SET app.current_user_id = '42';
-- SELECT * FROM orders;  -- only returns orders for user 42

-- ─── RLS: Multi-tenant isolation ─────────────────────────────
CREATE TABLE tenant_data (
    id          SERIAL PRIMARY KEY,
    tenant_id   INT NOT NULL,
    data        TEXT
);

ALTER TABLE tenant_data ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON tenant_data
    USING (tenant_id = current_setting('app.tenant_id')::INT);

-- ─── FORCE RLS (even for table owner) ────────────────────────
ALTER TABLE orders FORCE ROW LEVEL SECURITY;

-- ─── REVOKE PERMISSIONS ──────────────────────────────────────
REVOKE DELETE ON orders FROM app_writer;    -- app_writer can no longer delete orders
REVOKE ALL ON products FROM report_user;

-- ─── OBJECT OWNERSHIP ────────────────────────────────────────
ALTER TABLE products OWNER TO app_user;     -- change table owner

-- ─── VIEW PERMISSIONS ────────────────────────────────────────
-- Who has what permissions on a table
SELECT grantee, privilege_type, is_grantable
FROM information_schema.role_table_grants
WHERE table_name = 'orders' AND table_schema = 'public';

-- All roles
SELECT rolname, rolsuper, rolinherit, rolcreatedb, rolcanlogin
FROM pg_roles
WHERE rolname NOT LIKE 'pg_%'
ORDER BY rolname;

-- Role memberships
SELECT r.rolname AS role, m.rolname AS member
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.roleid
JOIN pg_roles m ON m.oid = am.member;

-- ─── SECURITY DEFINER vs SECURITY INVOKER ────────────────────
-- SECURITY DEFINER: function runs with owner's privileges (like sudo)
-- SECURITY INVOKER: function runs with caller's privileges (default)

CREATE OR REPLACE FUNCTION get_all_orders()
RETURNS TABLE (id BIGINT, user_id BIGINT, total NUMERIC) AS $$
    SELECT id, user_id, total FROM orders;
$$ LANGUAGE sql SECURITY DEFINER;  -- even restricted users can call this

-- ─── PITFALLS ────────────────────────────────────────────────
-- 1. RLS is bypassed by superusers and table owners (use FORCE ROW LEVEL SECURITY)
-- 2. SECURITY DEFINER functions are a privilege escalation risk — audit carefully
-- 3. Column-level grants don't work with SELECT * — must name columns
-- 4. Forgetting to grant USAGE on schema = "permission denied for schema"
-- 5. ALTER DEFAULT PRIVILEGES only affects future objects, not existing ones
