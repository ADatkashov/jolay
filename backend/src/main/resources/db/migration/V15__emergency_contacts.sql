-- Emergency contacts: people a customer trusts. When the customer presses SOS during a ride, each contact receives an SMS with a live trip link.
CREATE TABLE emergency_contacts (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name       VARCHAR(80) NOT NULL,
    phone      VARCHAR(20) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, phone)
);
