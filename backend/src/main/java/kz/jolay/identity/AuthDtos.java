package kz.jolay.identity;

import jakarta.validation.constraints.*;

public final class AuthDtos {
    private AuthDtos() {}

    public record RegisterRequest(
            @NotBlank @Size(min = 2, max = 120) String fullName,
            @Email @Size(max = 254) String email,
            @NotBlank String phone,
            @NotBlank @Size(min = 8, max = 72) String password,
            @NotBlank @Pattern(regexp = "CUSTOMER|DRIVER|PARTNER") String role,
            @AssertTrue(message = "terms_not_accepted") boolean acceptTerms,
            @Pattern(regexp = "kk|ru|en") String locale,
            @Size(max = 20) String referralCode) {}
    public record VerifyOtpRequest(@NotBlank String phone, @NotBlank @Size(min = 4, max = 8) String code) {}
    public record LoginRequest(@NotBlank String identifier, @NotBlank String password, @Size(max = 20) String mfaCode) {}
    public record RefreshRequest(@NotBlank String refreshToken) {}
    public record ForgotRequest(@NotBlank String identifier) {}
    public record ResetRequest(@NotBlank String identifier, @NotBlank String code, @NotBlank @Size(min = 8, max = 72) String newPassword) {}
    public record ResendRequest(@NotBlank String phone) {}
    public record TokenResponse(String accessToken, String refreshToken, long expiresIn, UserView user) {}
    public record UserView(java.util.UUID id, String fullName, String phone, String email, java.util.Set<String> roles, String locale) {}
    public record RegisterResponse(String phone, int resendAfterSeconds) {}
}
