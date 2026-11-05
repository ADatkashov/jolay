package kz.jolay.rides;

import kz.jolay.common.AppSettings;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/** Deletes raw GPS points of finished rides after the retention window; the simplified route (rides.route_line) is kept. */
@Component
public class TrackRetentionJob {
    private static final Logger log = LoggerFactory.getLogger(TrackRetentionJob.class);
    private final JdbcClient jdbc;
    private final AppSettings settings;
    public TrackRetentionJob(JdbcClient jdbc, AppSettings settings) { this.jdbc = jdbc; this.settings = settings; }

    @Scheduled(cron = "0 30 3 * * *", zone = "Asia/Almaty")
    public int purge() {
        int days = settings.getInt("rides.raw_track_retention_days");
        int n = jdbc.sql("""
                DELETE FROM ride_locations l USING rides r
                WHERE r.id = l.ride_id AND r.status IN ('COMPLETED','CANCELLED','EXPIRED','FAILED')
                  AND COALESCE(r.completed_at, r.cancelled_at, r.updated_at) < now() - make_interval(days => :d)""").param("d", days).update();
        if (n > 0) log.info("purged {} raw GPS points older than {} days", n, days);
        return n;
    }
}
