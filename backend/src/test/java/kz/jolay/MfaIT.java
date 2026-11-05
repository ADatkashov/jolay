package kz.jolay;

import kz.jolay.identity.Totp;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/** Optional TOTP second factor for staff accounts. */
class MfaIT extends IntegrationTestBase {
    private static long now() { return Totp.stepAt(Instant.now().getEpochSecond()); }
    private Resp login(String phone, String code) {
        return post("/api/v1/auth/login", null, code == null ? Map.of("identifier", phone, "password", "Secret123") : Map.of("identifier", phone, "password", "Secret123", "mfaCode", code));
    }
    /** Enables MFA for a fresh staff account; returns {session, secret, recovery codes}. */
    private record Enrolled(Session s, String secret, List<String> recovery) {}
    private Enrolled enrol() {
        Session a = admin("FINANCE_ADMIN");
        String secret = post("/api/v1/account/mfa/setup", a.token(), null).s("secret");
        Resp en = post("/api/v1/account/mfa/enable", a.token(), Map.of("code", Totp.code(secret, now())));
        assertEquals(200, en.status(), String.valueOf(en.body()));
        List<String> rec = new java.util.ArrayList<>();
        en.body().path("recoveryCodes").forEach(n -> rec.add(n.asText()));
        return new Enrolled(a, secret, rec);
    }

    @Test
    void onlyStaffCanEnrolAndNothingChangesUntilACodeIsConfirmed() {
        assertEquals(403, post("/api/v1/account/mfa/setup", customer().token(), null).status());
        assertEquals(401, post("/api/v1/account/mfa/setup", null, null).status());
        Session a = admin("OPERATIONS_ADMIN");
        Resp setup = post("/api/v1/account/mfa/setup", a.token(), null);
        assertEquals(200, setup.status());
        assertTrue(setup.s("otpauthUri").startsWith("otpauth://totp/JOLAY:"));
        assertEquals(200, login(a.phone(), null).status(), "a pending setup is not enforced yet");
        assertEquals("invalid_mfa_code", post("/api/v1/account/mfa/enable", a.token(), Map.of("code", "000000")).s("code"));
        assertFalse(get("/api/v1/account/mfa", a.token()).body().path("enabled").asBoolean());
        assertEquals(409, post("/api/v1/account/mfa/enable", admin("SUPPORT_AGENT").token(), Map.of("code", "123456")).status(), "no setup, nothing to enable");
    }

    @Test
    void onceEnabledLoginNeedsAFreshCodeAndSecretsAreStoredEncrypted() {
        Enrolled e = enrol();
        assertEquals(8, e.recovery().size());
        assertNotEquals(e.secret(), jdbc.sql("SELECT mfa_secret_enc FROM users WHERE id=:i").param("i", e.s().id()).query(String.class).single(), "the secret is not stored in clear");
        assertEquals(0, jdbc.sql("SELECT count(*) FROM mfa_recovery_codes WHERE code_hash=:c").param("c", e.recovery().get(0)).query(Integer.class).single(), "recovery codes are stored hashed");

        Resp none = login(e.s().phone(), null);
        assertEquals(401, none.status());
        assertEquals("mfa_required", none.s("code"));
        assertNull(none.body().get("accessToken"), "no tokens without the second factor");
        assertEquals("invalid_mfa_code", login(e.s().phone(), "000000").s("code"));
        assertEquals("invalid_mfa_code", login(e.s().phone(), Totp.code(e.secret(), now())).s("code"), "the code used to enable cannot be replayed");

        Resp ok = login(e.s().phone(), Totp.code(e.secret(), now() + 1));
        assertEquals(200, ok.status(), String.valueOf(ok.body()));
        assertNotNull(ok.s("accessToken"));
        assertEquals("invalid_mfa_code", login(e.s().phone(), Totp.code(e.secret(), now() + 1)).s("code"), "a code is good once");
    }

    @Test
    void recoveryCodesWorkOnceAndDisablingNeedsPasswordAndCode() {
        Enrolled e = enrol();
        String rc = e.recovery().get(0);
        assertEquals(200, login(e.s().phone(), rc).status());
        assertEquals("invalid_mfa_code", login(e.s().phone(), rc).s("code"), "single use");
        assertEquals(7, get("/api/v1/account/mfa", e.s().token()).body().path("recoveryCodesLeft").asInt());

        String code = Totp.code(e.secret(), now() + 1);
        assertEquals(401, post("/api/v1/account/mfa/disable", e.s().token(), Map.of("password", "WrongPass1", "code", code)).status());
        assertEquals(400, post("/api/v1/account/mfa/disable", e.s().token(), Map.of("password", "Secret123", "code", "000000")).status());
        assertEquals(200, post("/api/v1/account/mfa/disable", e.s().token(), Map.of("password", "Secret123", "code", e.recovery().get(1))).status());
        assertEquals(200, login(e.s().phone(), null).status(), "back to password-only");
        assertEquals(0, jdbc.sql("SELECT count(*) FROM mfa_recovery_codes WHERE user_id=:u").param("u", e.s().id()).query(Integer.class).single());
    }

    @Test
    void guessingCodesWithAKnownPasswordLocksTheAccountOut() {
        Enrolled e = enrol();
        int status = 0;
        for (int i = 0; i < 30 && status != 429; i++) status = login(e.s().phone(), String.format("%06d", 100000 + i)).status();
        assertEquals(429, status, "wrong codes count towards the same lockout as wrong passwords");
        assertEquals("login_locked", login(e.s().phone(), Totp.code(e.secret(), now() + 1)).s("code"), "even a correct code is refused while locked");
    }
}
