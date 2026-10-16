-- Та же схема, что migrations/mysql/001_init.sql, для разработки и тестов (SQLite).

CREATE TABLE app_users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    phone TEXT NOT NULL UNIQUE,
    name TEXT NULL,
    email TEXT NULL,
    company TEXT NULL,
    role TEXT NOT NULL DEFAULT 'customer',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE app_auth_codes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    phone TEXT NOT NULL,
    code_hash TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    expires_at TEXT NOT NULL,
    used_at TEXT NULL,
    ip TEXT NULL,
    created_at TEXT NOT NULL
);
CREATE INDEX ix_app_auth_codes_phone ON app_auth_codes (phone, created_at);

CREATE TABLE app_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES app_users (id) ON DELETE CASCADE,
    access_hash TEXT NOT NULL UNIQUE,
    access_expires_at TEXT NOT NULL,
    refresh_hash TEXT NOT NULL UNIQUE,
    refresh_expires_at TEXT NOT NULL,
    user_agent TEXT NULL,
    created_at TEXT NOT NULL,
    last_used_at TEXT NOT NULL,
    revoked_at TEXT NULL
);
CREATE INDEX ix_app_sessions_user ON app_sessions (user_id);

CREATE TABLE app_rate_limits (
    bucket TEXT NOT NULL PRIMARY KEY,
    window_start TEXT NOT NULL,
    hits INTEGER NOT NULL
);

CREATE TABLE app_orders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES app_users (id),
    number TEXT NULL UNIQUE,
    kind TEXT NOT NULL,
    status TEXT NOT NULL,
    event_date TEXT NULL,
    event_date_to TEXT NULL,
    delivery_method TEXT NULL,
    delivery_address TEXT NULL,
    contact_name TEXT NULL,
    contact_phone TEXT NOT NULL,
    comment TEXT NULL,
    subject TEXT NULL,
    details_json TEXT NULL,
    total INTEGER NOT NULL DEFAULT 0,
    has_on_request INTEGER NOT NULL DEFAULT 0,
    idempotency_key TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE (user_id, idempotency_key)
);
CREATE INDEX ix_app_orders_user ON app_orders (user_id, created_at);
CREATE INDEX ix_app_orders_status ON app_orders (status, created_at);

CREATE TABLE app_order_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id INTEGER NOT NULL REFERENCES app_orders (id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    product_name TEXT NOT NULL,
    product_slug TEXT NULL,
    image TEXT NULL,
    art TEXT NULL,
    complect_title TEXT NULL,
    sub_title TEXT NULL,
    time_label TEXT NULL,
    qty INTEGER NOT NULL,
    qty_unit TEXT NULL,
    unit_price INTEGER NOT NULL,
    total INTEGER NOT NULL,
    on_request INTEGER NOT NULL DEFAULT 0,
    extras_json TEXT NULL,
    input_json TEXT NOT NULL
);
CREATE INDEX ix_app_order_items_order ON app_order_items (order_id, position);

CREATE TABLE app_order_status_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id INTEGER NOT NULL REFERENCES app_orders (id) ON DELETE CASCADE,
    status TEXT NOT NULL,
    comment TEXT NULL,
    actor_user_id INTEGER NULL,
    created_at TEXT NOT NULL
);
CREATE INDEX ix_app_order_status_log_order ON app_order_status_log (order_id, id);

CREATE TABLE app_favorites (
    user_id INTEGER NOT NULL REFERENCES app_users (id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY (user_id, product_id)
);

CREATE TABLE app_carts (
    user_id INTEGER NOT NULL PRIMARY KEY REFERENCES app_users (id) ON DELETE CASCADE,
    items_json TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE app_devices (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES app_users (id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    token TEXT NOT NULL UNIQUE,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX ix_app_devices_user ON app_devices (user_id);
