-- TOTP second factor for staff accounts. Secrets are stored AES-GCM encrypted (key derived from jolay.security.mfa-key, or the JWT secret when unset).
-- mfa_last_step stops a used code from being replayed inside its validity window. Recovery codes are stored hashed and are single-use.
ALTER TABLE users
    ADD COLUMN mfa_secret_enc VARCHAR(200),
    ADD COLUMN mfa_pending_enc VARCHAR(200),
    ADD COLUMN mfa_enabled_at TIMESTAMPTZ,
    ADD COLUMN mfa_last_step BIGINT NOT NULL DEFAULT 0;

CREATE TABLE mfa_recovery_codes (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code_hash CHAR(64) NOT NULL,
    used_at TIMESTAMPTZ,
    UNIQUE (user_id, code_hash)
);
