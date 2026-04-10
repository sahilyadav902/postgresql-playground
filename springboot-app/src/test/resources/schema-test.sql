-- H2-compatible schema for tests
CREATE TABLE IF NOT EXISTS categories (
    id         BIGINT AUTO_INCREMENT PRIMARY KEY,
    name       VARCHAR(100) NOT NULL UNIQUE,
    parent_id  BIGINT REFERENCES categories(id) ON DELETE SET NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS users (
    id             BIGINT AUTO_INCREMENT PRIMARY KEY,
    email          VARCHAR(255) NOT NULL UNIQUE,
    username       VARCHAR(100) NOT NULL UNIQUE,
    display_name   VARCHAR(255),
    phone          VARCHAR(30),
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    role           VARCHAR(50) NOT NULL DEFAULT 'customer',
    loyalty_points INT NOT NULL DEFAULT 0,
    metadata       VARCHAR(2000),
    created_at     TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS products (
    id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    sku         VARCHAR(100) NOT NULL UNIQUE,
    name        VARCHAR(255) NOT NULL,
    description CLOB,
    price       DECIMAL(12,2) NOT NULL,
    stock       INT NOT NULL DEFAULT 0,
    category_id BIGINT REFERENCES categories(id) ON DELETE SET NULL,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS orders (
    id         BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id    BIGINT NOT NULL REFERENCES users(id),
    status     VARCHAR(50) NOT NULL DEFAULT 'pending',
    total      DECIMAL(12,2) NOT NULL DEFAULT 0,
    notes      CLOB,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS order_items (
    id         BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id   BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id BIGINT NOT NULL REFERENCES products(id),
    quantity   INT NOT NULL,
    unit_price DECIMAL(12,2) NOT NULL
);

CREATE TABLE IF NOT EXISTS blog_posts (
    id         BIGINT AUTO_INCREMENT PRIMARY KEY,
    title      VARCHAR(500) NOT NULL,
    body       CLOB NOT NULL,
    author     VARCHAR(100),
    published  BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS page_views (
    page        VARCHAR(500) NOT NULL,
    view_date   DATE NOT NULL DEFAULT CURRENT_DATE,
    view_count  BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (page, view_date)
);
