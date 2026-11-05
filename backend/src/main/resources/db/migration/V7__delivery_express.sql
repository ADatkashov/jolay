-- ===== JOLAY Express: parcel delivery =====
ALTER TABLE drivers ADD COLUMN accepts_delivery BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE delivery_tariffs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    city_id UUID NOT NULL REFERENCES cities(id),
    size_class VARCHAR(8) NOT NULL CHECK (size_class IN ('SMALL','MEDIUM','LARGE')),
    max_kg NUMERIC(5,1) NOT NULL CHECK (max_kg > 0),
    base_fare NUMERIC(12,2) NOT NULL CHECK (base_fare >= 0),
    per_km NUMERIC(12,2) NOT NULL CHECK (per_km >= 0),
    free_kg NUMERIC(5,1) NOT NULL DEFAULT 0 CHECK (free_kg >= 0),
    per_extra_kg NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (per_extra_kg >= 0),
    min_fare NUMERIC(12,2) NOT NULL CHECK (min_fare >= 0),
    commission_rate NUMERIC(5,4) NOT NULL CHECK (commission_rate >= 0 AND commission_rate < 1),
    rounding_step NUMERIC(8,2) NOT NULL DEFAULT 10 CHECK (rounding_step > 0),
    active BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE (city_id, size_class)
);
INSERT INTO delivery_tariffs(city_id,size_class,max_kg,base_fare,per_km,free_kg,per_extra_kg,min_fare,commission_rate)
SELECT c.id, v.sc, v.mx, v.base, v.km, v.free, v.extra, v.minfare, 0.15 FROM cities c, (VALUES
  ('SMALL', 2.0, 500, 90, 2.0, 0, 800),
  ('MEDIUM', 10.0, 700, 120, 2.0, 60, 1100),
  ('LARGE', 30.0, 1200, 170, 10.0, 80, 2000)) AS v(sc,mx,base,km,free,extra,minfare) WHERE c.code='ALA';

CREATE TABLE delivery_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tracking_number VARCHAR(12) NOT NULL UNIQUE,
    customer_id UUID NOT NULL REFERENCES users(id),
    courier_id UUID REFERENCES drivers(user_id),
    city_id UUID NOT NULL REFERENCES cities(id),
    status VARCHAR(18) NOT NULL CHECK (status IN ('SEARCHING_COURIER','COURIER_ASSIGNED','PICKED_UP','DELIVERED','CANCELLED','EXPIRED','FAILED')),
    size_class VARCHAR(8) NOT NULL CHECK (size_class IN ('SMALL','MEDIUM','LARGE')),
    weight_kg NUMERIC(5,1) NOT NULL CHECK (weight_kg > 0),
    parcel_description VARCHAR(300) NOT NULL,
    pickup_address VARCHAR(300) NOT NULL,
    pickup GEOGRAPHY(Point,4326) NOT NULL,
    dropoff_address VARCHAR(300) NOT NULL,
    dropoff GEOGRAPHY(Point,4326) NOT NULL,
    sender_name VARCHAR(120) NOT NULL, sender_phone VARCHAR(20) NOT NULL,
    recipient_name VARCHAR(120) NOT NULL, recipient_phone VARCHAR(20) NOT NULL,
    est_distance_m INT NOT NULL, est_duration_s INT NOT NULL,
    fee NUMERIC(12,2) NOT NULL CHECK (fee >= 0),
    commission NUMERIC(12,2) NOT NULL CHECK (commission >= 0),
    courier_earnings NUMERIC(12,2) NOT NULL CHECK (courier_earnings >= 0),
    payment_method VARCHAR(10) NOT NULL CHECK (payment_method IN ('CASH','WALLET')),
    payment_status VARCHAR(10) NOT NULL DEFAULT 'NONE' CHECK (payment_status IN ('NONE','PAID','FAILED')),
    handover_code VARCHAR(4) NOT NULL,
    idempotency_key VARCHAR(80),
    search_started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    assigned_at TIMESTAMPTZ, picked_up_at TIMESTAMPTZ, delivered_at TIMESTAMPTZ, cancelled_at TIMESTAMPTZ,
    cancelled_by VARCHAR(10) CHECK (cancelled_by IN ('CUSTOMER','COURIER','SYSTEM','ADMIN')),
    cancel_reason VARCHAR(200),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_deliveries_customer ON delivery_orders(customer_id, created_at DESC);
CREATE INDEX ix_deliveries_courier ON delivery_orders(courier_id, created_at DESC);
CREATE INDEX ix_deliveries_status ON delivery_orders(status);
CREATE UNIQUE INDEX ux_deliveries_courier_active ON delivery_orders(courier_id) WHERE courier_id IS NOT NULL AND status IN ('COURIER_ASSIGNED','PICKED_UP');
CREATE UNIQUE INDEX ux_deliveries_idem ON delivery_orders(customer_id, idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE TABLE delivery_status_history (
    id BIGSERIAL PRIMARY KEY, delivery_id UUID NOT NULL REFERENCES delivery_orders(id),
    from_status VARCHAR(18), to_status VARCHAR(18) NOT NULL, actor VARCHAR(60), created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_delivery_hist ON delivery_status_history(delivery_id);

CREATE TABLE delivery_offers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    delivery_id UUID NOT NULL REFERENCES delivery_orders(id),
    courier_id UUID NOT NULL REFERENCES drivers(user_id),
    status VARCHAR(12) NOT NULL CHECK (status IN ('OFFERED','ACCEPTED','DECLINED','EXPIRED','CANCELLED')),
    pickup_distance_m INT NOT NULL,
    expected_earnings NUMERIC(12,2) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    responded_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX ux_doffer_one_active_per_delivery ON delivery_offers(delivery_id) WHERE status = 'OFFERED';
CREATE UNIQUE INDEX ux_doffer_one_active_per_courier ON delivery_offers(courier_id) WHERE status = 'OFFERED';
CREATE INDEX ix_doffer_delivery ON delivery_offers(delivery_id);

-- wrong handover-code attempts live in their own table so they can be written in a separate transaction without touching the locked order row
CREATE TABLE delivery_code_attempts (
    delivery_id UUID PRIMARY KEY REFERENCES delivery_orders(id),
    attempts INT NOT NULL DEFAULT 0
);

CREATE TABLE delivery_ratings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    delivery_id UUID NOT NULL REFERENCES delivery_orders(id),
    from_user_id UUID NOT NULL REFERENCES users(id),
    to_user_id UUID NOT NULL REFERENCES users(id),
    stars INT NOT NULL CHECK (stars BETWEEN 1 AND 5),
    comment VARCHAR(500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (delivery_id, from_user_id)
);

-- ledger: courier earnings reuse tx types; add a dedicated reference type via ref_type text (no constraint change needed)
INSERT INTO application_settings(key,value,description) VALUES
('delivery.search_timeout_seconds','180','Time to find a courier before the order expires'),
('delivery.arrive_radius_m','300','Courier must be this close to the pickup / drop-off point to confirm it'),
('delivery.max_distance_m','25000','Maximum parcel route distance');
