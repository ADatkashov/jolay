package kz.jolay;

import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class AuthSecurityIT extends IntegrationTestBase {

    @Test
    void registrationValidationAndPolicies() {
        assertEquals(400, post("/api/v1/auth/register", null, Map.of("fullName", "A", "phone", "+77011110000", "password", "Secret123", "role", "CUSTOMER", "acceptTerms", true)).status());
        assertEquals(400, post("/api/v1/auth/register", null, Map.of("fullName", "Aidar B", "phone", "123", "password", "Secret123", "role", "CUSTOMER", "acceptTerms", true)).status());
        Resp weak = post("/api/v1/auth/register", null, Map.of("fullName", "Aidar B", "phone", "+77011110000", "password", "onlyletters", "role", "CUSTOMER", "acceptTerms", true));
        assertEquals("weak_password", weak.s("code"));
        assertEquals(400, post("/api/v1/auth/register", null, Map.of("fullName", "Aidar B", "phone", "+77011110000", "password", "Secret123", "role", "CUSTOMER", "acceptTerms", false)).status());
        assertEquals(400, post("/api/v1/auth/register", null, Map.of("fullName", "Aidar B", "phone", "+77011110000", "password", "Secret123", "role", "SUPER_ADMIN", "acceptTerms", true)).status(), "self-service admin role must be impossible");
        // national format 8XXXXXXXXXX is normalised
        assertEquals("+77012223344", post("/api/v1/auth/register", null, Map.of("fullName", "Aidar B", "phone", "8 (701) 222-33-44", "password", "Secret123", "role", "CUSTOMER", "acceptTerms", true)).s("phone"));
    }

    @Test
    void duplicatePhoneRejectedAfterVerificationAndLoginRequiresVerification() {
        Session s = customer();
        assertEquals(409, post("/api/v1/auth/register", null, Map.of("fullName", "Dup", "phone", s.phone(), "password", "Secret123", "role", "CUSTOMER", "acceptTerms", true)).status());
        String p = phone();
        post("/api/v1/auth/register", null, Map.of("fullName", "Unverified", "phone", p, "password", "Secret123", "role", "CUSTOMER", "acceptTerms", true));
        Resp l = post("/api/v1/auth/login", null, Map.of("identifier", p, "password", "Secret123"));
        assertEquals(403, l.status());
        assertEquals("phone_not_verified", l.s("code"));
    }

    @Test
    void otpAttemptLimitInvalidCodeAndSingleUse() {
        String p = phone();
        post("/api/v1/auth/register", null, Map.of("fullName", "Otp User", "phone", p, "password", "Secret123", "role", "CUSTOMER", "acceptTerms", true));
        String good = TestConfig.OTPS.get(p);
        String bad = good.equals("000000") ? "111111" : "000000";
        for (int i = 0; i < 5; i++) assertEquals("otp_invalid", post("/api/v1/auth/verify-otp", null, Map.of("phone", p, "code", bad)).s("code"));
        Resp locked = post("/api/v1/auth/verify-otp", null, Map.of("phone", p, "code", good));      // even the right code is dead after 5 failures
        assertEquals(429, locked.status());
        // a new code works once
        jdbc.sql("UPDATE otp_verifications SET created_at = now() - interval '2 minutes'").update();
        post("/api/v1/auth/resend-otp", null, Map.of("phone", p));
        String fresh = TestConfig.OTPS.get(p);
        assertEquals(200, post("/api/v1/auth/verify-otp", null, Map.of("phone", p, "code", fresh)).status());
        assertEquals(400, post("/api/v1/auth/verify-otp", null, Map.of("phone", p, "code", fresh)).status(), "OTP is single-use");
    }

    @Test
    void loginThrottlingLocksAfterRepeatedFailures() {
        Session s = customer();
        for (int i = 0; i < 5; i++) assertEquals(401, post("/api/v1/auth/login", null, Map.of("identifier", s.phone(), "password", "Wrong1234")).status());
        assertEquals(429, post("/api/v1/auth/login", null, Map.of("identifier", s.phone(), "password", "Secret123")).status());
    }

    @Test
    void refreshTokenRotationAndReuseDetection() {
        Session s = customer();
        Resp r1 = post("/api/v1/auth/refresh", null, Map.of("refreshToken", s.refresh()));
        assertEquals(200, r1.status());
        assertNotEquals(s.refresh(), r1.s("refreshToken"));
        Resp reuse = post("/api/v1/auth/refresh", null, Map.of("refreshToken", s.refresh()));        // replaying the old token
        assertEquals(401, reuse.status());
        assertEquals(401, post("/api/v1/auth/refresh", null, Map.of("refreshToken", r1.s("refreshToken"))).status(), "whole family revoked after reuse");
    }

    @Test
    void logoutRevokesRefreshToken() {
        Session s = customer();
        assertEquals(204, post("/api/v1/auth/logout", null, Map.of("refreshToken", s.refresh())).status());
        assertEquals(401, post("/api/v1/auth/refresh", null, Map.of("refreshToken", s.refresh())).status());
    }

    @Test
    void passwordResetFlowRevokesSessions() {
        Session s = customer();
        assertEquals(202, post("/api/v1/auth/forgot-password", null, Map.of("identifier", "+77019998877")).status(), "unknown account looks identical");
        jdbc.sql("UPDATE otp_verifications SET created_at = now() - interval '2 minutes'").update();   // clear the 30s resend throttle
        assertEquals(202, post("/api/v1/auth/forgot-password", null, Map.of("identifier", s.phone())).status());
        String code = TestConfig.OTPS.get(s.phone());
        assertEquals("weak_password", post("/api/v1/auth/reset-password", null, Map.of("identifier", s.phone(), "code", code, "newPassword", "alllowercase")).s("code"));
        assertEquals(204, post("/api/v1/auth/reset-password", null, Map.of("identifier", s.phone(), "code", code, "newPassword", "NewSecret456")).status());
        assertEquals(401, post("/api/v1/auth/login", null, Map.of("identifier", s.phone(), "password", "Secret123")).status());
        assertEquals(200, post("/api/v1/auth/login", null, Map.of("identifier", s.phone(), "password", "NewSecret456")).status());
        assertEquals(401, post("/api/v1/auth/refresh", null, Map.of("refreshToken", s.refresh())).status());
    }

    @Test
    void roleSeparationIsEnforcedOnTheBackend() {
        Session c = customer(); Session d = register("DRIVER");
        assertEquals(401, get("/api/v1/rides/active", null).status());
        assertEquals(403, get("/api/v1/admin/dashboard", c.token()).status());
        assertEquals(403, get("/api/v1/admin/dashboard", d.token()).status());
        assertEquals(403, get("/api/v1/drivers/me", c.token()).status());
        assertEquals(403, requestRide(d, "ECONOMY", "CASH").status());
        Session support = admin("SUPPORT_AGENT");
        assertEquals(200, get("/api/v1/admin/dashboard", support.token()).status());
        assertEquals(403, get("/api/v1/admin/audit-logs", support.token()).status());
        assertEquals(403, put("/api/v1/admin/pricing/00000000-0000-0000-0000-000000000000", support.token(), Map.of("baseFare", 1, "perKm", 1, "perMinute", 1, "minFare", 1, "bookingFee", 0, "cancellationFee", 0, "freeCancelSeconds", 1, "commissionRate", "0.1", "demandMultiplier", "1", "active", true)).status());
        assertEquals(403, get("/api/v1/admin/payments", admin("OPERATIONS_ADMIN").token()).status());
        assertEquals(200, get("/api/v1/admin/payments", admin("FINANCE_ADMIN").token()).status());
        assertEquals(403, put("/api/v1/admin/drivers/" + d.id() + "/verification", admin("FINANCE_ADMIN").token(), Map.of("status", "APPROVED")).status());
    }

    @Test
    void customersCannotReadOtherUsersRidesOrTickets() {
        Session a = customer(), b = customer(); driver("ECONOMY", 43.2336, 76.9568);
        String rideId = requestRide(a, "ECONOMY", "CASH").s("id");
        assertEquals(404, get("/api/v1/rides/" + rideId, b.token()).status());
        assertEquals(404, post("/api/v1/rides/" + rideId + "/cancel", b.token(), null).status());
        String t = post("/api/v1/support/tickets", a.token(), Map.of("category", "RIDE", "subject", "Help", "message", "Where is my driver")).s("id");
        assertEquals(404, get("/api/v1/support/tickets/" + t + "/messages", b.token()).status());
        assertEquals(1, get("/api/v1/support/tickets/" + t + "/messages", a.token()).body().size());
    }

    @Test
    void suspendedAccountLosesAccessImmediately() {
        Session c = customer();
        assertEquals(200, get("/api/v1/customers/me", c.token()).status());
        Session adm = admin("OPERATIONS_ADMIN");
        assertEquals(200, put("/api/v1/admin/users/" + c.id() + "/status", adm.token(), Map.of("status", "SUSPENDED", "reason", "fraud review")).status());
        assertEquals(401, get("/api/v1/customers/me", c.token()).status());                          // valid JWT, but account is suspended
        assertEquals(403, post("/api/v1/auth/login", null, Map.of("identifier", c.phone(), "password", "Secret123")).status());
        assertEquals(1, jdbc.sql("SELECT count(*) FROM audit_logs WHERE action='USER_STATUS'").query(Integer.class).single());
    }

    @Test
    void supportChatRoundTripWithAgent() {
        Session c = customer();
        String t = post("/api/v1/support/tickets", c.token(), Map.of("category", "PAYMENT", "subject", "Charged twice", "message", "I was charged twice")).s("id");
        Session agent = admin("SUPPORT_AGENT");
        assertEquals(201, post("/api/v1/admin/support/tickets/" + t + "/messages", agent.token(), Map.of("body", "We are checking", "status", "PENDING")).status());
        assertEquals(1, get("/api/v1/support/tickets", c.token()).body().get(0).path("unread").asInt());
        assertEquals(2, get("/api/v1/support/tickets/" + t + "/messages", c.token()).body().size());
        assertEquals(0, get("/api/v1/support/tickets", c.token()).body().get(0).path("unread").asInt());
        assertEquals(1, jdbc.sql("SELECT count(*) FROM notifications WHERE type='SUPPORT_MESSAGE'").query(Integer.class).single());
    }

    @Test
    void accountDeletionAnonymisesAndBlocksLogin() {
        Session c = customer();
        assertEquals(204, call(org.springframework.http.HttpMethod.DELETE, "/api/v1/customers/me", c.token(), null, null).status());
        assertEquals(401, post("/api/v1/auth/login", null, Map.of("identifier", c.phone(), "password", "Secret123")).status());
        assertEquals("Deleted user", jdbc.sql("SELECT full_name FROM users WHERE id=:i").param("i", c.id()).query(String.class).single());
    }

    @Test
    void healthAndOpenApiArePublic() {
        assertEquals(200, get("/actuator/health", null).status());
        assertEquals(200, get("/api/v1/docs", null).status());
        assertEquals(4, get("/api/v1/catalog/categories?lang=kk", null).body().size());
    }
}
