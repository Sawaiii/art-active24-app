-- Личный кабинет заказа: скидка постоянного клиента, связи с CRM / Вызов Чатом, состав из КП,
-- машина на карте, отзывы, претензии, документы. Та же схема, что migrations/mysql/002_order_cabinet.sql.

ALTER TABLE app_orders ADD COLUMN subtotal INTEGER NULL;
ALTER TABLE app_orders ADD COLUMN discount_percent INTEGER NOT NULL DEFAULT 0;
ALTER TABLE app_orders ADD COLUMN discount_amount INTEGER NOT NULL DEFAULT 0;
ALTER TABLE app_orders ADD COLUMN crm_deal_id TEXT NULL;
ALTER TABLE app_orders ADD COLUMN vyzovchat_event_id INTEGER NULL;

ALTER TABLE app_users ADD COLUMN loyalty_override_percent INTEGER NULL;
ALTER TABLE app_users ADD COLUMN loyalty_override_note TEXT NULL;

CREATE TABLE app_order_compositions (
    order_id INTEGER NOT NULL PRIMARY KEY REFERENCES app_orders (id) ON DELETE CASCADE,
    version INTEGER NOT NULL,
    payload_json TEXT NOT NULL,
    updated_by INTEGER NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE app_order_vehicles (
    order_id INTEGER NOT NULL PRIMARY KEY REFERENCES app_orders (id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    token_expires_at TEXT NOT NULL,
    driver_name TEXT NULL,
    vehicle_label TEXT NULL,
    tracker_device_id TEXT NULL,
    lat REAL NULL,
    lng REAL NULL,
    accuracy REAL NULL,
    heading REAL NULL,
    eta_minutes INTEGER NULL,
    arrived INTEGER NOT NULL DEFAULT 0,
    fix_at TEXT NULL,
    received_at TEXT NULL,
    rejected_count INTEGER NOT NULL DEFAULT 0,
    last_reject_reason TEXT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE app_order_reviews (
    order_id INTEGER NOT NULL PRIMARY KEY REFERENCES app_orders (id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL,
    rating INTEGER NOT NULL,
    text TEXT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    forwarded_at TEXT NULL
);

CREATE TABLE app_order_claims (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id INTEGER NOT NULL REFERENCES app_orders (id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL,
    category TEXT NOT NULL,
    description TEXT NOT NULL,
    contact_preference TEXT NOT NULL,
    photos_json TEXT NULL,
    status TEXT NOT NULL,
    manager_comment TEXT NULL,
    chat_url TEXT NULL,
    chat_app_url TEXT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX ix_app_order_claims_order ON app_order_claims (order_id, id);
CREATE INDEX ix_app_order_claims_status ON app_order_claims (status, id);

CREATE TABLE app_order_documents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id INTEGER NOT NULL REFERENCES app_orders (id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    kind TEXT NOT NULL,
    url TEXT NOT NULL,
    mime TEXT NULL,
    size INTEGER NULL,
    doc_date TEXT NULL,
    created_by INTEGER NULL,
    created_at TEXT NOT NULL
);
CREATE INDEX ix_app_order_documents_order ON app_order_documents (order_id, id);
