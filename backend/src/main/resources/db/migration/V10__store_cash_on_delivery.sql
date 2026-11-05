-- Cash on delivery for store orders: the customer pays the courier the full total at hand-over.
-- Nothing is held at placement; at hand-over the courier's wallet is debited by (total - courier earnings) and the partner/platform are credited,
-- exactly like cash rides (the courier owes the platform what they collected beyond their own earnings).
ALTER TABLE store_orders ADD COLUMN payment_method VARCHAR(6) NOT NULL DEFAULT 'WALLET' CHECK (payment_method IN ('WALLET','CASH'));
ALTER TABLE delivery_orders DROP CONSTRAINT delivery_orders_payment_method_check;
ALTER TABLE delivery_orders ADD CONSTRAINT delivery_orders_payment_method_check CHECK (payment_method IN ('CASH','WALLET','PREPAID','STORE_CASH'));
INSERT INTO application_settings(key,value,description) VALUES
('marketplace.cash_max_total','20000','Maximum total of a store order payable in cash on delivery (KZT)'),
('marketplace.cash_max_open','2','Maximum simultaneous open cash store orders per customer');
