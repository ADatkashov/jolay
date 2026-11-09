package kz.jolay.common;

import kz.jolay.identity.SmsSender;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import jakarta.annotation.PostConstruct;
import java.nio.charset.StandardCharsets;
import java.util.Set;

/**
 * Refuses to start in the prod profile with development-only or unsafe settings. None of these checks can be switched off by the
 * sandbox demo flag: that flag only permits the sandbox payment gateway (see {@link #verify()}).
 */
@Component
@Profile("prod")
public class ProductionSafetyCheck {
    private static final Logger log = LoggerFactory.getLogger(ProductionSafetyCheck.class);
    private static final Set<String> KNOWN_WEAK_SECRETS = Set.of("dev-sandbox-secret", "test-secret", "change-me", "change-me-too", "changeme", "secret");
    private static final Set<String> KNOWN_WEAK_PASSWORDS = Set.of("changeme12345", "change-me", "change-me-too", "password1234", "admin12345678");

    private final String jwtSecret, paymentProvider, publicBaseUrl, corsOrigins, sandboxWebhookSecret, adminPassword, documentsDir;
    private final boolean logCode, allowSandbox;
    private final SmsSender sms;

    public ProductionSafetyCheck(@Value("${jolay.security.jwt-secret}") String jwtSecret, @Value("${jolay.payments.provider}") String paymentProvider,
                                 @Value("${jolay.sms.log-code:false}") boolean logCode, @Value("${JOLAY_ALLOW_SANDBOX_PAYMENTS:false}") boolean allowSandbox,
                                 @Value("${jolay.payments.public-base-url}") String publicBaseUrl,
                                 @Value("${jolay.security.cors-origins:}") String corsOrigins,
                                 @Value("${jolay.payments.sandbox-webhook-secret:}") String sandboxWebhookSecret,
                                 @Value("${jolay.admin-bootstrap.password:}") String adminPassword,
                                 @Value("${jolay.storage.documents-dir:}") String documentsDir,
                                 SmsSender sms) {
        this.jwtSecret = jwtSecret; this.paymentProvider = paymentProvider; this.logCode = logCode; this.allowSandbox = allowSandbox; this.publicBaseUrl = publicBaseUrl;
        this.corsOrigins = corsOrigins; this.sandboxWebhookSecret = sandboxWebhookSecret; this.adminPassword = adminPassword; this.documentsDir = documentsDir; this.sms = sms;
    }

    @PostConstruct
    void verify() {
        if (jwtSecret.startsWith("dev-only-secret") || jwtSecret.startsWith("local-dev-secret"))
            throw new IllegalStateException("prod profile: JOLAY_JWT_SECRET must be set to a real secret");
        if (jwtSecret.getBytes(StandardCharsets.UTF_8).length < 32) throw new IllegalStateException("prod profile: JOLAY_JWT_SECRET must be at least 32 bytes");
        if (logCode) throw new IllegalStateException("prod profile: JOLAY_SMS_LOG_CODE must be false");

        // One-time codes must actually reach people: the development log sender delivers nothing, so sign-up and password reset would be impossible.
        if (!sms.deliversMessages())
            throw new IllegalStateException("prod profile: no OTP delivery channel is configured (the SMS sender is the development log sender). "
                    + "Enable WhatsApp (JOLAY_WHATSAPP_ENABLED=true plus its credentials) and/or provide a real SmsSender bean named productionSmsSender");

        // Payments. The sandbox gateway lets any signed-in customer mark their own payments as paid, so it needs a separate explicit flag and a real secret.
        if ("sandbox".equals(paymentProvider)) {
            if (!allowSandbox)
                throw new IllegalStateException("prod profile: the sandbox payment gateway would let anyone mark payments as paid. Use JOLAY_PAYMENT_PROVIDER=none "
                        + "(cash and wallet only) or a real provider; JOLAY_ALLOW_SANDBOX_PAYMENTS=true is for a closed internal demo only, never a public deployment");
            if (sandboxWebhookSecret.length() < 24 || KNOWN_WEAK_SECRETS.contains(sandboxWebhookSecret.toLowerCase()))
                throw new IllegalStateException("prod profile: JOLAY_SANDBOX_WEBHOOK_SECRET must be a strong secret (>= 24 characters) even for the sandbox demo");
            log.warn("SANDBOX PAYMENTS ARE ENABLED: no real money moves and customers can mark their own card payments as paid. Closed internal demo only.");
        } else if (allowSandbox) {
            log.warn("JOLAY_ALLOW_SANDBOX_PAYMENTS is set but the payment provider is '{}': the flag has no effect, remove it", paymentProvider);
        }

        // Browser origins and the public link base are checked unconditionally (the sandbox flag does not relax them).
        if (corsOrigins.isBlank() || corsOrigins.contains("*") || corsOrigins.contains("localhost") || corsOrigins.contains("127.0.0.1")
                || java.util.Arrays.stream(corsOrigins.split(",")).map(String::trim).anyMatch(o -> !o.startsWith("https://")))
            throw new IllegalStateException("prod profile: JOLAY_CORS_ORIGINS must list the real https:// origins of the admin console / partner portal (no '*', no localhost, no http://)");
        // The trip-sharing links texted to emergency contacts are built from this address: a development default would send people to localhost.
        if (!publicBaseUrl.startsWith("https://") || publicBaseUrl.contains("localhost") || publicBaseUrl.contains("127.0.0.1"))
            throw new IllegalStateException("prod profile: JOLAY_PUBLIC_URL must be the public https:// address of the API (it is used in links sent by SMS)");

        if (!adminPassword.isBlank() && (adminPassword.length() < 12 || KNOWN_WEAK_PASSWORDS.contains(adminPassword.toLowerCase())))
            throw new IllegalStateException("prod profile: JOLAY_ADMIN_PASSWORD must be at least 12 characters and not a published default");

        // Not a failure (an operator may mount a durable encrypted volume), but never silent: this repository cannot verify it.
        log.warn("Driver documents are written to the local directory '{}' without encryption or malware scanning. Mount a durable, encrypted volume there "
                + "or move to object storage before real driver documents are uploaded (docs/DEPLOYMENT.md#driver-documents).", documentsDir);
        if (sms instanceof kz.jolay.identity.WhatsAppFirstSender w && !w.fallbackDelivers())
            log.warn("Only WhatsApp delivers one-time codes: people without WhatsApp cannot sign up or reset a password until an SMS gateway is added");
    }
}
