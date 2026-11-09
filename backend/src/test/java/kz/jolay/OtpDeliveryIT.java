package kz.jolay;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/** A failing OTP gateway must give a clear, uniform error and must not leak whether an account exists. */
class OtpDeliveryIT extends IntegrationTestBase {
    @AfterEach void restore() { TestConfig.FAIL_SMS = false; }

    @Test
    void registrationReportsGatewayFailureAndLeavesNoHalfCreatedAccount() {
        String phone = phone();
        TestConfig.FAIL_SMS = true;
        Resp r = post("/api/v1/auth/register", null, Map.of("fullName", "Gate Way", "phone", phone, "password", "Secret123", "role", "CUSTOMER", "acceptTerms", true, "locale", "ru"));
        assertEquals(503, r.status());
        assertEquals("otp_delivery_failed", r.s("code"));
        assertEquals(0, jdbc.sql("SELECT count(*) FROM users WHERE phone=:p").param("p", phone).query(Integer.class).single(), "rolled back");
        assertEquals(0, jdbc.sql("SELECT count(*) FROM otp_verifications WHERE phone=:p").param("p", phone).query(Integer.class).single());
        assertFalse(r.body().toString().contains("gateway down"), "provider details are not exposed");

        TestConfig.FAIL_SMS = false;                                    // the user can simply try again
        assertEquals(201, post("/api/v1/auth/register", null, Map.of("fullName", "Gate Way", "phone", phone, "password", "Secret123", "role", "CUSTOMER", "acceptTerms", true, "locale", "ru")).status());
        assertEquals(200, post("/api/v1/auth/verify-otp", null, Map.of("phone", phone, "code", TestConfig.OTPS.get(phone))).status());
    }

    @Test
    void forgotPasswordAnswersTheSameWhenTheGatewayIsDownAndNeverRevealsAccounts() {
        Session known = customer();
        String unknown = phone();
        TestConfig.FAIL_SMS = true;
        Resp a = post("/api/v1/auth/forgot-password", null, Map.of("identifier", known.phone()));
        Resp b = post("/api/v1/auth/forgot-password", null, Map.of("identifier", unknown));
        assertEquals(202, a.status());
        assertEquals(a.status(), b.status());
    }

    @Test
    void resendOtpReportsGatewayFailureOnlyForPendingAccounts() {
        String phone = phone();
        post("/api/v1/auth/register", null, Map.of("fullName", "Pending One", "phone", phone, "password", "Secret123", "role", "CUSTOMER", "acceptTerms", true, "locale", "ru"));
        jdbc.sql("DELETE FROM otp_verifications WHERE phone=:p").param("p", phone).update();      // clear the resend throttle
        TestConfig.FAIL_SMS = true;
        assertEquals(503, post("/api/v1/auth/resend-otp", null, Map.of("phone", phone)).status());
        assertEquals(200, post("/api/v1/auth/resend-otp", null, Map.of("phone", phone())).status(), "unknown number: silent no-op");
    }
}
