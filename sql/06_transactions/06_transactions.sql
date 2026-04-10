-- =============================================================
-- 06_TRANSACTIONS.SQL — ACID, Isolation Levels, Savepoints,
--                        Advisory Locks, Atomic Operations
-- Scenario: Banking / Payment System
-- =============================================================

CREATE TABLE bank_accounts (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    owner       VARCHAR(100) NOT NULL,
    balance     NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
    version     INT NOT NULL DEFAULT 0,          -- optimistic locking version
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE transactions_log (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    from_acct   BIGINT REFERENCES bank_accounts(id),
    to_acct     BIGINT REFERENCES bank_accounts(id),
    amount      NUMERIC(15,2) NOT NULL CHECK (amount > 0),
    type        VARCHAR(20) NOT NULL CHECK (type IN ('transfer','deposit','withdrawal')),
    status      VARCHAR(20) NOT NULL DEFAULT 'completed',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO bank_accounts (owner, balance) VALUES ('Alice', 1000.00), ('Bob', 500.00);

-- ─── BASIC TRANSACTION ───────────────────────────────────────
-- ACID: Atomic (all or nothing), Consistent, Isolated, Durable
BEGIN;
    UPDATE bank_accounts SET balance = balance - 200, updated_at = NOW() WHERE id = 1;
    UPDATE bank_accounts SET balance = balance + 200, updated_at = NOW() WHERE id = 2;
    INSERT INTO transactions_log (from_acct, to_acct, amount, type)
    VALUES (1, 2, 200, 'transfer');
COMMIT;

-- ─── ROLLBACK ────────────────────────────────────────────────
BEGIN;
    UPDATE bank_accounts SET balance = balance - 9999 WHERE id = 1;
    -- Something went wrong, undo everything
ROLLBACK;

-- ─── SAVEPOINTS ──────────────────────────────────────────────
-- Partial rollback within a transaction
BEGIN;
    UPDATE bank_accounts SET balance = balance + 100 WHERE id = 1;
    SAVEPOINT after_deposit;

    UPDATE bank_accounts SET balance = balance - 50 WHERE id = 2;
    -- Oops, second update was wrong
    ROLLBACK TO SAVEPOINT after_deposit;

    -- First update still stands, only second was rolled back
    INSERT INTO transactions_log (to_acct, amount, type) VALUES (1, 100, 'deposit');
COMMIT;

-- ─── ISOLATION LEVELS ────────────────────────────────────────
-- READ COMMITTED (default): sees committed data at each statement
-- REPEATABLE READ: sees snapshot from start of transaction
-- SERIALIZABLE: full isolation, detects conflicts

-- Session 1: REPEATABLE READ example
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
    SELECT balance FROM bank_accounts WHERE id = 1;
    -- Even if another session commits a change here, we see the same value
    SELECT balance FROM bank_accounts WHERE id = 1;  -- same result
COMMIT;

-- Session 1: SERIALIZABLE — prevents phantom reads and write skew
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    SELECT SUM(balance) FROM bank_accounts;
    -- If another transaction modifies balances concurrently, this will FAIL with:
    -- ERROR: could not serialize access due to concurrent update
    UPDATE bank_accounts SET balance = balance * 1.01;  -- interest
COMMIT;

-- ─── OPTIMISTIC LOCKING (version column) ─────────────────────
-- No DB lock — check version hasn't changed before updating
BEGIN;
    -- Read current version
    -- App stores: id=1, version=0
    UPDATE bank_accounts
    SET balance = balance - 100, version = version + 1, updated_at = NOW()
    WHERE id = 1 AND version = 0;  -- fails if another transaction already updated

    -- Check rows affected: if 0, someone else updated first → retry
    GET DIAGNOSTICS -- (in PL/pgSQL: GET DIAGNOSTICS rows_affected = ROW_COUNT)
COMMIT;

-- ─── PESSIMISTIC LOCKING ─────────────────────────────────────
-- Lock rows for update — other transactions wait

-- SELECT FOR UPDATE: locks selected rows
BEGIN;
    SELECT * FROM bank_accounts WHERE id = 1 FOR UPDATE;
    -- Row is locked — other transactions block on this row
    UPDATE bank_accounts SET balance = balance - 100 WHERE id = 1;
COMMIT;

-- SELECT FOR UPDATE SKIP LOCKED: skip locked rows (job queue pattern)
BEGIN;
    SELECT * FROM bank_accounts
    WHERE balance > 0
    FOR UPDATE SKIP LOCKED
    LIMIT 1;
COMMIT;

-- SELECT FOR SHARE: allows other readers but blocks writers
BEGIN;
    SELECT * FROM bank_accounts WHERE id = 1 FOR SHARE;
COMMIT;

-- ─── TABLE-LEVEL LOCK ────────────────────────────────────────
BEGIN;
    LOCK TABLE bank_accounts IN EXCLUSIVE MODE;
    -- No other transaction can read or write
    UPDATE bank_accounts SET balance = 0;  -- dangerous!
COMMIT;

-- ─── ADVISORY LOCKS ──────────────────────────────────────────
-- Application-level locks using integer keys — not tied to rows/tables
-- Use case: distributed cron jobs, preventing duplicate processing

-- Session-level advisory lock (released on disconnect)
SELECT pg_try_advisory_lock(12345);     -- returns true if acquired
SELECT pg_advisory_unlock(12345);

-- Transaction-level advisory lock (released on COMMIT/ROLLBACK)
BEGIN;
    SELECT pg_advisory_xact_lock(42);   -- blocks until acquired
    -- Do exclusive work here
COMMIT;

-- ─── DEADLOCK DEMO ───────────────────────────────────────────
-- Session 1:                    Session 2:
-- BEGIN;                        BEGIN;
-- UPDATE accounts SET ... WHERE id=1;   UPDATE accounts SET ... WHERE id=2;
-- UPDATE accounts SET ... WHERE id=2;   UPDATE accounts SET ... WHERE id=1;
-- → PostgreSQL detects deadlock and kills one session with:
-- ERROR: deadlock detected

-- Prevention: always lock rows in the same order (by id ASC)

-- ─── MONITORING TRANSACTIONS ─────────────────────────────────
-- Active transactions
SELECT pid, state, query, now() - xact_start AS duration
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY duration DESC;

-- Locks held
SELECT pid, locktype, relation::regclass, mode, granted
FROM pg_locks
WHERE NOT granted;  -- waiting locks
