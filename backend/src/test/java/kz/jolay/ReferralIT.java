package kz.jolay;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/** Referral codes and the one-off ledger bonus for an invited customer's first completed ride. */
class ReferralIT extends IntegrationTestBase {

    @org.junit.jupiter.api.BeforeEach
    void defaults() {   // application_settings are not truncated between tests
        setting("referral.enabled", "false"); setting("referral.min_fare", "1500"); setting("referral.max_rewards_per_referrer", "20");
    }

    private void setting(String key, String value) { jdbc.sql("UPDATE application_settings SET value=:v WHERE key=:k").param("v", value).param("k", key).update(); }

    private Session registerWithCode(String code) {
        String phone = phone();
        Resp r = post("/api/v1/auth/register", null, Map.of("fullName", "Invited Friend", "phone", phone, "password", "Secret123", "role", "CUSTOMER", "acceptTerms", true, "locale", "en", "referralCode", code));
        assertEquals(201, r.status(), r.body().toString());
        String otp = TestConfig.OTPS.get(phone);
        Resp v = post("/api/v1/auth/verify-otp", null, Map.of("phone", phone, "code", otp));
        assertEquals(200, v.status(), v.body().toString());
        return new Session(java.util.UUID.fromString(v.body().path("user").path("id").asText()), v.s("accessToken"), v.s("refreshToken"), phone);
    }

    @Test
    void invitedFirstRideCreditsBothWalletsOnceThroughTheLedger() {
        setting("referral.enabled", "true"); setting("referral.min_fare", "500");
        Session inviter = customer(); Session d = driver("ECONOMY", 43.2340, 76.9570);
        Resp mine = get("/api/v1/customers/me/referral", inviter.token());
        String code = mine.s("code");
        assertTrue(code.startsWith("J") && code.length() == 8, code);
        assertEquals(code, get("/api/v1/customers/me/referral", inviter.token()).s("code"));   // stable

        assertEquals(400, post("/api/v1/auth/register", null, Map.of("fullName", "Typo Person", "phone", phone(), "password", "Secret123", "role", "CUSTOMER", "acceptTerms", true, "referralCode", "JNOSUCH1")).status());

        Session friend = registerWithCode(code.toLowerCase());          // codes are case-insensitive
        assertEquals(0, balance(friend).compareTo(BigDecimal.ZERO));
        completeRide(friend, d, "CASH");
        assertEquals(0, balance(inviter).compareTo(new BigDecimal("1000")));
        assertEquals(0, balance(friend).compareTo(new BigDecimal("1000")));
        assertEquals(1, get("/api/v1/customers/me/referral", inviter.token()).body().path("rewarded").asInt());

        completeRide(friend, d, "CASH");                                // second ride: no second bonus
        assertEquals(0, balance(inviter).compareTo(new BigDecimal("1000")));
        assertEquals(0, new BigDecimal(jdbc.sql("SELECT balance FROM accounts WHERE type='PROMO'").query(String.class).single()).compareTo(new BigDecimal("-2000")));
        assertLedgerBalanced();
    }

    @Test
    void programmeIsOffByDefaultAndRespectsMinimumFareAndPerReferrerCap() {
        Session inviter = customer(); Session d = driver("ECONOMY", 43.2340, 76.9570);
        String code = get("/api/v1/customers/me/referral", inviter.token()).s("code");
        assertFalse(get("/api/v1/customers/me/referral", inviter.token()).body().path("enabled").asBoolean());

        Session off = registerWithCode(code);
        completeRide(off, d, "CASH");
        assertEquals(0, balance(inviter).compareTo(BigDecimal.ZERO), "disabled programme pays nothing");

        setting("referral.enabled", "true"); setting("referral.min_fare", "1000000");
        Session cheap = registerWithCode(code);
        completeRide(cheap, d, "CASH");
        assertEquals(0, balance(inviter).compareTo(BigDecimal.ZERO), "fare below the minimum pays nothing");

        setting("referral.min_fare", "500"); setting("referral.max_rewards_per_referrer", "1");
        Session first = registerWithCode(code); completeRide(first, d, "CASH");
        Session second = registerWithCode(code); completeRide(second, d, "CASH");
        assertEquals(0, balance(inviter).compareTo(new BigDecimal("1000")), "cap of one rewarded invitation");
        assertEquals(0, balance(second).compareTo(BigDecimal.ZERO));
        assertLedgerBalanced();
    }
}
