package kz.jolay.payments;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import kz.jolay.common.Auth;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1")
public class PaymentController {
    private final PaymentService payments;
    public PaymentController(PaymentService payments) { this.payments = payments; }

    public record PayRideRequest(@NotNull UUID rideId, @NotBlank @Pattern(regexp = "CARD|WALLET") String method) {}
    public record TopUpRequest(@NotNull @DecimalMin("100") @DecimalMax("500000") BigDecimal amount) {}

    @PostMapping("/payments/initialize") @PreAuthorize("hasRole('CUSTOMER')")
    public PaymentService.PaymentView initialize(@Valid @RequestBody PayRideRequest r, @RequestHeader(value = "Idempotency-Key", required = false) String key) {
        return payments.payRide(Auth.id(), r.rideId(), r.method(), key);
    }

    @GetMapping("/payments/{id}") @PreAuthorize("hasAnyRole('CUSTOMER','DRIVER')")
    public PaymentService.PaymentView get(@PathVariable UUID id) { return payments.get(Auth.id(), id, false); }

    @PostMapping("/wallet/top-ups") @PreAuthorize("hasRole('CUSTOMER')")
    public PaymentService.PaymentView topUp(@Valid @RequestBody TopUpRequest r, @RequestHeader(value = "Idempotency-Key", required = false) String key) {
        return payments.topUp(Auth.id(), r.amount(), key);
    }

    /** Gateway callback. Unauthenticated at the HTTP layer; authenticity is the HMAC signature over the raw body. */
    @PostMapping("/payments/webhooks/{provider}")
    public ResponseEntity<Map<String, String>> webhook(@PathVariable String provider, @RequestBody String body,
                                                       @RequestHeader(value = "X-Signature", required = false) String signature) {
        return ResponseEntity.ok(Map.of("result", payments.handleWebhook(provider, body, signature)));
    }

    /** Sandbox only: stands in for the hosted checkout page ("pay" or "decline"). Disabled when another provider is configured. */
    @PostMapping("/payments/{id}/sandbox-checkout") @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, String> sandbox(@PathVariable UUID id, @RequestParam(defaultValue = "true") boolean success) {
        return Map.of("result", payments.sandboxComplete(Auth.id(), id, success));
    }
}
