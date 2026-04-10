INSERT INTO categories (name) VALUES ('Electronics'), ('Books'), ('Clothing');
INSERT INTO users (email, username, display_name, role) VALUES
    ('alice@example.com', 'alice', 'Alice Smith', 'customer'),
    ('bob@example.com',   'bob',   'Bob Jones',   'vendor');
INSERT INTO products (sku, name, price, stock, category_id) VALUES
    ('SKU-001', 'iPhone 15', 999.99, 50, 1),
    ('SKU-002', 'Clean Code', 39.99, 100, 2);
INSERT INTO orders (user_id, status, total) VALUES (1, 'pending', 999.99);
INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES (1, 1, 1, 999.99);
INSERT INTO blog_posts (title, body, author, published) VALUES
    ('PostgreSQL Performance', 'Tips for optimizing PostgreSQL queries and indexes', 'Alice', TRUE),
    ('Vector Databases', 'Introduction to vector similarity search and embeddings', 'Bob', TRUE);
