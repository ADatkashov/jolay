package kz.jolay;

import kz.jolay.common.ProductionSafetyCheck;
import kz.jolay.identity.LogSmsSender;
import kz.jolay.identity.SmsSender;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Method;

import static org.junit.jupiter.api.Assertions.*;

/** The prod profile must refuse development-only and unsafe settings; the sandbox demo flag must not relax anything except the gateway itself. */
class ProductionSafetyCheckTest {
    private static final String SECRET = "a-real-secret-a-real-secret-a-real-secret";
    private static final String WEBHOOK = "a-strong-sandbox-webhook-secret-123";
    private static final SmsSender DELIVERING = (phone, text) -> { };
    private static final SmsSender LOG_ONLY = new LogSmsSender(false);

    /** Builder for a valid production configuration; tests change one field at a time. */
    private static class Cfg {
        String secret = SECRET, provider = "none", publicUrl = "https://api.jolay.kz", cors = "https://admin.jolay.kz", webhook = WEBHOOK, adminPw = "a-long-admin-password", docs = "/data/documents";
        boolean logCode, allowSandbox; SmsSender sms = DELIVERING;
        Cfg secret(String v) { secret = v; return this; } Cfg provider(String v) { provider = v; return this; } Cfg logCode(boolean v) { logCode = v; return this; }
        Cfg allowSandbox(boolean v) { allowSandbox = v; return this; } Cfg publicUrl(String v) { publicUrl = v; return this; } Cfg cors(String v) { cors = v; return this; }
        Cfg webhook(String v) { webhook = v; return this; } Cfg adminPw(String v) { adminPw = v; return this; } Cfg sms(SmsSender v) { sms = v; return this; }
        void verify() throws Exception {
            ProductionSafetyCheck c = new ProductionSafetyCheck(secret, provider, logCode, allowSandbox, publicUrl, cors, webhook, adminPw, docs, sms);
            Method m = ProductionSafetyCheck.class.getDeclaredMethod("verify");
            m.setAccessible(true);
            try { m.invoke(c); } catch (java.lang.reflect.InvocationTargetException e) { throw (Exception) e.getCause(); }
        }
    }
    private static Cfg ok() { return new Cfg(); }
    private static IllegalStateException refused(Cfg c) { return assertThrows(IllegalStateException.class, c::verify); }

    @Test
    void acceptsAProperProductionConfiguration() {
        assertDoesNotThrow(() -> ok().verify());
        assertDoesNotThrow(() -> ok().provider("kaspi").verify());
        assertDoesNotThrow(() -> ok().cors("https://admin.jolay.kz,https://partners.jolay.kz").verify());
    }

    @Test
    void refusesDevelopmentDefaults() {
        refused(ok().secret("dev-only-secret-xxxxxxxxxxxxxxxxxxxxxxxxxxxx"));
        refused(ok().secret("local-dev-secret-local-dev-secret-0123456789"));
        refused(ok().secret("too-short"));
        refused(ok().logCode(true));
    }

    @Test
    void sandboxPaymentsAreRefusedUnlessExplicitlyAllowedAndNeverRelaxOtherChecks() {
        assertTrue(refused(ok().provider("sandbox")).getMessage().contains("sandbox"));
        // the explicit demo flag permits only the gateway, with a real webhook secret
        assertDoesNotThrow(() -> ok().provider("sandbox").allowSandbox(true).verify());
        refused(ok().provider("sandbox").allowSandbox(true).webhook("dev-sandbox-secret"));
        refused(ok().provider("sandbox").allowSandbox(true).webhook("short"));
        // ... and it does not excuse a localhost URL, wildcard/localhost/http CORS, an undelivered OTP channel or a weak admin password
        refused(ok().provider("sandbox").allowSandbox(true).publicUrl("http://localhost:8080"));
        refused(ok().provider("sandbox").allowSandbox(true).cors("*"));
        refused(ok().provider("sandbox").allowSandbox(true).cors("http://localhost:5173"));
        refused(ok().provider("sandbox").allowSandbox(true).sms(LOG_ONLY));
        refused(ok().provider("sandbox").allowSandbox(true).adminPw("ChangeMe12345"));
        // a stray flag next to a real provider changes nothing
        assertDoesNotThrow(() -> ok().provider("kaspi").allowSandbox(true).verify());
    }

    @Test
    void publicUrlMustBeHttps() {
        assertTrue(refused(ok().publicUrl("http://localhost:8080")).getMessage().contains("JOLAY_PUBLIC_URL"));
        refused(ok().publicUrl("http://api.jolay.kz"));
        refused(ok().publicUrl("https://localhost:8443"));
    }

    @Test
    void corsOriginsMustBeExplicitHttpsOrigins() {
        for (String bad : new String[]{"", "*", "https://admin.jolay.kz,*", "http://localhost:5173", "http://127.0.0.1:3000", "http://admin.jolay.kz", "https://admin.jolay.kz,http://other.kz"}) {
            IllegalStateException e = refused(ok().cors(bad));
            assertTrue(e.getMessage().contains("JOLAY_CORS_ORIGINS"), "cors=" + bad);
        }
    }

    @Test
    void anOtpChannelThatDeliversNothingIsAConfigurationError() {
        IllegalStateException e = refused(ok().sms(LOG_ONLY));
        assertTrue(e.getMessage().contains("OTP delivery channel"));
    }

    @Test
    void theBootstrapAdminPasswordMustBeStrongWhenSet() {
        refused(ok().adminPw("short-pw"));
        refused(ok().adminPw("ChangeMe12345"));
        assertDoesNotThrow(() -> ok().adminPw("").verify());      // no bootstrap requested
    }
}
