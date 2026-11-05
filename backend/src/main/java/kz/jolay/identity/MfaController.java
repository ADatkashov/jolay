package kz.jolay.identity;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import kz.jolay.common.Auth;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/** Staff two-factor management. Requires a normal access token; deliberately outside /auth/** (which is public). */
@RestController
@RequestMapping("/api/v1/account/mfa")
public class MfaController {
    private final MfaService mfa;
    private final AuthService auth;
    public MfaController(MfaService mfa, AuthService auth) { this.mfa = mfa; this.auth = auth; }

    public record CodeRequest(@NotBlank @Size(max = 20) String code) {}
    public record DisableRequest(@NotBlank String password, @NotBlank @Size(max = 20) String code) {}

    @GetMapping
    public Map<String, Object> status() { return mfa.status(Auth.id()); }

    @PostMapping("/setup")
    public Map<String, Object> setup() {
        var u = auth.userView(Auth.id());
        return mfa.setup(Auth.id(), u.roles(), u.email() != null ? u.email() : u.phone());
    }

    @PostMapping("/enable")
    public Map<String, Object> enable(@Valid @RequestBody CodeRequest r) {
        List<String> codes = mfa.enable(Auth.id(), r.code());
        return Map.of("enabled", true, "recoveryCodes", codes);
    }

    @PostMapping("/disable")
    public Map<String, Object> disable(@Valid @RequestBody DisableRequest r) {
        mfa.disable(Auth.id(), r.password(), r.code());
        return Map.of("enabled", false);
    }
}
