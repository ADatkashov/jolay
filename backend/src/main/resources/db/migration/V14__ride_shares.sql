-- Trip sharing: a customer can share a live, read-only view of an active ride with anyone (family, friends) through an unguessable link.
-- The public view exposes no phone numbers or fares, and stops showing the driver's position once the ride is over.
CREATE TABLE ride_shares (
    token      VARCHAR(48) PRIMARY KEY,
    ride_id    UUID NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX ux_ride_shares_active ON ride_shares(ride_id) WHERE revoked_at IS NULL;
INSERT INTO application_settings(key,value,description) VALUES
('safety.share_grace_minutes','60','How long a shared trip link keeps showing the final status after the ride ends');
