package kz.jolay.payments;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.UUID;

/**
 * DEVELOPMENT/TEST gateway. It never moves real money. Callbacks are HMAC-SHA256 signed exactly like a real gateway would,
 * so the production verification path is exercised. A real adapter (e.g. FreedomPay) implements the same interface;
 * see docs/PAYMENT_INTEGRATION.md for what is still required (merchant credentials, signature scheme, URLs).
 */
@Component
public class SandboxPaymentProvider implements PaymentProvider {
    private final String secret;
    private final String baseUrl;

    public SandboxPaymentProvider(@Value("${jolay.payments.sandbox-webhook-secret}") String secret,
                                  @Value("${jolay.payments.public-base-url}") String baseUrl) { this.secret = secret; this.baseUrl = baseUrl; }

    @Override public String name() { return "sandbox"; }

    @Override public Initiation initiate(UUID paymentId, BigDecimal amount, String currency, String description) {
        String ref = "sbx_" + UUID.randomUUID().toString().replace("-", "");
        return new Initiation(ref, baseUrl + "/api/v1/payments/" + paymentId + "/sandbox-checkout");
    }

    public String sign(String body) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return HexFormat.of().formatHex(mac.doFinal(body.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) { throw new IllegalStateException(e); }
    }

    @Override public boolean verifySignature(String rawBody, String sig) {
        if (sig == null) return false;
        return MessageDigest.isEqual(sign(rawBody).getBytes(StandardCharsets.UTF_8), sig.trim().toLowerCase().getBytes(StandardCharsets.UTF_8));
    }

    @Override public void refund(String providerRef, BigDecimal amount) { /* sandbox: nothing to call */ }
}
