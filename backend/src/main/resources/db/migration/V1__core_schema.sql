CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============ Identity ============
CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone         VARCHAR(20)  NOT NULL,
    email         VARCHAR(254),
    password_hash VARCHAR(100) NOT NULL,
    full_name     VARCHAR(120) NOT NULL,
    avatar_url    VARCHAR(500),
    locale        VARCHAR(5)   NOT NULL DEFAULT 'kk' CHECK (locale IN ('kk','ru','en')),
    status        VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','SUSPENDED','DELETED')),
    phone_verified BOOLEAN     NOT NULL DEFAULT FALSE,
    terms_accepted_at TIMESTAMPTZ,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at    TIMESTAMPTZ
);
CREATE UNIQUE INDEX ux_users_phone ON users(phone) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX ux_users_email ON users(lower(email)) WHERE email IS NOT NULL AND deleted_at IS NULL;

CREATE TABLE user_roles (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role    VARCHAR(30) NOT NULL CHECK (role IN ('CUSTOMER','DRIVER','SUPER_ADMIN','OPERATIONS_ADMIN','FINANCE_ADMIN','SUPPORT_AGENT','PARTNER_ADMIN')),
    PRIMARY KEY (user_id, role)
);

CREATE TABLE otp_verifications (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone       VARCHAR(20) NOT NULL,
    purpose     VARCHAR(20) NOT NULL CHECK (purpose IN ('REGISTER','RESET')),
    code_hash   VARCHAR(100) NOT NULL,
    attempts    INT NOT NULL DEFAULT 0,
    expires_at  TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_otp_phone_created ON otp_verifications(phone, created_at DESC);

CREATE TABLE refresh_tokens (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    family_id   UUID NOT NULL,
    token_hash  VARCHAR(64) NOT NULL UNIQUE,
    expires_at  TIMESTAMPTZ NOT NULL,
    revoked_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_refresh_user ON refresh_tokens(user_id);

CREATE TABLE user_devices (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    push_token VARCHAR(300) NOT NULL,
    platform   VARCHAR(10) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, push_token)
);

CREATE TABLE customer_addresses (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    label      VARCHAR(40) NOT NULL,
    address    VARCHAR(300) NOT NULL,
    location   GEOGRAPHY(Point,4326) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);
CREATE INDEX ix_addr_user ON customer_addresses(user_id) WHERE deleted_at IS NULL;

-- ============ Geography / catalog / pricing ============
CREATE TABLE cities (
    id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code     VARCHAR(20) NOT NULL UNIQUE,
    name_kk  VARCHAR(80) NOT NULL, name_ru VARCHAR(80) NOT NULL, name_en VARCHAR(80) NOT NULL,
    timezone VARCHAR(40) NOT NULL DEFAULT 'Asia/Almaty',
    currency CHAR(3) NOT NULL DEFAULT 'KZT',
    active   BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE service_zones (
    id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    city_id  UUID NOT NULL REFERENCES cities(id),
    name     VARCHAR(80) NOT NULL,
    boundary GEOGRAPHY(Polygon,4326) NOT NULL,
    active   BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE INDEX ix_zones_boundary ON service_zones USING GIST (boundary);

CREATE TABLE places (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    city_id UUID NOT NULL REFERENCES cities(id),
    name VARCHAR(160) NOT NULL, address VARCHAR(300) NOT NULL,
    location GEOGRAPHY(Point,4326) NOT NULL
);
CREATE INDEX ix_places_loc ON places USING GIST (location);

CREATE TABLE vehicle_categories (
    code      VARCHAR(20) PRIMARY KEY,
    rank      INT NOT NULL,
    name_kk   VARCHAR(60) NOT NULL, name_ru VARCHAR(60) NOT NULL, name_en VARCHAR(60) NOT NULL,
    desc_kk   VARCHAR(200) NOT NULL, desc_ru VARCHAR(200) NOT NULL, desc_en VARCHAR(200) NOT NULL,
    capacity  INT NOT NULL CHECK (capacity > 0),
    active    BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE pricing_rules (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    city_id          UUID NOT NULL REFERENCES cities(id),
    category_code    VARCHAR(20) NOT NULL REFERENCES vehicle_categories(code),
    base_fare        NUMERIC(12,2) NOT NULL CHECK (base_fare >= 0),
    per_km           NUMERIC(12,2) NOT NULL CHECK (per_km >= 0),
    per_minute       NUMERIC(12,2) NOT NULL CHECK (per_minute >= 0),
    min_fare         NUMERIC(12,2) NOT NULL CHECK (min_fare >= 0),
    booking_fee      NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (booking_fee >= 0),
    cancellation_fee NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (cancellation_fee >= 0),
    free_cancel_seconds INT NOT NULL DEFAULT 120,
    commission_rate  NUMERIC(5,4) NOT NULL CHECK (commission_rate >= 0 AND commission_rate < 1),
    demand_multiplier NUMERIC(4,2) NOT NULL DEFAULT 1.00 CHECK (demand_multiplier >= 1),
    rounding_step    NUMERIC(8,2) NOT NULL DEFAULT 10 CHECK (rounding_step > 0),
    active           BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (city_id, category_code)
);

CREATE TABLE application_settings (
    key VARCHAR(80) PRIMARY KEY,
    value VARCHAR(500) NOT NULL,
    description VARCHAR(300),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============ Drivers ============
CREATE TABLE drivers (
    user_id        UUID PRIMARY KEY REFERENCES users(id),
    city_id        UUID NOT NULL REFERENCES cities(id),
    verification   VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK (verification IN ('PENDING','APPROVED','REJECTED','SUSPENDED')),
    availability   VARCHAR(20) NOT NULL DEFAULT 'OFFLINE' CHECK (availability IN ('OFFLINE','ONLINE','OFFERED','BUSY','PAUSED','SUSPENDED')),
    rejection_reason VARCHAR(300),
    rating_avg     NUMERIC(3,2) NOT NULL DEFAULT 5.00,
    rating_count   INT NOT NULL DEFAULT 0,
    offers_total   INT NOT NULL DEFAULT 0,
    offers_accepted INT NOT NULL DEFAULT 0,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_drivers_avail ON drivers(availability, verification);

CREATE TABLE vehicles (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id     UUID NOT NULL REFERENCES drivers(user_id),
    brand         VARCHAR(60) NOT NULL, model VARCHAR(60) NOT NULL,
    year          INT NOT NULL CHECK (year BETWEEN 1990 AND 2100),
    color         VARCHAR(30) NOT NULL,
    plate         VARCHAR(15) NOT NULL UNIQUE,
    category_code VARCHAR(20) NOT NULL REFERENCES vehicle_categories(code),
    approved      BOOLEAN NOT NULL DEFAULT FALSE,
    active        BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_vehicles_driver ON vehicles(driver_id) WHERE active;

CREATE TABLE driver_documents (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id  UUID NOT NULL REFERENCES drivers(user_id),
    doc_type   VARCHAR(30) NOT NULL CHECK (doc_type IN ('ID_CARD','DRIVER_LICENSE','VEHICLE_REGISTRATION','INSURANCE','PHOTO')),
    storage_key VARCHAR(300) NOT NULL,
    content_type VARCHAR(60) NOT NULL,
    size_bytes BIGINT NOT NULL,
    status     VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','APPROVED','REJECTED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE driver_locations (
    driver_id  UUID PRIMARY KEY REFERENCES drivers(user_id),
    location   GEOGRAPHY(Point,4326) NOT NULL,
    heading    NUMERIC(5,1),
    speed_kmh  NUMERIC(5,1),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_driver_loc_gist ON driver_locations USING GIST (location);

CREATE TABLE driver_status_history (
    id BIGSERIAL PRIMARY KEY, driver_id UUID NOT NULL REFERENCES drivers(user_id),
    from_status VARCHAR(20), to_status VARCHAR(20) NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============ Rides ============
CREATE TABLE rides (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id    UUID NOT NULL REFERENCES users(id),
    driver_id      UUID REFERENCES drivers(user_id),
    vehicle_id     UUID REFERENCES vehicles(id),
    city_id        UUID NOT NULL REFERENCES cities(id),
    category_code  VARCHAR(20) NOT NULL REFERENCES vehicle_categories(code),
    status         VARCHAR(20) NOT NULL CHECK (status IN ('CREATED','SEARCHING_DRIVER','DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS','COMPLETED','CANCELLED','EXPIRED','FAILED')),
    pickup_address VARCHAR(300) NOT NULL,
    pickup         GEOGRAPHY(Point,4326) NOT NULL,
    dropoff_address VARCHAR(300) NOT NULL,
    dropoff        GEOGRAPHY(Point,4326) NOT NULL,
    est_distance_m INT NOT NULL CHECK (est_distance_m >= 0),
    est_duration_s INT NOT NULL CHECK (est_duration_s >= 0),
    est_fare       NUMERIC(12,2) NOT NULL CHECK (est_fare >= 0),
    final_fare     NUMERIC(12,2) CHECK (final_fare >= 0),
    actual_distance_m INT,
    actual_duration_s INT,
    payment_method VARCHAR(10) NOT NULL CHECK (payment_method IN ('CASH','CARD','WALLET')),
    payment_status VARCHAR(10) NOT NULL DEFAULT 'NONE' CHECK (payment_status IN ('NONE','PENDING','PAID','FAILED')),
    pricing_rule_id UUID REFERENCES pricing_rules(id),
    idempotency_key VARCHAR(80),
    search_started_at TIMESTAMPTZ,
    assigned_at TIMESTAMPTZ, arrived_at TIMESTAMPTZ, started_at TIMESTAMPTZ, completed_at TIMESTAMPTZ, cancelled_at TIMESTAMPTZ,
    cancelled_by VARCHAR(10) CHECK (cancelled_by IN ('CUSTOMER','DRIVER','SYSTEM','ADMIN')),
    cancel_reason VARCHAR(200),
    cancellation_fee NUMERIC(12,2) NOT NULL DEFAULT 0,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_rides_customer ON rides(customer_id, created_at DESC);
CREATE INDEX ix_rides_driver ON rides(driver_id, created_at DESC);
CREATE INDEX ix_rides_status ON rides(status);
CREATE INDEX ix_rides_created ON rides(created_at);
-- A customer can have only one non-terminal ride; a driver only one active ride.
CREATE UNIQUE INDEX ux_rides_customer_active ON rides(customer_id)
    WHERE status IN ('CREATED','SEARCHING_DRIVER','DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS');
CREATE UNIQUE INDEX ux_rides_driver_active ON rides(driver_id)
    WHERE driver_id IS NOT NULL AND status IN ('DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS');
CREATE UNIQUE INDEX ux_rides_idem ON rides(customer_id, idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE TABLE ride_status_history (
    id BIGSERIAL PRIMARY KEY, ride_id UUID NOT NULL REFERENCES rides(id),
    from_status VARCHAR(20), to_status VARCHAR(20) NOT NULL, actor VARCHAR(60), created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_ride_hist ON ride_status_history(ride_id);

CREATE TABLE ride_offers (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id    UUID NOT NULL REFERENCES rides(id),
    driver_id  UUID NOT NULL REFERENCES drivers(user_id),
    status     VARCHAR(12) NOT NULL CHECK (status IN ('OFFERED','ACCEPTED','DECLINED','EXPIRED','CANCELLED')),
    pickup_distance_m INT NOT NULL,
    eta_s      INT NOT NULL,
    expected_earnings NUMERIC(12,2) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    responded_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX ux_offer_one_active_per_ride ON ride_offers(ride_id) WHERE status = 'OFFERED';
CREATE UNIQUE INDEX ux_offer_one_active_per_driver ON ride_offers(driver_id) WHERE status = 'OFFERED';
CREATE INDEX ix_offer_ride ON ride_offers(ride_id);

CREATE TABLE ride_locations (
    id BIGSERIAL PRIMARY KEY, ride_id UUID NOT NULL REFERENCES rides(id),
    location GEOGRAPHY(Point,4326) NOT NULL, recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_ride_loc ON ride_locations(ride_id, id);

CREATE TABLE ride_fares (
    ride_id UUID PRIMARY KEY REFERENCES rides(id),
    base_fare NUMERIC(12,2) NOT NULL, distance_fare NUMERIC(12,2) NOT NULL, time_fare NUMERIC(12,2) NOT NULL,
    fees NUMERIC(12,2) NOT NULL, discount NUMERIC(12,2) NOT NULL DEFAULT 0,
    multiplier NUMERIC(4,2) NOT NULL, total NUMERIC(12,2) NOT NULL,
    commission_rate NUMERIC(5,4) NOT NULL, commission NUMERIC(12,2) NOT NULL, driver_earnings NUMERIC(12,2) NOT NULL
);

CREATE TABLE ratings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id UUID NOT NULL REFERENCES rides(id),
    from_user_id UUID NOT NULL REFERENCES users(id),
    to_user_id UUID NOT NULL REFERENCES users(id),
    stars INT NOT NULL CHECK (stars BETWEEN 1 AND 5),
    tags VARCHAR(200), comment VARCHAR(500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (ride_id, from_user_id)
);

-- ============ Wallet / ledger / payments ============
CREATE TABLE accounts (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type      VARCHAR(20) NOT NULL CHECK (type IN ('CUSTOMER_WALLET','DRIVER_WALLET','PLATFORM_REVENUE','EXTERNAL_CARD','EXTERNAL_CASH','PROMO')),
    owner_id  UUID REFERENCES users(id),
    currency  CHAR(3) NOT NULL DEFAULT 'KZT',
    balance   NUMERIC(14,2) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (type <> 'CUSTOMER_WALLET' OR balance >= 0)
);
CREATE UNIQUE INDEX ux_account_owner_type ON accounts(owner_id, type) WHERE owner_id IS NOT NULL;
CREATE UNIQUE INDEX ux_account_system ON accounts(type) WHERE owner_id IS NULL;

CREATE TABLE ledger_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tx_type VARCHAR(20) NOT NULL CHECK (tx_type IN ('TOPUP','RIDE_PAYMENT','CASH_COMMISSION','REFUND','BONUS','ADJUSTMENT','PAYOUT','CANCELLATION_FEE')),
    ref_type VARCHAR(20), ref_id UUID,
    idempotency_key VARCHAR(100) UNIQUE,
    description VARCHAR(200),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE ledger_entries (
    id BIGSERIAL PRIMARY KEY,
    transaction_id UUID NOT NULL REFERENCES ledger_transactions(id),
    account_id UUID NOT NULL REFERENCES accounts(id),
    amount NUMERIC(14,2) NOT NULL CHECK (amount <> 0),
    balance_after NUMERIC(14,2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_ledger_account ON ledger_entries(account_id, id DESC);
CREATE INDEX ix_ledger_tx ON ledger_entries(transaction_id);

-- Ledger is append-only.
CREATE FUNCTION forbid_ledger_mutation() RETURNS trigger AS $$
BEGIN RAISE EXCEPTION 'ledger is immutable'; END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_ledger_entries_immutable BEFORE UPDATE OR DELETE ON ledger_entries FOR EACH ROW EXECUTE FUNCTION forbid_ledger_mutation();
CREATE TRIGGER trg_ledger_tx_immutable BEFORE UPDATE OR DELETE ON ledger_transactions FOR EACH ROW EXECUTE FUNCTION forbid_ledger_mutation();

CREATE TABLE payment_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    purpose VARCHAR(10) NOT NULL CHECK (purpose IN ('RIDE','TOPUP')),
    ride_id UUID REFERENCES rides(id),
    provider VARCHAR(30) NOT NULL,
    amount NUMERIC(14,2) NOT NULL CHECK (amount > 0),
    currency CHAR(3) NOT NULL DEFAULT 'KZT',
    status VARCHAR(12) NOT NULL CHECK (status IN ('PENDING','SUCCEEDED','FAILED','REFUNDED')),
    provider_ref VARCHAR(100),
    idempotency_key VARCHAR(100),
    failure_reason VARCHAR(200),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX ux_pay_idem ON payment_transactions(user_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE UNIQUE INDEX ux_pay_provider_ref ON payment_transactions(provider, provider_ref) WHERE provider_ref IS NOT NULL;
CREATE UNIQUE INDEX ux_pay_one_pending_ride ON payment_transactions(ride_id) WHERE ride_id IS NOT NULL AND status IN ('PENDING','SUCCEEDED');

CREATE TABLE payment_webhook_events (
    provider VARCHAR(30) NOT NULL, event_id VARCHAR(100) NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (provider, event_id)
);

CREATE TABLE payment_refunds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id UUID NOT NULL REFERENCES payment_transactions(id),
    amount NUMERIC(14,2) NOT NULL CHECK (amount > 0),
    reason VARCHAR(200) NOT NULL,
    requested_by UUID NOT NULL REFERENCES users(id),
    ledger_transaction_id UUID REFERENCES ledger_transactions(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (payment_id)
);

CREATE TABLE payouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id UUID NOT NULL REFERENCES drivers(user_id),
    amount NUMERIC(14,2) NOT NULL CHECK (amount > 0),
    status VARCHAR(12) NOT NULL DEFAULT 'REQUESTED' CHECK (status IN ('REQUESTED','PAID','REJECTED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============ Support / notifications / audit ============
CREATE TABLE support_tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    category VARCHAR(20) NOT NULL CHECK (category IN ('PAYMENT','RIDE','DELIVERY','SAFETY','OTHER')),
    subject VARCHAR(160) NOT NULL,
    ride_id UUID REFERENCES rides(id),
    status VARCHAR(12) NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','PENDING','RESOLVED','CLOSED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_tickets_user ON support_tickets(user_id, updated_at DESC);
CREATE TABLE support_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID NOT NULL REFERENCES support_tickets(id),
    sender_id UUID NOT NULL REFERENCES users(id),
    from_agent BOOLEAN NOT NULL DEFAULT FALSE,
    body VARCHAR(2000) NOT NULL,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_msgs_ticket ON support_messages(ticket_id, created_at);

CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    type VARCHAR(40) NOT NULL, dedupe_key VARCHAR(120) NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}',
    read_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, dedupe_key)
);
CREATE INDEX ix_notif_user ON notifications(user_id, created_at DESC);

CREATE TABLE audit_logs (
    id BIGSERIAL PRIMARY KEY,
    actor_id UUID, actor_role VARCHAR(30),
    action VARCHAR(60) NOT NULL, entity_type VARCHAR(40), entity_id VARCHAR(60),
    details JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_audit_created ON audit_logs(created_at DESC);
