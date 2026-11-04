-- Audit finding (measured, 40k upserts): logging driver positions generated 20.5 MB of WAL vs ~1 KB unlogged.
-- The table only holds the *latest* position per online driver. After a crash it is empty and drivers re-send within
-- seconds (dispatch ignores positions older than dispatch.location_max_age_seconds anyway). It is not replicated to standbys.
ALTER TABLE driver_locations SET UNLOGGED;
ALTER TABLE driver_locations SET (fillfactor = 70, autovacuum_vacuum_scale_factor = 0.02, autovacuum_analyze_scale_factor = 0.05, autovacuum_vacuum_cost_limit = 2000);
