package kz.jolay.common;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import jakarta.annotation.PostConstruct;

/** Refuses to start in the prod profile with development-only settings (audit: default secret / sandbox gateway / OTP logging). */
@Component
@Profile("prod")
public class ProductionSafetyCheck {
    private final String jwtSecret, paymentProvider, publicBaseUrl, corsOrigins;
    private final boolean logCode, allowSandbox;

    public ProductionSafetyCheck(@Value("${jolay.security.jwt-secret}") String jwtSecret, @Value("${jolay.payments.provider}") String paymentProvider,
                                 @Value("${jolay.sms.log-code:false}") boolean logCode, @Value("${JOLAY_ALLOW_SANDBOX_PAYMENTS:false}") boolean allowSandbox,
                                 @Value("${jolay.payments.public-base-url}") String publicBaseUrl,
                                 @Value("${jolay.security.cors-origins:}") String corsOrigins) {
        this.jwtSecret = jwtSecret; this.paymentProvider = paymentProvider; this.logCode = logCode; this.allowSandbox = allowSandbox; this.publicBaseUrl = publicBaseUrl; this.corsOrigins = corsOrigins;
    }

    @PostConstruct
    void verify() {
        if (jwtSecret.startsWith("dev-only-secret")) throw new IllegalStateException("prod profile: JOLAY_JWT_SECRET must be set to a real secret");
        if (logCode) throw new IllegalStateException("prod profile: JOLAY_SMS_LOG_CODE must be false");
        if ("sandbox".equals(paymentProvider) && !allowSandbox)
            throw new IllegalStateException("prod profile: the sandbox payment gateway would let anyone mark payments as paid. Configure a real provider "
                    + "(or set JOLAY_ALLOW_SANDBOX_PAYMENTS=true for a closed internal demo only)");
        // CORS decides which web origins may call the API from a browser (the admin console, the partner portal): production must name them explicitly.
        if (!allowSandbox && (corsOrigins.isBlank() || corsOrigins.contains("*") || corsOrigins.contains("localhost") || corsOrigins.contains("127.0.0.1")))
            throw new IllegalStateException("prod profile: JOLAY_CORS_ORIGINS must list the real https:// origins of the admin console / partner portal (no '*', no localhost)");
        // The trip-sharing links texted to emergency contacts are built from this address: a development default would send people to localhost.
        if (!allowSandbox && !publicBaseUrl.startsWith("https://"))
            throw new IllegalStateException("prod profile: JOLAY_PUBLIC_URL must be the public https:// address of the API (it is used in links sent by SMS)");
    }
}
