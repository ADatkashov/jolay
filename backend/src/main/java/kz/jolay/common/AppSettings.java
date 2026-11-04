package kz.jolay.common;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;

/** Typed access to the application_settings table (admin-configurable business parameters). */
@Component
public class AppSettings {
    private final JdbcClient jdbc;
    public AppSettings(JdbcClient jdbc) { this.jdbc = jdbc; }

    public String get(String key) {
        return jdbc.sql("SELECT value FROM application_settings WHERE key=:k").param("k", key)
                .query(String.class).optional()
                .orElseThrow(() -> new IllegalStateException("Missing setting " + key));
    }
    public int getInt(String key) { return Integer.parseInt(get(key)); }
    public BigDecimal getDecimal(String key) { return new BigDecimal(get(key)); }
}
