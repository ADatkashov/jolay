-- A driver/courier who cancels after accepting too often within the window is skipped by dispatch until older cancellations age out.
-- No money is taken and no account is suspended: it only stops them from being offered new work (review flags stay advisory).
INSERT INTO application_settings(key,value,description) VALUES
('dispatch.cancel_cooldown_count','3','Cancellations after accepting (rides + deliveries) within the window after which a driver is not offered new work'),
('dispatch.cancel_cooldown_hours','24','Length of the cancellation window in hours'),
('risk.courier_cancels_24h','3','Flag a courier after this many cancellations after assignment in 24 h');
-- The dispatch candidate queries and the risk checks count these rows by actor, so index exactly those events.
CREATE INDEX ix_ride_hist_driver_cancel ON ride_status_history(actor, created_at) WHERE to_status = 'SEARCHING_DRIVER';
CREATE INDEX ix_delivery_hist_courier_cancel ON delivery_status_history(actor, created_at) WHERE to_status = 'SEARCHING_COURIER';
