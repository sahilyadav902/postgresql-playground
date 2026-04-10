-- =============================================================
-- 08_SCHEMAS.SQL — Schema Management, Search Path, Multi-Tenant
-- Scenario: Multi-Tenant SaaS Application
-- =============================================================

-- ─── WHAT IS A SCHEMA? ───────────────────────────────────────
-- A schema is a namespace within a database.
-- Default schema is 'public'. Objects are referenced as schema.table.
-- Use cases: multi-tenancy, module separation, permission isolation

-- ─── CREATE SCHEMAS ──────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS app;        -- application tables
CREATE SCHEMA IF NOT EXISTS reporting;  -- reporting/analytics tables
CREATE SCHEMA IF NOT EXISTS audit;      -- audit tables

-- ─── CREATE TABLES IN SPECIFIC SCHEMAS ───────────────────────
CREATE TABLE app.tenants (
    id          SERIAL PRIMARY KEY,
    slug        VARCHAR(100) NOT NULL UNIQUE,    -- e.g., 'acme-corp'
    name        VARCHAR(255) NOT NULL,
    plan        VARCHAR(50) NOT NULL DEFAULT 'free'
                    CHECK (plan IN ('free','starter','pro','enterprise')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE app.tenant_users (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id   INT NOT NULL REFERENCES app.tenants(id) ON DELETE CASCADE,
    email       VARCHAR(255) NOT NULL,
    role        VARCHAR(50) NOT NULL DEFAULT 'member',
    UNIQUE (tenant_id, email)
);

CREATE TABLE reporting.monthly_summary (
    tenant_id   INT NOT NULL REFERENCES app.tenants(id),
    month       DATE NOT NULL,
    metric_key  VARCHAR(100) NOT NULL,
    metric_val  NUMERIC(20,4),
    PRIMARY KEY (tenant_id, month, metric_key)
);

CREATE TABLE audit.changes (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    schema_name VARCHAR(100),
    table_name  VARCHAR(100),
    operation   VARCHAR(10),
    changed_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ─── SEARCH PATH ─────────────────────────────────────────────
-- Controls which schemas are searched when no schema is specified
SHOW search_path;                           -- default: "$user", public

-- Set for current session
SET search_path TO app, reporting, public;

-- Now you can query without schema prefix:
SELECT * FROM tenants;                      -- resolves to app.tenants

-- Set permanently for a role
ALTER ROLE myapp_user SET search_path TO app, public;

-- ─── MULTI-TENANT PATTERN 1: Schema-per-tenant ───────────────
-- Each tenant gets their own schema — strong isolation
-- Good for: compliance, large tenants, different schemas per tenant

CREATE OR REPLACE FUNCTION create_tenant_schema(tenant_slug TEXT)
RETURNS VOID AS $$
BEGIN
    EXECUTE FORMAT('CREATE SCHEMA IF NOT EXISTS tenant_%s', tenant_slug);
    EXECUTE FORMAT('
        CREATE TABLE tenant_%s.projects (
            id          SERIAL PRIMARY KEY,
            name        VARCHAR(255) NOT NULL,
            created_at  TIMESTAMPTZ DEFAULT NOW()
        )', tenant_slug);
    EXECUTE FORMAT('
        CREATE TABLE tenant_%s.tasks (
            id          SERIAL PRIMARY KEY,
            project_id  INT NOT NULL REFERENCES tenant_%s.projects(id),
            title       VARCHAR(500) NOT NULL,
            done        BOOLEAN DEFAULT FALSE
        )', tenant_slug, tenant_slug);
END;
$$ LANGUAGE plpgsql;

-- Create schemas for two tenants
SELECT create_tenant_schema('acme');
SELECT create_tenant_schema('globex');

-- Each tenant has isolated data
INSERT INTO tenant_acme.projects (name) VALUES ('Website Redesign');
INSERT INTO tenant_globex.projects (name) VALUES ('Mobile App');

-- ─── MULTI-TENANT PATTERN 2: Row-level (tenant_id column) ────
-- All tenants share tables — simpler, but requires RLS for isolation
-- See 09_permissions.sql for Row Level Security

-- ─── SCHEMA PERMISSIONS ──────────────────────────────────────
-- Create a read-only reporting role
CREATE ROLE reporting_role;
GRANT USAGE ON SCHEMA reporting TO reporting_role;
GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO reporting_role;
-- Future tables too:
ALTER DEFAULT PRIVILEGES IN SCHEMA reporting
    GRANT SELECT ON TABLES TO reporting_role;

-- App role with full access to app schema
CREATE ROLE app_role;
GRANT USAGE ON SCHEMA app TO app_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO app_role;

-- ─── LIST SCHEMAS ────────────────────────────────────────────
SELECT schema_name, schema_owner
FROM information_schema.schemata
WHERE schema_name NOT IN ('pg_catalog', 'information_schema')
ORDER BY schema_name;

-- Tables per schema
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY table_schema, table_name;

-- ─── DROP SCHEMA ─────────────────────────────────────────────
-- DROP SCHEMA tenant_acme CASCADE;   -- drops schema and all its objects
-- DROP SCHEMA reporting RESTRICT;    -- fails if schema has objects

-- ─── PITFALLS ────────────────────────────────────────────────
-- 1. Schema-per-tenant doesn't scale beyond ~1000 tenants (pg_catalog bloat)
-- 2. search_path injection: never use user input in search_path
-- 3. Cross-schema JOINs work but can be confusing — document clearly
-- 4. Migrations become complex with schema-per-tenant (run N times)
-- 5. Default 'public' schema is accessible to all — restrict in production
REVOKE CREATE ON SCHEMA public FROM PUBLIC;  -- security best practice
