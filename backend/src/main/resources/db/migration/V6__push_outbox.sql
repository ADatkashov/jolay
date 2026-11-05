-- Development push mock: every push the platform WOULD send is recorded here (and nowhere else).
-- With real FCM credentials configured the FcmPushSender is used and this table stays empty.
CREATE TABLE push_outbox (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    push_token VARCHAR(300) NOT NULL,
    type VARCHAR(40) NOT NULL,
    title VARCHAR(200) NOT NULL,
    body VARCHAR(500) NOT NULL,
    data JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_push_outbox_user ON push_outbox(user_id, id DESC);
