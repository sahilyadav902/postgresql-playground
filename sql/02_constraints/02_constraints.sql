-- =============================================================
-- 02_CONSTRAINTS.SQL — Primary Keys, Foreign Keys, Cascading,
--                      Unique, Check, Not Null, Exclusion
-- Scenario: Hospital Management System
-- =============================================================

-- ─── SETUP ───────────────────────────────────────────────────
CREATE TABLE departments (
    id      SERIAL PRIMARY KEY,
    name    VARCHAR(100) NOT NULL UNIQUE,
    budget  NUMERIC(15,2) CHECK (budget >= 0)
);

CREATE TABLE doctors (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    license_no    VARCHAR(50) NOT NULL UNIQUE,       -- UNIQUE constraint
    full_name     VARCHAR(255) NOT NULL,
    speciality    VARCHAR(100) NOT NULL,
    department_id INT NOT NULL REFERENCES departments(id)
                      ON DELETE RESTRICT             -- cannot delete dept with doctors
                      ON UPDATE CASCADE,             -- if dept id changes, update here
    hired_at      DATE NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE patients (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    mrn         VARCHAR(50) NOT NULL UNIQUE,         -- Medical Record Number
    full_name   VARCHAR(255) NOT NULL,
    dob         DATE NOT NULL,
    blood_type  CHAR(3) CHECK (blood_type IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
    -- GENERATED column: age computed from dob, not ideal as age will have to be regenerated daily in db
    -- age         INT GENERATED ALWAYS AS (
    --                 DATE_PART('year', AGE(dob))::INT
    --             ) STORED
);

-- ─── COMPOSITE PRIMARY KEY ───────────────────────────────────
-- A patient can have multiple appointments, but not two at the same slot
CREATE TABLE appointments (
    patient_id  BIGINT NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    doctor_id   BIGINT NOT NULL REFERENCES doctors(id) ON DELETE CASCADE,
    slot_time   TIMESTAMPTZ NOT NULL,
    status      VARCHAR(20) NOT NULL DEFAULT 'scheduled'
                    CHECK (status IN ('scheduled','completed','cancelled')),
    notes       TEXT,
    PRIMARY KEY (patient_id, doctor_id, slot_time)  -- composite PK
);

-- ─── EXCLUSION CONSTRAINT (no overlapping room bookings) ─────
-- Requires btree_gist extension
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE room_bookings (
    id          SERIAL PRIMARY KEY,
    room_no     VARCHAR(20) NOT NULL,
    doctor_id   BIGINT NOT NULL REFERENCES doctors(id),
    during      TSTZRANGE NOT NULL,                 -- time range type
    -- EXCLUDE: same room cannot have overlapping time ranges
    EXCLUDE USING GIST (room_no WITH =, during WITH &&)
);

-- ─── DEFERRABLE CONSTRAINTS ──────────────────────────────────
-- Useful when you need to insert rows that reference each other
CREATE TABLE employees (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    manager_id  INT REFERENCES employees(id) DEFERRABLE INITIALLY DEFERRED
    -- manager_id can temporarily violate FK within a transaction
);

-- ─── CASCADING DEMO ──────────────────────────────────────────
-- ON DELETE CASCADE  → child rows deleted when parent deleted
-- ON DELETE RESTRICT → prevents parent deletion if children exist
-- ON DELETE SET NULL → child FK set to NULL when parent deleted
-- ON DELETE SET DEFAULT → child FK set to default when parent deleted
-- ON UPDATE CASCADE  → child FK updated when parent PK changes

-- ─── SEED DATA ───────────────────────────────────────────────
INSERT INTO departments (name, budget) VALUES ('Cardiology', 500000), ('Neurology', 750000);

INSERT INTO doctors (license_no, full_name, speciality, department_id)
VALUES ('LIC-001', 'Dr. Sarah Connor', 'Cardiologist', 1),
       ('LIC-002', 'Dr. John Doe',     'Neurologist',  2);

INSERT INTO patients (mrn, full_name, dob, blood_type)
VALUES ('MRN-001', 'Jane Roe', '1990-05-15', 'O+'),
       ('MRN-002', 'Mark Lee', '1985-11-20', 'A-');

INSERT INTO appointments (patient_id, doctor_id, slot_time, status)
VALUES (1, 1, '2025-01-15 09:00:00+00', 'scheduled'),
       (2, 2, '2025-01-15 10:00:00+00', 'scheduled');

-- ─── CONSTRAINT VIOLATION EXAMPLES (educational) ─────────────
-- These will FAIL — showing what constraints protect against:

-- FAIL: duplicate license
-- INSERT INTO doctors (license_no, full_name, speciality, department_id)
-- VALUES ('LIC-001', 'Fake Doctor', 'None', 1);

-- FAIL: invalid blood type
-- INSERT INTO patients (mrn, full_name, dob, blood_type)
-- VALUES ('MRN-003', 'Test', '2000-01-01', 'XY');

-- FAIL: delete department that has doctors (RESTRICT)
-- DELETE FROM departments WHERE id = 1;

-- FAIL: overlapping room booking
-- INSERT INTO room_bookings (room_no, doctor_id, during)
-- VALUES ('R101', 1, '[2025-01-15 09:00, 2025-01-15 10:00)');
-- INSERT INTO room_bookings (room_no, doctor_id, during)
-- VALUES ('R101', 2, '[2025-01-15 09:30, 2025-01-15 10:30)'); -- overlaps!

-- ─── VIEWING CONSTRAINTS ─────────────────────────────────────
SELECT conname, contype, conrelid::regclass
FROM pg_constraint
WHERE conrelid = 'doctors'::regclass;
