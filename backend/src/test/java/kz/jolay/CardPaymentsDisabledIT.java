package kz.jolay;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/** With JOLAY_PAYMENT_PROVIDER=none (the public-deployment setting) there is no sandbox gateway at all: no checkout, no webhook, no card rides or top-ups. */
class CardPaymentsDisabledIT extends IntegrationTestBase {
    @DynamicPropertySource
    static void props(DynamicPropertyRegistry r) { r.add("jolay.payments.provider", () -> "none"); }

    @Test
    void sandboxEndpointsAndCardPaymentsAreUnavailable() {
        Session c = customer();
        // no sandbox bean: a signed webhook (made with the test secret) is not accepted and the checkout helper does not exist
        String body = "{\"eventId\":\"e1\",\"providerRef\":\"sbx_x\",\"status\":\"SUCCEEDED\",\"amount\":\"3000.00\"}";
        String sig = new kz.jolay.payments.SandboxPaymentProvider("test-secret", "http://x").sign(body);
        assertEquals(404, call(HttpMethod.POST, "/api/v1/payments/webhooks/sandbox", null, body, Map.of("X-Signature", sig)).status());
        assertEquals(404, post("/api/v1/payments/" + java.util.UUID.randomUUID() + "/sandbox-checkout", c.token(), null).status());

        assertEquals(503, post("/api/v1/wallet/top-ups", c.token(), Map.of("amount", 3000)).status());
        assertEquals("card_payments_unavailable", post("/api/v1/wallet/top-ups", c.token(), Map.of("amount", 3000)).s("code"));
        Resp ride = requestRide(c, "ECONOMY", "CARD");
        assertEquals(503, ride.status());
        assertEquals("card_payments_unavailable", ride.s("code"));
        assertEquals(0, jdbc.sql("SELECT count(*) FROM payment_transactions").query(Integer.class).single());
        assertEquals(0, jdbc.sql("SELECT count(*) FROM rides").query(Integer.class).single());
    }

    @Test
    void cashRidesStillWork() {
        Session c = customer(); driver("ECONOMY", 43.2336, 76.9568);
        assertEquals(201, requestRide(c, "ECONOMY", "CASH").status());
    }
}
