package kz.jolay;

import kz.jolay.common.ProductionSafetyCheck;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Method;

import static org.junit.jupiter.api.Assertions.*;

/** The prod profile must refuse development-only settings. */
class ProductionSafetyCheckTest {
    private static final String SECRET = "a-real-secret-a-real-secret-a-real-secret";

    private void verify(String secret, String provider, boolean logCode, boolean allowSandbox, String publicUrl) throws Exception {
        ProductionSafetyCheck c = new ProductionSafetyCheck(secret, provider, logCode, allowSandbox, publicUrl);
        Method m = ProductionSafetyCheck.class.getDeclaredMethod("verify");
        m.setAccessible(true);
        try { m.invoke(c); } catch (java.lang.reflect.InvocationTargetException e) { throw (Exception) e.getCause(); }
    }

    @Test
    void acceptsAProperProductionConfiguration() {
        assertDoesNotThrow(() -> verify(SECRET, "kaspi", false, false, "https://api.jolay.kz"));
    }

    @Test
    void refusesDevelopmentDefaults() {
        assertThrows(IllegalStateException.class, () -> verify("dev-only-secret-xxxxxxxxxxxxxxxxxxxxxxxxxxxx", "kaspi", false, false, "https://api.jolay.kz"));
        assertThrows(IllegalStateException.class, () -> verify(SECRET, "kaspi", true, false, "https://api.jolay.kz"));
        assertThrows(IllegalStateException.class, () -> verify(SECRET, "sandbox", false, false, "https://api.jolay.kz"));
    }

    @Test
    void publicUrlMustBeHttpsExceptForAnInternalSandboxDemo() {
        IllegalStateException e = assertThrows(IllegalStateException.class, () -> verify(SECRET, "kaspi", false, false, "http://localhost:8080"));
        assertTrue(e.getMessage().contains("JOLAY_PUBLIC_URL"));
        assertThrows(IllegalStateException.class, () -> verify(SECRET, "kaspi", false, false, "http://api.jolay.kz"));
        assertDoesNotThrow(() -> verify(SECRET, "sandbox", false, true, "http://localhost:8080"));      // closed internal demo only
    }
}
