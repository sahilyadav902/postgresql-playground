-- Seed data loaded on startup (idempotent)
INSERT INTO categories (name) VALUES ('Electronics') ON CONFLICT (name) DO NOTHING;
INSERT INTO categories (name) VALUES ('Books')       ON CONFLICT (name) DO NOTHING;
INSERT INTO categories (name) VALUES ('Clothing')    ON CONFLICT (name) DO NOTHING;
