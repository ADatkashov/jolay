package kz.jolay;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.BeforeEach;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.context.annotation.Import;
import org.springframework.http.*;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ActiveProfiles;

import java.math.BigDecimal;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("test")
@Import(TestConfig.class)
public abstract class IntegrationTestBase {
    @Autowired protected TestRestTemplate rest;
    @Autowired protected JdbcClient jdbc;
    @Autowired protected ObjectMapper mapper;
    @Autowired protected PasswordEncoder encoder;
    @Autowired protected Flyway flyway;
    @Autowired protected javax.sql.DataSource dataSource;
    @LocalServerPort protected int port;

    private static final AtomicInteger SEQ = new AtomicInteger(1000);
    // Almaty: Dostyk Plaza -> Mega Alma-Ata (~7 km straight line)
    protected static final double[] PICKUP = {43.2335, 76.9567};
    protected static final double[] DROPOFF = {43.2025, 76.9066};

    public record Session(UUID id, String token, String refresh, String phone) {}
    public record Resp(int status, JsonNode body) {
        public String s(String field) { return body.path(field).asText(null); }
    }

    private static volatile boolean migrated;

    @BeforeEach
    void cleanDb() {
        synchronized (IntegrationTestBase.class) {
            if (!migrated) { flyway.clean(); flyway.migrate(); migrated = true;
                // PostGIS was re-created: drop pooled connections holding stale type oids
                if (dataSource instanceof com.zaxxer.hikari.HikariDataSource h) h.getHikariPoolMXBean().softEvictConnections(); }
        }
        jdbc.sql("TRUNCATE users, cities_placeholder_never RESTART IDENTITY CASCADE".replace(", cities_placeholder_never", "")).update();
        jdbc.sql("TRUNCATE audit_logs, notifications RESTART IDENTITY CASCADE").update();
        jdbc.sql("INSERT INTO accounts(type) VALUES ('PLATFORM_REVENUE'),('EXTERNAL_CARD'),('EXTERNAL_CASH'),('PROMO')").update();
        jdbc.sql("UPDATE pricing_rules SET demand_multiplier=1.00, active=true").update();
        TestConfig.OTPS.clear();
    }

    // ---------- HTTP helpers ----------
    protected Resp call(HttpMethod m, String path, String token, Object body, Map<String, String> headers) {
        HttpHeaders h = new HttpHeaders();
        h.setContentType(MediaType.APPLICATION_JSON);
        if (token != null) h.setBearerAuth(token);
        if (headers != null) headers.forEach(h::add);
        try {
            String json = body == null ? null : body instanceof String s ? s : mapper.writeValueAsString(body);
            ResponseEntity<String> r = rest.exchange("http://localhost:" + port + path, m, new HttpEntity<>(json, h), String.class);
            JsonNode n = r.getBody() == null || r.getBody().isBlank() ? mapper.createObjectNode() : mapper.readTree(r.getBody());
            return new Resp(r.getStatusCode().value(), n);
        } catch (Exception e) { throw new RuntimeException(e); }
    }
    protected Resp get(String path, String token) { return call(HttpMethod.GET, path, token, null, null); }
    protected Resp post(String path, String token, Object body) { return call(HttpMethod.POST, path, token, body, null); }
    protected Resp put(String path, String token, Object body) { return call(HttpMethod.PUT, path, token, body, null); }

    // ---------- fixtures ----------
    protected String phone() { return "+7701" + String.format("%07d", SEQ.incrementAndGet()); }

    protected Session register(String role) {
        String phone = phone();
        Resp r = post("/api/v1/auth/register", null, Map.of("fullName", role + " Test", "phone", phone, "password", "Secret123", "role", role, "acceptTerms", true, "locale", "ru"));
        if (r.status() != 201) throw new IllegalStateException("register failed " + r.status() + " " + r.body());
        Resp v = post("/api/v1/auth/verify-otp", null, Map.of("phone", phone, "code", TestConfig.OTPS.get(phone)));
        if (v.status() != 200) throw new IllegalStateException("verify failed " + v.body());
        return new Session(UUID.fromString(v.body().path("user").path("id").asText()), v.s("accessToken"), v.s("refreshToken"), phone);
    }
    protected Session customer() { return register("CUSTOMER"); }

    protected Session admin(String role) {
        String phone = phone();
        UUID id = jdbc.sql("INSERT INTO users(phone,password_hash,full_name,phone_verified) VALUES (:p,:h,'Staff',true) RETURNING id").param("p", phone).param("h", encoder.encode("Secret123")).query(UUID.class).single();
        jdbc.sql("INSERT INTO user_roles(user_id,role) VALUES (:u,:r)").param("u", id).param("r", role).update();
        Resp l = post("/api/v1/auth/login", null, Map.of("identifier", phone, "password", "Secret123"));
        return new Session(id, l.s("accessToken"), l.s("refreshToken"), phone);
    }

    /** Registers a driver with a vehicle, approves it via the real admin API, and puts it online at the given point. */
    protected Session driver(String category, double lat, double lng) {
        Session d = register("DRIVER");
        Resp r = post("/api/v1/drivers/register", d.token(), Map.of("vehicle", Map.of("brand", "Toyota", "model", "Camry", "year", 2020, "color", "White", "plate", "A" + SEQ.incrementAndGet() + "KZ", "category", category)));
        if (r.status() != 201) throw new IllegalStateException("driver register " + r.body());
        Session adm = admin("OPERATIONS_ADMIN");
        Resp a = put("/api/v1/admin/drivers/" + d.id() + "/verification", adm.token(), Map.of("status", "APPROVED"));
        if (a.status() != 200) throw new IllegalStateException("approve " + a.body());
        goOnline(d, lat, lng);
        return d;
    }
    protected void goOnline(Session d, double lat, double lng) {
        Resp o = put("/api/v1/drivers/availability", d.token(), Map.of("online", true));
        if (o.status() != 200) throw new IllegalStateException("online " + o.body());
        moveDriver(d, lat, lng);
    }
    protected Resp moveDriver(Session d, double lat, double lng) {
        return post("/api/v1/drivers/location", d.token(), Map.of("point", Map.of("lat", lat, "lng", lng), "heading", 90, "speedKmh", 30));
    }

    protected Map<String, Object> rideRequest(String category, String payment) {
        return Map.of("pickup", Map.of("point", Map.of("lat", PICKUP[0], "lng", PICKUP[1]), "address", "Dostyk Plaza"),
                "dropoff", Map.of("point", Map.of("lat", DROPOFF[0], "lng", DROPOFF[1]), "address", "Mega Alma-Ata"), "category", category, "paymentMethod", payment);
    }

    protected Resp requestRide(Session c, String category, String payment) { return post("/api/v1/rides", c.token(), rideRequest(category, payment)); }

    protected String currentOfferId(Session d) {
        Resp o = get("/api/v1/drivers/offers", d.token());
        return o.status() == 200 && o.body().has("offer_id") ? o.s("offer_id") : null;
    }

    protected void topUp(Session c, int amount) {
        Resp t = post("/api/v1/wallet/top-ups", c.token(), Map.of("amount", amount));
        if (t.status() != 200) throw new IllegalStateException("topup " + t.body());
        Resp p = post("/api/v1/payments/" + t.s("id") + "/sandbox-checkout?success=true", c.token(), null);
        if (p.status() != 200) throw new IllegalStateException("sandbox " + p.body());
    }

    protected BigDecimal balance(Session s) { return new BigDecimal(get("/api/v1/wallet", s.token()).s("balance")); }

    /** Money invariant: every ledger transaction is balanced, so all account balances sum to exactly zero. */
    protected void assertLedgerBalanced() {
        BigDecimal sum = jdbc.sql("SELECT COALESCE(sum(balance),0) FROM accounts").query(BigDecimal.class).single();
        org.junit.jupiter.api.Assertions.assertEquals(0, sum.compareTo(BigDecimal.ZERO), "ledger imbalance: " + sum);
        Integer unbalanced = jdbc.sql("SELECT count(*) FROM (SELECT transaction_id FROM ledger_entries GROUP BY 1 HAVING sum(amount) <> 0) x").query(Integer.class).single();
        org.junit.jupiter.api.Assertions.assertEquals(0, unbalanced);
        Integer drift = jdbc.sql("SELECT count(*) FROM accounts a WHERE a.balance <> COALESCE((SELECT sum(amount) FROM ledger_entries e WHERE e.account_id=a.id),0)").query(Integer.class).single();
        org.junit.jupiter.api.Assertions.assertEquals(0, drift, "cached balance drifted from ledger");
    }
}
