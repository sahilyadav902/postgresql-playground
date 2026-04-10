-- =============================================================
-- 18_ERROR_HANDLING.SQL — PL/pgSQL Exception Handling,
--                          Custom Error Codes, RAISE, Domains
-- Scenario: Robust stored procedures with proper error handling
-- =============================================================

-- ═══════════════════════════════════════════════════════════════
-- PART 1: RAISE — emit messages and errors
-- ═══════════════════════════════════════════════════════════════

-- RAISE levels: DEBUG, LOG, INFO, NOTICE, WARNING, EXCEPTION
-- Only EXCEPTION aborts the transaction

CREATE OR REPLACE FUNCTION demo_raise_levels()
RETURNS VOID AS $$
BEGIN
    RAISE DEBUG   'Debug: internal detail (only in logs if log_min_messages=debug)';
    RAISE LOG     'Log: written to server log';
    RAISE INFO    'Info: sent to client';
    RAISE NOTICE  'Notice: sent to client (default visible level)';
    RAISE WARNING 'Warning: sent to client';
    -- RAISE EXCEPTION 'This would abort the transaction';
END;
$$ LANGUAGE plpgsql;

SELECT demo_raise_levels();

-- RAISE with SQLSTATE (custom error code)
CREATE OR REPLACE FUNCTION raise_custom_error()
RETURNS VOID AS $$
BEGIN
    RAISE EXCEPTION 'Insufficient balance'
        USING ERRCODE = 'P0001',    -- user-defined error (P0001–P9999)
              HINT    = 'Top up your account before retrying',
              DETAIL  = 'Required: 500.00, Available: 100.00';
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════
-- PART 2: EXCEPTION HANDLING
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION safe_transfer(
    p_from BIGINT, p_to BIGINT, p_amount NUMERIC
) RETURNS JSONB AS $$
DECLARE
    v_balance NUMERIC;
    v_err_msg TEXT;
    v_err_detail TEXT;
    v_err_hint TEXT;
    v_sqlstate TEXT;
BEGIN
    -- Validate inputs
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Amount must be positive' USING ERRCODE = 'P0002';
    END IF;

    SELECT balance INTO STRICT v_balance
    FROM bank_accounts WHERE id = p_from FOR UPDATE;

    IF v_balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient funds: have %, need %', v_balance, p_amount
            USING ERRCODE = 'P0001';
    END IF;

    UPDATE bank_accounts SET balance = balance - p_amount WHERE id = p_from;
    UPDATE bank_accounts SET balance = balance + p_amount WHERE id = p_to;

    RETURN JSONB_BUILD_OBJECT('success', true, 'transferred', p_amount);

EXCEPTION
    WHEN SQLSTATE 'P0001' THEN          -- our custom insufficient funds
        GET STACKED DIAGNOSTICS
            v_err_msg    = MESSAGE_TEXT,
            v_err_detail = PG_EXCEPTION_DETAIL,
            v_err_hint   = PG_EXCEPTION_HINT;
        RETURN JSONB_BUILD_OBJECT('success', false, 'error', v_err_msg);

    WHEN NO_DATA_FOUND THEN             -- SELECT INTO STRICT found no rows
        RETURN JSONB_BUILD_OBJECT('success', false, 'error', 'Account not found');

    WHEN TOO_MANY_ROWS THEN
        RETURN JSONB_BUILD_OBJECT('success', false, 'error', 'Multiple accounts found');

    WHEN OTHERS THEN                    -- catch-all
        GET STACKED DIAGNOSTICS
            v_err_msg  = MESSAGE_TEXT,
            v_sqlstate = RETURNED_SQLSTATE;
        RAISE WARNING 'Unexpected error [%]: %', v_sqlstate, v_err_msg;
        RETURN JSONB_BUILD_OBJECT('success', false, 'error', 'Internal error', 'code', v_sqlstate);
END;
$$ LANGUAGE plpgsql;

SELECT safe_transfer(1, 2, 50.00);
SELECT safe_transfer(1, 2, 999999.00);  -- insufficient funds
SELECT safe_transfer(1, 2, -10.00);     -- invalid amount

-- ═══════════════════════════════════════════════════════════════
-- PART 3: DOMAINS — custom types with built-in validation
-- ═══════════════════════════════════════════════════════════════

-- A domain is a named type with constraints
CREATE DOMAIN email_address AS VARCHAR(255)
    CHECK (VALUE ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

CREATE DOMAIN positive_money AS NUMERIC(15,2)
    CHECK (VALUE > 0);

CREATE DOMAIN us_zip AS CHAR(5)
    CHECK (VALUE ~ '^\d{5}$');

CREATE DOMAIN percentage AS NUMERIC(5,2)
    CHECK (VALUE BETWEEN 0 AND 100);

-- Use domains in tables
CREATE TABLE validated_contacts (
    id      SERIAL PRIMARY KEY,
    email   email_address NOT NULL,         -- validated by domain
    budget  positive_money,
    zip     us_zip,
    score   percentage
);

-- This works:
INSERT INTO validated_contacts (email, budget, zip, score)
VALUES ('user@example.com', 99.99, '10001', 85.5);

-- These fail domain constraints:
-- INSERT INTO validated_contacts (email) VALUES ('not-an-email');
-- INSERT INTO validated_contacts (email, budget) VALUES ('a@b.com', -10);
-- INSERT INTO validated_contacts (email, zip) VALUES ('a@b.com', 'ABCDE');

-- Alter domain constraint
ALTER DOMAIN positive_money ADD CONSTRAINT max_million CHECK (VALUE <= 1000000);
ALTER DOMAIN positive_money DROP CONSTRAINT max_million;

-- ═══════════════════════════════════════════════════════════════
-- PART 4: COMMON EXCEPTION NAMES
-- ═══════════════════════════════════════════════════════════════
-- unique_violation          (23505) — UNIQUE constraint failed
-- foreign_key_violation     (23503) — FK constraint failed
-- not_null_violation        (23502) — NOT NULL constraint failed
-- check_violation           (23514) — CHECK constraint failed
-- exclusion_violation       (23P01) — EXCLUSION constraint failed
-- division_by_zero          (22012)
-- numeric_value_out_of_range (22003)
-- deadlock_detected         (40P01)
-- serialization_failure     (40001)
-- no_data_found             (P0002) — SELECT INTO STRICT, no rows
-- too_many_rows             (P0003) — SELECT INTO STRICT, multiple rows

-- Catch specific constraint violation:
CREATE OR REPLACE FUNCTION safe_insert_user(p_email TEXT, p_username TEXT)
RETURNS TEXT AS $$
BEGIN
    INSERT INTO users (email, username, role) VALUES (p_email, p_username, 'customer');
    RETURN 'created';
EXCEPTION
    WHEN unique_violation THEN
        RETURN 'duplicate: ' || SQLERRM;
    WHEN check_violation THEN
        RETURN 'invalid data: ' || SQLERRM;
END;
$$ LANGUAGE plpgsql;

SELECT safe_insert_user('alice@example.com', 'alice_dup');  -- duplicate
SELECT safe_insert_user('new99@example.com', 'new99');      -- success
