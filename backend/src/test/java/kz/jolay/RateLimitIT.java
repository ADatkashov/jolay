package kz.jolay;

import org.junit.jupiter.api.Test;
import org.springframework.test.context.TestPropertySource;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

@TestPropertySource(properties = {"jolay.ratelimit.auth-per-minute=6", "jolay.ratelimit.api-per-minute=100000"})
class RateLimitIT extends IntegrationTestBase {
    @Test
    void authEndpointsAreRateLimitedPerClient() {
        int limited = 0;
        for (int i = 0; i < 12; i++) {
            Resp r = post("/api/v1/auth/login", null, Map.of("identifier", "+77019990000", "password", "Wrong1234"));
            if (r.status() == 429 && "rate_limited".equals(r.s("code"))) limited++;   // (login_locked is the separate per-account lockout)
        }
        assertTrue(limited >= 5, "requests beyond the window must be rejected, got " + limited);
    }
}
