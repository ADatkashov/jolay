-- Peak-hour pricing: recurring weekly time windows (in the city's local time) during which fares are multiplied.
-- The multiplier in force when a ride is requested is stored on the ride (surge_multiplier) and used for its final fare, so the
-- rider is never charged a different multiplier than the one shown in the estimate. The effective multiplier is
-- max(pricing_rules.demand_multiplier, highest matching active window). No windows are seeded: the owner defines them in Admin.
CREATE TABLE peak_windows (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    city_id    UUID NOT NULL REFERENCES cities(id),
    label      VARCHAR(60) NOT NULL,
    days       SMALLINT[] NOT NULL CHECK (cardinality(days) BETWEEN 1 AND 7 AND days <@ ARRAY[1,2,3,4,5,6,7]::smallint[]),   -- ISO weekdays, 1 = Monday
    start_time TIME NOT NULL,
    end_time   TIME NOT NULL CHECK (end_time <> start_time),                                                              -- end < start means the window crosses midnight
    multiplier NUMERIC(4,2) NOT NULL CHECK (multiplier >= 1 AND multiplier <= 3),
    active     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE rides ADD COLUMN surge_multiplier NUMERIC(4,2) NOT NULL DEFAULT 1.00 CHECK (surge_multiplier >= 1);
