-- Payouts are keyed by user (column driver_id is a users reference); the wallet the money is held in is now explicit,
-- so partners can request payouts from PARTNER_WALLET through the same ledger flow as drivers.
ALTER TABLE payouts ADD COLUMN wallet_type text NOT NULL DEFAULT 'DRIVER_WALLET' CHECK (wallet_type IN ('DRIVER_WALLET','PARTNER_WALLET'));
-- driver_id referenced drivers(user_id); partners are not drivers, so it now references users(id). Approval is checked in PayoutService.
ALTER TABLE payouts DROP CONSTRAINT payouts_driver_id_fkey;
ALTER TABLE payouts ADD CONSTRAINT payouts_user_id_fkey FOREIGN KEY (driver_id) REFERENCES users(id);
