package kz.jolay.identity;

import jakarta.validation.Valid;
import kz.jolay.identity.AuthDtos.*;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {
    private final AuthService auth;
    public AuthController(AuthService auth) { this.auth = auth; }

    @PostMapping("/register") @ResponseStatus(HttpStatus.CREATED)
    public RegisterResponse register(@Valid @RequestBody RegisterRequest r) { return auth.register(r); }

    @PostMapping("/resend-otp")
    public RegisterResponse resend(@Valid @RequestBody ResendRequest r) { return auth.resendOtp(r.phone()); }

    @PostMapping("/verify-otp")
    public TokenResponse verify(@Valid @RequestBody VerifyOtpRequest r) { return auth.verifyRegistration(r); }

    @PostMapping("/login")
    public TokenResponse login(@Valid @RequestBody LoginRequest r) { return auth.login(r); }

    @PostMapping("/refresh")
    public TokenResponse refresh(@Valid @RequestBody RefreshRequest r) { return auth.refresh(r.refreshToken()); }

    @PostMapping("/logout") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void logout(@Valid @RequestBody RefreshRequest r) { auth.logout(r.refreshToken()); }

    @PostMapping("/forgot-password") @ResponseStatus(HttpStatus.ACCEPTED)
    public void forgot(@Valid @RequestBody ForgotRequest r) { auth.forgotPassword(r.identifier()); }

    @PostMapping("/reset-password") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void reset(@Valid @RequestBody ResetRequest r) { auth.resetPassword(r); }
}
