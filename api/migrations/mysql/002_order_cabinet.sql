-- Личный кабинет заказа: скидка постоянного клиента, связи с CRM / Вызов Чатом, состав из КП,
-- машина на карте, отзывы, претензии, документы.

ALTER TABLE app_orders
    ADD COLUMN subtotal INT NULL,
    ADD COLUMN discount_percent TINYINT UNSIGNED NOT NULL DEFAULT 0,
    ADD COLUMN discount_amount INT NOT NULL DEFAULT 0,
    ADD COLUMN crm_deal_id VARCHAR(50) NULL,
    ADD COLUMN vyzovchat_event_id BIGINT UNSIGNED NULL;

ALTER TABLE app_users
    ADD COLUMN loyalty_override_percent TINYINT UNSIGNED NULL,
    ADD COLUMN loyalty_override_note VARCHAR(200) NULL;

CREATE TABLE IF NOT EXISTS app_order_compositions (
    order_id INT UNSIGNED NOT NULL PRIMARY KEY,
    version INT UNSIGNED NOT NULL,
    payload_json MEDIUMTEXT NOT NULL,
    updated_by INT UNSIGNED NULL,
    updated_at DATETIME NOT NULL,
    CONSTRAINT fk_app_order_compositions_order FOREIGN KEY (order_id) REFERENCES app_orders (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS app_order_vehicles (
    order_id INT UNSIGNED NOT NULL PRIMARY KEY,
    token_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    token_expires_at DATETIME NOT NULL,
    driver_name VARCHAR(100) NULL,
    vehicle_label VARCHAR(100) NULL,
    tracker_device_id VARCHAR(64) NULL,
    lat DOUBLE NULL,
    lng DOUBLE NULL,
    accuracy DOUBLE NULL,
    heading DOUBLE NULL,
    eta_minutes SMALLINT UNSIGNED NULL,
    arrived TINYINT(1) NOT NULL DEFAULT 0,
    fix_at DATETIME NULL,
    received_at DATETIME NULL,
    rejected_count INT UNSIGNED NOT NULL DEFAULT 0,
    last_reject_reason VARCHAR(32) NULL,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    UNIQUE KEY uq_app_order_vehicles_token (token_hash),
    CONSTRAINT fk_app_order_vehicles_order FOREIGN KEY (order_id) REFERENCES app_orders (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS app_order_reviews (
    order_id INT UNSIGNED NOT NULL PRIMARY KEY,
    user_id INT UNSIGNED NOT NULL,
    rating TINYINT UNSIGNED NOT NULL,
    text TEXT NULL,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    forwarded_at DATETIME NULL,
    CONSTRAINT fk_app_order_reviews_order FOREIGN KEY (order_id) REFERENCES app_orders (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS app_order_claims (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_id INT UNSIGNED NOT NULL,
    user_id INT UNSIGNED NOT NULL,
    category VARCHAR(16) NOT NULL,
    description TEXT NOT NULL,
    contact_preference VARCHAR(16) NOT NULL,
    photos_json TEXT NULL,
    status VARCHAR(16) NOT NULL,
    manager_comment TEXT NULL,
    chat_url VARCHAR(500) NULL,
    chat_app_url VARCHAR(500) NULL,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    KEY ix_app_order_claims_order (order_id, id),
    KEY ix_app_order_claims_status (status, id),
    CONSTRAINT fk_app_order_claims_order FOREIGN KEY (order_id) REFERENCES app_orders (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS app_order_documents (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_id INT UNSIGNED NOT NULL,
    title VARCHAR(200) NOT NULL,
    kind VARCHAR(16) NOT NULL,
    url VARCHAR(1000) NOT NULL,
    mime VARCHAR(100) NULL,
    size BIGINT UNSIGNED NULL,
    doc_date DATE NULL,
    created_by INT UNSIGNED NULL,
    created_at DATETIME NOT NULL,
    KEY ix_app_order_documents_order (order_id, id),
    CONSTRAINT fk_app_order_documents_order FOREIGN KEY (order_id) REFERENCES app_orders (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
