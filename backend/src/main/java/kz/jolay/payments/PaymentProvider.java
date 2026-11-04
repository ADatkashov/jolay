package kz.jolay.payments;

import java.math.BigDecimal;
import java.util.UUID;

/**
 * Adapter boundary for card/wallet payment gateways (FreedomPay, Kaspi-compatible, ...).
 * Providers only talk to the gateway; ALL money state changes happen in {@link PaymentService} after a verified callback.
 */
public interface PaymentProvider {
    String name();

    /** Create a payment at the gateway. Returns the gateway reference and the URL/SDK payload the client must open. */
    Initiation initiate(UUID paymentId, BigDecimal amount, String currency, String description);

    /** Verify the authenticity of a callback body. */
    boolean verifySignature(String rawBody, String signatureHeader);

    /** Ask the gateway to refund (sandbox: no-op). Throws on failure. */
    void refund(String providerRef, BigDecimal amount);

    record Initiation(String providerRef, String checkoutUrl) {}
}
