-- Zone surcharges: a flat fee added to the fare when the pickup and/or the destination lies inside a circular zone (e.g. the airport, a distant suburb).
-- The surcharge is part of the fare (commission applies, like the booking fee), is shown in the fee line, and is stored on the ride when it is requested
-- (rides.zone_surcharge) so the final fare keeps the amount the rider was quoted. No zones are seeded.
CREATE TABLE tariff_zones (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    city_id     UUID NOT NULL REFERENCES cities(id),
    name        VARCHAR(80) NOT NULL,
    center      GEOGRAPHY(Point,4326) NOT NULL,
    radius_m    INT NOT NULL CHECK (radius_m BETWEEN 100 AND 50000),
    surcharge   NUMERIC(12,2) NOT NULL CHECK (surcharge > 0 AND surcharge <= 100000),
    applies_to  VARCHAR(10) NOT NULL DEFAULT 'EITHER' CHECK (applies_to IN ('PICKUP','DROPOFF','EITHER')),
    active      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_tariff_zones_city ON tariff_zones(city_id) WHERE active;
ALTER TABLE rides ADD COLUMN zone_surcharge NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (zone_surcharge >= 0);
