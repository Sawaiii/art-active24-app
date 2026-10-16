-- Собственные таблицы мобильного приложения. Таблицы CMS не изменяются.
-- Время везде UTC, формат 'Y-m-d H:i:s'.

CREATE TABLE IF NOT EXISTS app_users (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    phone VARCHAR(16) NOT NULL,
    name VARCHAR(100) NULL,
    email VARCHAR(150) NULL,
    company VARCHAR(150) NULL,
    role VARCHAR(16) NOT NULL DEFAULT 'customer',
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    UNIQUE KEY uq_app_users_phone (phone)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS app_auth_codes (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    phone VARCHAR(16) NOT NULL,
    code_hash CHAR(64) NOT NULL,
    attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
    expires_at DATETIME NOT NULL,
    used_at DATETIME NULL,
    ip VARCHAR(45) NULL,
    created_at DATETIME NOT NULL,
    KEY ix_app_auth_codes_phone (phone, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS app_sessions (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id INT UNSIGNED NOT NULL,
    access_hash CHAR(64) NOT NULL,
    access_expires_at DATETIME NOT NULL,
    refresh_hash CHAR(64) NOT NULL,
    refresh_expires_at DATETIME NOT NULL,
    user_agent VARCHAR(255) NULL,
    created_at DATETIME NOT NULL,
    last_used_at DATETIME NOT NULL,
    revoked_at DATETIME NULL,
    UNIQUE KEY uq_app_sessions_access (access_hash),
    UNIQUE KEY uq_app_sessions_refresh (refresh_hash),
    KEY ix_app_sessions_user (user_id),
    CONSTRAINT fk_app_sessions_user FOREIGN KEY (user_id) REFERENCES app_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS app_rate_limits (
    bucket VARCHAR(190) NOT NULL PRIMARY KEY,
    window_start DATETIME NOT NULL,
    hits INT UNSIGNED NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS app_orders (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id INT UNSIGNED NOT NULL,
    number VARCHAR(20) NULL,
    kind VARCHAR(16) NOT NULL,
    status VARCHAR(16) NOT NULL,
    event_date DATE NULL,
    event_date_to DATE NULL,
    delivery_method VARCHAR(16) NULL,
    delivery_address VARCHAR(300) NULL,
    contact_name VARCHAR(100) NULL,
    contact_phone VARCHAR(16) NOT NULL,
    comment TEXT NULL,
    subject VARCHAR(300) NULL,
    details_json TEXT NULL,
    total INT NOT NULL DEFAULT 0,
    has_on_request TINYINT(1) NOT NULL DEFAULT 0,
    idempotency_key VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    UNIQUE KEY uq_app_orders_number (number),
    UNIQUE KEY uq_app_orders_idem (user_id, idempotency_key),
    KEY ix_app_orders_user (user_id, created_at),
    KEY ix_app_orders_status (status, created_at),
    CONSTRAINT fk_app_orders_user FOREIGN KEY (user_id) REFERENCES app_users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS app_order_items (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_id INT UNSIGNED NOT NULL,
    position SMALLINT UNSIGNED NOT NULL,
    product_id INT UNSIGNED NOT NULL,
    product_name VARCHAR(300) NOT NULL,
    product_slug VARCHAR(190) NULL,
    image VARCHAR(500) NULL,
    art VARCHAR(20) NULL,
    complect_title VARCHAR(300) NULL,
    sub_title VARCHAR(300) NULL,
    time_label VARCHAR(20) NULL,
    qty INT UNSIGNED NOT NULL,
    qty_unit VARCHAR(30) NULL,
    unit_price INT NOT NULL,
    total INT NOT NULL,
    on_request TINYINT(1) NOT NULL DEFAULT 0,
    extras_json TEXT NULL,
    input_json TEXT NOT NULL,
    KEY ix_app_order_items_order (order_id, position),
    CONSTRAINT fk_app_order_items_order FOREIGN KEY (order_id) REFERENCES app_orders (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS app_order_status_log (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_id INT UNSIGNED NOT NULL,
    status VARCHAR(16) NOT NULL,
    comment TEXT NULL,
    actor_user_id INT UNSIGNED NULL,
    created_at DATETIME NOT NULL,
    KEY ix_app_order_status_log_order (order_id, id),
    CONSTRAINT fk_app_order_status_log_order FOREIGN KEY (order_id) REFERENCES app_orders (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS app_favorites (
    user_id INT UNSIGNED NOT NULL,
    product_id INT UNSIGNED NOT NULL,
    created_at DATETIME NOT NULL,
    PRIMARY KEY (user_id, product_id),
    CONSTRAINT fk_app_favorites_user FOREIGN KEY (user_id) REFERENCES app_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS app_carts (
    user_id INT UNSIGNED NOT NULL PRIMARY KEY,
    items_json MEDIUMTEXT NOT NULL,
    updated_at DATETIME NOT NULL,
    CONSTRAINT fk_app_carts_user FOREIGN KEY (user_id) REFERENCES app_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS app_devices (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id INT UNSIGNED NOT NULL,
    platform VARCHAR(10) NOT NULL,
    token VARCHAR(512) NOT NULL,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    UNIQUE KEY uq_app_devices_token (token(190)),
    KEY ix_app_devices_user (user_id),
    CONSTRAINT fk_app_devices_user FOREIGN KEY (user_id) REFERENCES app_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
