-- ===== Payout accounts (hold + outflow) =====
ALTER TABLE accounts DROP CONSTRAINT accounts_type_check;
ALTER TABLE accounts ADD CONSTRAINT accounts_type_check CHECK (type IN
  ('CUSTOMER_WALLET','DRIVER_WALLET','PLATFORM_REVENUE','EXTERNAL_CARD','EXTERNAL_CASH','PROMO','PAYOUT_CLEARING','EXTERNAL_BANK'));
INSERT INTO accounts(type) VALUES ('PAYOUT_CLEARING'),('EXTERNAL_BANK');

ALTER TABLE payouts
  ADD COLUMN destination VARCHAR(60) NOT NULL DEFAULT '',
  ADD COLUMN reference VARCHAR(100),
  ADD COLUMN reviewed_by UUID REFERENCES users(id),
  ADD COLUMN reviewed_at TIMESTAMPTZ,
  ADD COLUMN note VARCHAR(300),
  ADD COLUMN hold_tx UUID REFERENCES ledger_transactions(id),
  ADD COLUMN final_tx UUID REFERENCES ledger_transactions(id);
ALTER TABLE payouts ALTER COLUMN destination DROP DEFAULT;
-- one open payout request per driver
CREATE UNIQUE INDEX ux_payout_one_open ON payouts(driver_id) WHERE status = 'REQUESTED';

-- ===== Incidents (SOS, complaints, accidents) with investigation history =====
CREATE TABLE incidents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type VARCHAR(12) NOT NULL CHECK (type IN ('SOS','COMPLAINT','ACCIDENT','OTHER')),
    severity VARCHAR(10) NOT NULL CHECK (severity IN ('LOW','HIGH','CRITICAL')),
    status VARCHAR(14) NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','ACKNOWLEDGED','RESOLVED')),
    reporter_id UUID NOT NULL REFERENCES users(id),
    subject_user_id UUID REFERENCES users(id),
    ride_id UUID REFERENCES rides(id),
    description VARCHAR(1000),
    location GEOGRAPHY(Point,4326),
    assigned_to UUID REFERENCES users(id),
    resolution VARCHAR(500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    acknowledged_at TIMESTAMPTZ,
    resolved_at TIMESTAMPTZ
);
CREATE INDEX ix_incidents_status ON incidents(status, severity, created_at DESC);
CREATE INDEX ix_incidents_reporter ON incidents(reporter_id, created_at DESC);
CREATE TABLE incident_events (
    id BIGSERIAL PRIMARY KEY,
    incident_id UUID NOT NULL REFERENCES incidents(id),
    actor_id UUID REFERENCES users(id),
    action VARCHAR(20) NOT NULL,
    note VARCHAR(500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_incident_events ON incident_events(incident_id, id);

-- ===== Risk flags (human review only; nothing is suspended automatically) =====
CREATE TABLE risk_events (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    kind VARCHAR(30) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_risk_events ON risk_events(user_id, kind, created_at DESC);
CREATE TABLE risk_flags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    ride_id UUID REFERENCES rides(id),
    rule VARCHAR(40) NOT NULL,
    severity VARCHAR(10) NOT NULL CHECK (severity IN ('LOW','MEDIUM','HIGH')),
    dedupe_key VARCHAR(80) NOT NULL,
    details JSONB NOT NULL DEFAULT '{}',
    status VARCHAR(12) NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','DISMISSED','CONFIRMED')),
    reviewed_by UUID REFERENCES users(id),
    reviewed_at TIMESTAMPTZ,
    review_note VARCHAR(300),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, rule, dedupe_key)
);
CREATE INDEX ix_risk_flags_status ON risk_flags(status, severity, created_at DESC);

-- ===== Legal documents: content is supplied by counsel and editable by SUPER_ADMIN; nothing is pre-filled =====
CREATE TABLE legal_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doc_type VARCHAR(12) NOT NULL CHECK (doc_type IN ('TERMS','PRIVACY','ABOUT')),
    locale VARCHAR(2) NOT NULL CHECK (locale IN ('kk','ru','en')),
    version INT NOT NULL,
    body TEXT NOT NULL CHECK (length(body) BETWEEN 1 AND 200000),
    published_by UUID REFERENCES users(id),
    published_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (doc_type, locale, version)
);

-- ===== Simplified route kept forever; raw GPS points are purged after the retention window =====
ALTER TABLE rides ADD COLUMN route_line GEOGRAPHY(LineString,4326);

INSERT INTO application_settings(key,value,description) VALUES
('payouts.min_amount','5000','Minimum driver payout request (KZT)'),
('rides.raw_track_retention_days','14','Raw GPS points of finished rides are deleted after this many days (simplified route is kept)'),
('risk.customer_cancels_24h','5','Flag a customer after this many own cancellations in 24 h'),
('risk.driver_cancels_24h','3','Flag a driver after this many cancellations after assignment in 24 h'),
('risk.gps_jumps_1h','3','Flag a driver after this many rejected GPS jumps in 1 h'),
('risk.pair_rides_24h','4','Flag the same customer-driver pair after this many completed rides in 24 h'),
('risk.device_accounts','3','Flag when one push device is shared by this many accounts'),
('risk.refunds_30d','3','Flag a customer after this many refunds in 30 days'),
('risk.duplicate_callbacks_24h','5','Flag a payer after this many replayed gateway callbacks in 24 h');
