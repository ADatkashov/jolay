package kz.jolay;

import kz.jolay.identity.Totp;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class TotpTest {
    private static final String RFC_SECRET = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";   // ASCII "12345678901234567890", the RFC 6238 test key

    @Test
    void matchesTheRfc6238TestVectors() {
        assertEquals("287082", Totp.code(RFC_SECRET, 59 / 30));            // T=59, last six digits of 94287082
        assertEquals("081804", Totp.code(RFC_SECRET, 1111111109L / 30));
        assertEquals("050471", Totp.code(RFC_SECRET, 1111111111L / 30));
        assertEquals("005924", Totp.code(RFC_SECRET, 1234567890L / 30));
    }

    @Test
    void verifyAcceptsOneStepOfDriftButNotMore() {
        long now = 1_000_000;
        String code = Totp.code(RFC_SECRET, now);
        assertEquals(now, Totp.verify(RFC_SECRET, code, now));
        assertEquals(now, Totp.verify(RFC_SECRET, code, now + 1));
        assertEquals(now, Totp.verify(RFC_SECRET, code, now - 1));
        assertEquals(-1, Totp.verify(RFC_SECRET, code, now + 2));
        assertEquals(-1, Totp.verify(RFC_SECRET, "12345", now), "must be six digits");
        assertEquals(-1, Totp.verify(RFC_SECRET, null, now));
    }

    @Test
    void base32RoundTripsAndSecretsAreRandom() {
        byte[] data = "hello jolay".getBytes();
        assertArrayEquals(data, Totp.fromBase32(Totp.base32(data)));
        String a = Totp.newSecret(), b = Totp.newSecret();
        assertNotEquals(a, b);
        assertEquals(32, a.length());
        assertThrows(IllegalArgumentException.class, () -> Totp.fromBase32("not base32!"));
    }

    @Test
    void otpauthUriCarriesIssuerAccountAndSecret() {
        String uri = Totp.otpauthUri("JOLAY", "ops@jolay.kz", RFC_SECRET);
        assertTrue(uri.startsWith("otpauth://totp/JOLAY:ops%40jolay.kz?secret=" + RFC_SECRET));
        assertTrue(uri.contains("issuer=JOLAY") && uri.contains("digits=6") && uri.contains("period=30"));
    }
}
