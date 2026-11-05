-- ===== Partner marketplace: stores, catalog, orders with escrow, delivery leg =====
ALTER TABLE user_roles DROP CONSTRAINT user_roles_role_check;
ALTER TABLE user_roles ADD CONSTRAINT user_roles_role_check CHECK (role IN
  ('CUSTOMER','DRIVER','PARTNER','SUPER_ADMIN','OPERATIONS_ADMIN','FINANCE_ADMIN','SUPPORT_AGENT','PARTNER_ADMIN'));

ALTER TABLE accounts DROP CONSTRAINT accounts_type_check;
ALTER TABLE accounts ADD CONSTRAINT accounts_type_check CHECK (type IN
  ('CUSTOMER_WALLET','DRIVER_WALLET','PLATFORM_REVENUE','EXTERNAL_CARD','EXTERNAL_CASH','PROMO','PAYOUT_CLEARING','EXTERNAL_BANK','PARTNER_WALLET','ORDER_ESCROW'));
INSERT INTO accounts(type) VALUES ('ORDER_ESCROW');

CREATE TABLE partners (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID NOT NULL UNIQUE REFERENCES users(id),
    business_name VARCHAR(160) NOT NULL,
    legal_id VARCHAR(30),                         -- BIN/IIN; verified by operations, never trusted automatically
    status VARCHAR(12) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','APPROVED','SUSPENDED','REJECTED')),
    commission_rate NUMERIC(5,4) NOT NULL DEFAULT 0.1500 CHECK (commission_rate >= 0 AND commission_rate < 1),
    review_note VARCHAR(300),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE stores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    partner_id UUID NOT NULL REFERENCES partners(id),
    city_id UUID NOT NULL REFERENCES cities(id),
    name VARCHAR(160) NOT NULL,
    category VARCHAR(20) NOT NULL CHECK (category IN ('FOOD','GROCERY','PHARMACY','SHOP')),
    description VARCHAR(500),
    address VARCHAR(300) NOT NULL,
    location GEOGRAPHY(Point,4326) NOT NULL,
    phone VARCHAR(20),
    accepting_orders BOOLEAN NOT NULL DEFAULT TRUE,
    prep_minutes INT NOT NULL DEFAULT 20 CHECK (prep_minutes BETWEEN 1 AND 240),
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_stores_loc ON stores USING GIST (location);
CREATE INDEX ix_stores_partner ON stores(partner_id);

CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES stores(id),
    name VARCHAR(160) NOT NULL,
    description VARCHAR(500),
    section VARCHAR(60),
    price NUMERIC(12,2) NOT NULL CHECK (price > 0),
    available BOOLEAN NOT NULL DEFAULT TRUE,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_products_store ON products(store_id) WHERE deleted_at IS NULL;

CREATE TABLE store_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    number VARCHAR(10) NOT NULL UNIQUE,
    customer_id UUID NOT NULL REFERENCES users(id),
    store_id UUID NOT NULL REFERENCES stores(id),
    partner_id UUID NOT NULL REFERENCES partners(id),
    status VARCHAR(14) NOT NULL CHECK (status IN ('PLACED','ACCEPTED','READY','COMPLETED','REJECTED','CANCELLED','FAILED')),
    items_total NUMERIC(12,2) NOT NULL CHECK (items_total > 0),
    delivery_fee NUMERIC(12,2) NOT NULL CHECK (delivery_fee >= 0),
    partner_commission NUMERIC(12,2) NOT NULL CHECK (partner_commission >= 0),
    delivery_courier_earnings NUMERIC(12,2) NOT NULL CHECK (delivery_courier_earnings >= 0),
    delivery_platform_cut NUMERIC(12,2) NOT NULL CHECK (delivery_platform_cut >= 0),
    dropoff_address VARCHAR(300) NOT NULL,
    dropoff GEOGRAPHY(Point,4326) NOT NULL,
    recipient_name VARCHAR(120) NOT NULL,
    recipient_phone VARCHAR(20) NOT NULL,
    note VARCHAR(300),
    reject_reason VARCHAR(200),
    escrow_tx UUID REFERENCES ledger_transactions(id),
    idempotency_key VARCHAR(80),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    accepted_at TIMESTAMPTZ, ready_at TIMESTAMPTZ, completed_at TIMESTAMPTZ
);
CREATE INDEX ix_store_orders_customer ON store_orders(customer_id, created_at DESC);
CREATE INDEX ix_store_orders_store ON store_orders(store_id, created_at DESC);
CREATE INDEX ix_store_orders_status ON store_orders(status);
CREATE UNIQUE INDEX ux_store_orders_idem ON store_orders(customer_id, idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE TABLE store_order_items (
    id BIGSERIAL PRIMARY KEY,
    order_id UUID NOT NULL REFERENCES store_orders(id),
    product_id UUID NOT NULL REFERENCES products(id),
    name VARCHAR(160) NOT NULL,           -- snapshot: later menu edits never change past orders
    unit_price NUMERIC(12,2) NOT NULL,
    quantity INT NOT NULL CHECK (quantity BETWEEN 1 AND 50)
);
CREATE INDEX ix_store_order_items ON store_order_items(order_id);

-- delivery leg of a store order: pickup = store, prepaid from escrow, couriers paid at hand-over
ALTER TABLE delivery_orders ADD COLUMN store_order_id UUID REFERENCES store_orders(id);
ALTER TABLE delivery_orders DROP CONSTRAINT delivery_orders_payment_method_check;
ALTER TABLE delivery_orders ADD CONSTRAINT delivery_orders_payment_method_check CHECK (payment_method IN ('CASH','WALLET','PREPAID'));
CREATE UNIQUE INDEX ux_delivery_store_order ON delivery_orders(store_order_id) WHERE store_order_id IS NOT NULL;

INSERT INTO application_settings(key,value,description) VALUES
('marketplace.max_distance_m','8000','Maximum distance between a store and the customer'),
('marketplace.delivery_courier_share','0.80','Share of the delivery fee paid to the courier (the rest is platform revenue)'),
('marketplace.max_items','30','Maximum number of different lines in one order');

ALTER TABLE ledger_transactions DROP CONSTRAINT ledger_transactions_tx_type_check;
ALTER TABLE ledger_transactions ADD CONSTRAINT ledger_transactions_tx_type_check CHECK (tx_type IN
  ('TOPUP','RIDE_PAYMENT','CASH_COMMISSION','REFUND','BONUS','ADJUSTMENT','PAYOUT','CANCELLATION_FEE','ORDER_ESCROW','ORDER_SETTLEMENT','ORDER_REFUND'));
