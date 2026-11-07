-- Referral programme: a customer invites friends with a personal code; when the invited customer completes their first paid ride of at least
-- the minimum fare, both receive a wallet bonus. The money moves PROMO -> wallets through the ledger (tx_type BONUS), once per invited user.
-- The programme is OFF by default (referral.enabled=false): the owner decides when and how much promo budget to spend.
ALTER TABLE users ADD COLUMN referral_code VARCHAR(10) UNIQUE, ADD COLUMN referred_by UUID REFERENCES users(id);
CREATE TABLE referral_rewards (
    referee_id  UUID PRIMARY KEY REFERENCES users(id),
    referrer_id UUID NOT NULL REFERENCES users(id),
    ride_id     UUID NOT NULL REFERENCES rides(id),
    referrer_amount NUMERIC(12,2) NOT NULL,
    referee_amount  NUMERIC(12,2) NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_referral_rewards_referrer ON referral_rewards(referrer_id);
INSERT INTO application_settings(key,value,description) VALUES
('referral.enabled','false','Turn the referral programme on (true/false)'),
('referral.referrer_bonus','1000','Wallet bonus (KZT) paid to the inviting customer'),
('referral.referee_bonus','1000','Wallet bonus (KZT) paid to the invited customer'),
('referral.min_fare','1500','Minimum final fare (KZT) of the invited customer''s first completed ride for the bonus to be paid'),
('referral.max_rewards_per_referrer','20','Maximum number of rewarded invitations per customer');
