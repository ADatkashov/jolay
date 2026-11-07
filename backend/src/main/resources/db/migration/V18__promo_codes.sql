-- Promo codes: a discount on a ride that the PLATFORM pays for. The driver's earnings and the commission are calculated on the full fare;
-- the rider pays (total - discount) and the difference is booked from the PROMO account through the ledger (tx type BONUS), so every
-- discount is visible as a negative PROMO balance. No codes exist by default: the owner creates them in Admin.
CREATE TABLE promo_codes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code            VARCHAR(30) NOT NULL UNIQUE CHECK (code = upper(code)),
    description     VARCHAR(200),
    kind            VARCHAR(10) NOT NULL CHECK (kind IN ('PERCENT','FIXED')),
    value           NUMERIC(12,2) NOT NULL CHECK (value > 0),                    -- percent (1-100) or KZT amount
    max_discount    NUMERIC(12,2) CHECK (max_discount > 0),                       -- cap for PERCENT codes
    min_fare        NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (min_fare >= 0),
    starts_at       TIMESTAMPTZ,
    ends_at         TIMESTAMPTZ,
    max_redemptions INT CHECK (max_redemptions > 0),                              -- across all riders
    per_user_limit  INT NOT NULL DEFAULT 1 CHECK (per_user_limit > 0),
    first_ride_only BOOLEAN NOT NULL DEFAULT FALSE,
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (kind <> 'PERCENT' OR value <= 100)
);
-- RESERVED while the ride is open, APPLIED once it completes, RELEASED if it is cancelled/expired/failed (the use is given back).
CREATE TABLE promo_redemptions (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    promo_id   UUID NOT NULL REFERENCES promo_codes(id),
    user_id    UUID NOT NULL REFERENCES users(id),
    ride_id    UUID NOT NULL UNIQUE REFERENCES rides(id),
    status     VARCHAR(10) NOT NULL DEFAULT 'RESERVED' CHECK (status IN ('RESERVED','APPLIED','RELEASED')),
    discount   NUMERIC(12,2),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_promo_redemptions_promo ON promo_redemptions(promo_id, status);
CREATE INDEX ix_promo_redemptions_user ON promo_redemptions(user_id, promo_id, status);
ALTER TABLE rides ADD COLUMN promo_code VARCHAR(30), ADD COLUMN promo_est_discount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (promo_est_discount >= 0);
