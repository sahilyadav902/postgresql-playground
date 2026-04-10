-- =============================================================
-- 14_SYSTEM_DESIGNS.SQL — Real-World System Design Scenarios
-- Each scenario: schema + queries + pitfalls + solutions
-- =============================================================

-- ═══════════════════════════════════════════════════════════════
-- SCENARIO 1: URL SHORTENER (like bit.ly)
-- Requirements: short code → long URL, click tracking, expiry
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE short_urls (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    short_code  VARCHAR(10) NOT NULL UNIQUE,
    long_url    TEXT NOT NULL,
    user_id     BIGINT,
    click_count BIGINT NOT NULL DEFAULT 0,
    expires_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE url_clicks (
    id          BIGINT GENERATED ALWAYS AS IDENTITY,
    short_code  VARCHAR(10) NOT NULL,
    ip_address  INET,
    user_agent  TEXT,
    referer     TEXT,
    clicked_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (clicked_at);

CREATE TABLE url_clicks_2025_01 PARTITION OF url_clicks
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

CREATE INDEX idx_short_urls_code ON short_urls (short_code);
CREATE INDEX idx_url_clicks_code ON url_clicks (short_code);

-- Atomic increment click count
UPDATE short_urls
SET click_count = click_count + 1
WHERE short_code = 'abc123' AND (expires_at IS NULL OR expires_at > NOW())
RETURNING long_url;

-- Pitfall: race condition on click_count → use atomic UPDATE (above) not SELECT then UPDATE
-- Solution: counter tables or approximate counting with pg_stat

-- ═══════════════════════════════════════════════════════════════
-- SCENARIO 2: RATE LIMITER (sliding window)
-- Requirements: limit API calls per user per time window
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE rate_limit_buckets (
    user_id     BIGINT NOT NULL,
    endpoint    VARCHAR(200) NOT NULL,
    window_start TIMESTAMPTZ NOT NULL,
    request_count INT NOT NULL DEFAULT 1,
    PRIMARY KEY (user_id, endpoint, window_start)
);

-- Check and increment rate limit (1-minute sliding window, max 100 req)
WITH window AS (
    SELECT DATE_TRUNC('minute', NOW()) AS current_window
),
upsert AS (
    INSERT INTO rate_limit_buckets (user_id, endpoint, window_start, request_count)
    SELECT 42, '/api/search', current_window, 1 FROM window
    ON CONFLICT (user_id, endpoint, window_start)
    DO UPDATE SET request_count = rate_limit_buckets.request_count + 1
    RETURNING request_count
)
SELECT request_count <= 100 AS allowed, request_count FROM upsert;

-- Cleanup old windows
DELETE FROM rate_limit_buckets WHERE window_start < NOW() - INTERVAL '5 minutes';

-- ═══════════════════════════════════════════════════════════════
-- SCENARIO 3: JOB QUEUE / TASK QUEUE
-- Requirements: reliable job processing, retry, dead letter queue
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE job_queue (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    queue_name  VARCHAR(100) NOT NULL DEFAULT 'default',
    payload     JSONB NOT NULL,
    status      VARCHAR(20) NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','processing','completed','failed','dead')),
    attempts    INT NOT NULL DEFAULT 0,
    max_attempts INT NOT NULL DEFAULT 3,
    scheduled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    locked_at   TIMESTAMPTZ,
    locked_by   VARCHAR(100),
    completed_at TIMESTAMPTZ,
    error       TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_job_queue_pickup ON job_queue (queue_name, scheduled_at)
WHERE status = 'pending';

-- Claim next job (atomic, skip locked = no blocking)
WITH claimed AS (
    SELECT id FROM job_queue
    WHERE queue_name = 'default'
      AND status = 'pending'
      AND scheduled_at <= NOW()
    ORDER BY scheduled_at
    LIMIT 1
    FOR UPDATE SKIP LOCKED
)
UPDATE job_queue
SET status = 'processing', locked_at = NOW(), locked_by = 'worker-1', attempts = attempts + 1
FROM claimed
WHERE job_queue.id = claimed.id
RETURNING job_queue.*;

-- Complete job
UPDATE job_queue SET status = 'completed', completed_at = NOW() WHERE id = 1;

-- Fail job (retry or dead letter)
UPDATE job_queue
SET status = CASE WHEN attempts >= max_attempts THEN 'dead' ELSE 'pending' END,
    error = 'Connection timeout',
    scheduled_at = NOW() + INTERVAL '5 minutes' * attempts  -- exponential backoff
WHERE id = 1;

-- ═══════════════════════════════════════════════════════════════
-- SCENARIO 4: LEADERBOARD (real-time ranking)
-- Requirements: score updates, rank queries, top-N
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE leaderboard (
    user_id     BIGINT PRIMARY KEY,
    username    VARCHAR(100) NOT NULL,
    score       BIGINT NOT NULL DEFAULT 0,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_leaderboard_score ON leaderboard (score DESC);

-- Upsert score (atomic add)
INSERT INTO leaderboard (user_id, username, score)
VALUES (1, 'alice', 100)
ON CONFLICT (user_id)
DO UPDATE SET score = leaderboard.score + EXCLUDED.score, updated_at = NOW();

-- Top 10 with rank
SELECT username, score,
       RANK() OVER (ORDER BY score DESC) AS rank
FROM leaderboard
ORDER BY score DESC
LIMIT 10;

-- User's rank (efficient — uses index)
SELECT rank FROM (
    SELECT user_id, RANK() OVER (ORDER BY score DESC) AS rank
    FROM leaderboard
) ranked
WHERE user_id = 42;

-- ═══════════════════════════════════════════════════════════════
-- SCENARIO 5: CHAT / MESSAGING SYSTEM
-- Requirements: conversations, messages, read receipts, unread count
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE conversations (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    type        VARCHAR(20) NOT NULL DEFAULT 'direct' CHECK (type IN ('direct','group')),
    name        VARCHAR(255),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE conversation_members (
    conversation_id BIGINT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id         BIGINT NOT NULL,
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_read_at    TIMESTAMPTZ,
    PRIMARY KEY (conversation_id, user_id)
);

CREATE TABLE messages (
    id              BIGINT GENERATED ALWAYS AS IDENTITY,
    conversation_id BIGINT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id       BIGINT NOT NULL,
    content         TEXT NOT NULL,
    sent_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (sent_at);

CREATE TABLE messages_2025_01 PARTITION OF messages
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

CREATE INDEX idx_messages_conv_sent ON messages (conversation_id, sent_at DESC);

-- Unread message count per conversation for a user
SELECT
    cm.conversation_id,
    COUNT(m.id) AS unread_count
FROM conversation_members cm
JOIN messages m ON m.conversation_id = cm.conversation_id
WHERE cm.user_id = 42
  AND m.sent_at > COALESCE(cm.last_read_at, '1970-01-01')
  AND m.sender_id != 42
GROUP BY cm.conversation_id;

-- Mark as read
UPDATE conversation_members
SET last_read_at = NOW()
WHERE conversation_id = 1 AND user_id = 42;

-- ═══════════════════════════════════════════════════════════════
-- SCENARIO 6: INVENTORY MANAGEMENT (prevent overselling)
-- Requirements: atomic stock deduction, reservation, rollback
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE inventory (
    product_id      BIGINT PRIMARY KEY REFERENCES products(id),
    total_stock     INT NOT NULL DEFAULT 0 CHECK (total_stock >= 0),
    reserved_stock  INT NOT NULL DEFAULT 0 CHECK (reserved_stock >= 0),
    -- available = total - reserved (computed)
    CONSTRAINT chk_reserved_lte_total CHECK (reserved_stock <= total_stock)
);

-- Reserve stock (atomic, prevents overselling)
UPDATE inventory
SET reserved_stock = reserved_stock + 2
WHERE product_id = 1
  AND (total_stock - reserved_stock) >= 2  -- enough available
RETURNING total_stock - reserved_stock AS remaining_available;
-- If 0 rows updated → out of stock

-- Confirm reservation (order placed)
UPDATE inventory
SET total_stock = total_stock - 2, reserved_stock = reserved_stock - 2
WHERE product_id = 1;

-- Cancel reservation
UPDATE inventory
SET reserved_stock = reserved_stock - 2
WHERE product_id = 1;
