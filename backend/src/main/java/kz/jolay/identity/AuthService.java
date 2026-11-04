package kz.jolay.identity;

import kz.jolay.common.ApiException;
import kz.jolay.identity.AuthDtos.*;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Base64;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Pattern;

@Service
public class AuthService {
    private static final Pattern E164 = Pattern.compile("^\\+[1-9]\\d{9,14}$");
    private static final SecureRandom RNG = new SecureRandom();

    private final JdbcClient jdbc;
    private final PasswordEncoder encoder;
    private final JwtService jwt;
    private final SecurityProps props;
    private final SmsSender sms;
    private final Map<String, int[]> failures = new ConcurrentHashMap<>();       // identifier -> [count]
    private final Map<String, Instant> lockedUntil = new ConcurrentHashMap<>();

    public AuthService(JdbcClient jdbc, PasswordEncoder encoder, JwtService jwt, SecurityProps props, SmsSender sms) {
        this.jdbc = jdbc; this.encoder = encoder; this.jwt = jwt; this.props = props; this.sms = sms;
    }

    // ---------- helpers ----------
    public static String normalizePhone(String raw) {
        String p = raw == null ? "" : raw.replaceAll("[\\s()\\-]", "");
        if (p.matches("^8\\d{10}$")) p = "+7" + p.substring(1);        // KZ/RU national format 8XXXXXXXXXX
        else if (p.matches("^7\\d{10}$")) p = "+" + p;
        if (!E164.matcher(p).matches()) throw ApiException.badRequest("invalid_phone", "Phone number must be in international format");
        return p;
    }

    static void checkPasswordPolicy(String pw) {
        if (pw.length() < 8 || !pw.matches(".*[A-Za-z\\p{L}].*") || !pw.matches(".*\\d.*"))
            throw ApiException.badRequest("weak_password", "Password must be at least 8 characters and contain a letter and a digit");
    }

    private static String sha256(String s) {
        try { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8))); }
        catch (NoSuchAlgorithmException e) { throw new IllegalStateException(e); }
    }
    private String otpHash(String phone, String code) { return sha256(props.jwtSecret() + "|" + phone + "|" + code); }

    // ---------- registration & OTP ----------
    @Transactional
    public RegisterResponse register(RegisterRequest r) {
        String phone = normalizePhone(r.phone());
        checkPasswordPolicy(r.password());
        String email = r.email() == null || r.email().isBlank() ? null : r.email().trim().toLowerCase();

        Optional<Map<String, Object>> existing = jdbc.sql("SELECT id, phone_verified FROM users WHERE phone=:p AND deleted_at IS NULL")
                .param("p", phone).query().listOfRows().stream().findFirst();
        if (existing.isPresent() && (Boolean) existing.get().get("phone_verified"))
            throw ApiException.conflict("phone_taken", "An account with this phone already exists");
        if (email != null && jdbc.sql("SELECT count(*) FROM users WHERE lower(email)=:e AND deleted_at IS NULL AND phone<>:p")
                .param("e", email).param("p", phone).query(Integer.class).single() > 0)
            throw ApiException.conflict("email_taken", "An account with this email already exists");

        String locale = r.locale() == null ? "kk" : r.locale();
        UUID id;
        if (existing.isPresent()) {                                     // re-registration of an unverified number
            id = (UUID) existing.get().get("id");
            jdbc.sql("UPDATE users SET full_name=:n,email=:e,password_hash=:h,locale=:l,terms_accepted_at=now(),updated_at=now() WHERE id=:id")
                    .param("n", r.fullName().trim()).param("e", email).param("h", encoder.encode(r.password())).param("l", locale).param("id", id).update();
            jdbc.sql("DELETE FROM user_roles WHERE user_id=:id").param("id", id).update();
        } else {
            id = jdbc.sql("INSERT INTO users(phone,email,password_hash,full_name,locale,terms_accepted_at) VALUES (:p,:e,:h,:n,:l,now()) RETURNING id")
                    .param("p", phone).param("e", email).param("h", encoder.encode(r.password())).param("n", r.fullName().trim()).param("l", locale)
                    .query(UUID.class).single();
        }
        jdbc.sql("INSERT INTO user_roles(user_id, role) VALUES (:id,:r)").param("id", id).param("r", r.role()).update();
        sendOtp(phone, "REGISTER");
        return new RegisterResponse(phone, 60);
    }

    @Transactional
    public RegisterResponse resendOtp(String rawPhone) {
        String phone = normalizePhone(rawPhone);
        boolean pending = jdbc.sql("SELECT count(*) FROM users WHERE phone=:p AND NOT phone_verified AND deleted_at IS NULL").param("p", phone).query(Integer.class).single() > 0;
        if (pending) sendOtp(phone, "REGISTER");                         // silent no-op otherwise: don't reveal account existence
        return new RegisterResponse(phone, 60);
    }

    private void sendOtp(String phone, String purpose) {
        int sent = jdbc.sql("SELECT count(*) FROM otp_verifications WHERE phone=:p AND created_at > now() - interval '1 hour'")
                .param("p", phone).query(Integer.class).single();
        if (sent >= props.otpMaxPerHour()) throw ApiException.tooMany("otp_rate_limited", "Too many verification codes requested. Try later");
        Instant last = jdbc.sql("SELECT max(created_at) FROM otp_verifications WHERE phone=:p").param("p", phone)
                .query((rs, i) -> rs.getTimestamp(1) == null ? null : rs.getTimestamp(1).toInstant()).optional().orElse(null);
        if (last != null && last.isAfter(Instant.now().minusSeconds(30))) throw ApiException.tooMany("otp_too_soon", "Please wait before requesting another code");
        StringBuilder code = new StringBuilder();
        for (int i = 0; i < props.otpLength(); i++) code.append(RNG.nextInt(10));
        jdbc.sql("UPDATE otp_verifications SET consumed_at=now() WHERE phone=:p AND consumed_at IS NULL").param("p", phone).update();
        jdbc.sql("INSERT INTO otp_verifications(phone,purpose,code_hash,expires_at) VALUES (:p,:pu,:h,:e)")
                .param("p", phone).param("pu", purpose).param("h", otpHash(phone, code.toString()))
                .param("e", OffsetDateTime.now(ZoneOffset.UTC).plus(props.otpTtl())).update();
        sms.send(phone, "JOLAY: " + code + " - your verification code. Do not share it.");
    }

    /** Verifies and consumes an OTP. Failed attempts are committed (noRollbackFor) so the limit is enforced. */
    @Transactional(noRollbackFor = ApiException.class)
    public void consumeOtp(String phone, String code, String purpose) {
        var row = jdbc.sql("SELECT id, code_hash, attempts FROM otp_verifications WHERE phone=:p AND purpose=:pu AND consumed_at IS NULL AND expires_at > now() ORDER BY created_at DESC LIMIT 1 FOR UPDATE")
                .param("p", phone).param("pu", purpose).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.badRequest("otp_invalid", "Invalid or expired code"));
        UUID id = (UUID) row.get("id");
        if ((Integer) row.get("attempts") >= props.otpMaxAttempts()) {
            jdbc.sql("UPDATE otp_verifications SET consumed_at=now() WHERE id=:id").param("id", id).update();
            throw ApiException.tooMany("otp_attempts_exceeded", "Too many attempts. Request a new code");
        }
        boolean ok = MessageDigest.isEqual(((String) row.get("code_hash")).getBytes(StandardCharsets.UTF_8), otpHash(phone, code).getBytes(StandardCharsets.UTF_8));
        if (!ok) {
            jdbc.sql("UPDATE otp_verifications SET attempts=attempts+1 WHERE id=:id").param("id", id).update();
            throw ApiException.badRequest("otp_invalid", "Invalid or expired code");
        }
        jdbc.sql("UPDATE otp_verifications SET consumed_at=now() WHERE id=:id").param("id", id).update();
    }

    @Transactional(noRollbackFor = ApiException.class)
    public TokenResponse verifyRegistration(VerifyOtpRequest r) {
        String phone = normalizePhone(r.phone());
        consumeOtp(phone, r.code(), "REGISTER");
        UUID id = jdbc.sql("UPDATE users SET phone_verified=true, updated_at=now() WHERE phone=:p AND deleted_at IS NULL RETURNING id")
                .param("p", phone).query(UUID.class).optional().orElseThrow(() -> ApiException.badRequest("otp_invalid", "Invalid or expired code"));
        return issueTokens(id, UUID.randomUUID());
    }

    // ---------- login / tokens ----------
    @Transactional
    public TokenResponse login(LoginRequest r) {
        String ident = r.identifier().trim().toLowerCase();
        Instant lock = lockedUntil.get(ident);
        if (lock != null && lock.isAfter(Instant.now())) throw ApiException.tooMany("login_locked", "Too many failed attempts. Try again later");

        String col, value;
        if (ident.contains("@")) { col = "lower(email)"; value = ident; }
        else { col = "phone"; value = normalizePhone(ident); }
        var user = jdbc.sql("SELECT id, password_hash, status, phone_verified FROM users WHERE " + col + "=:v AND deleted_at IS NULL")
                .param("v", value).query().listOfRows().stream().findFirst();
        boolean ok = user.isPresent() && encoder.matches(r.password(), (String) user.get().get("password_hash"));
        if (!ok) {
            int[] c = failures.computeIfAbsent(ident, k -> new int[1]);
            if (++c[0] >= props.loginMaxFailures()) { lockedUntil.put(ident, Instant.now().plus(props.loginLockout())); c[0] = 0; }
            throw ApiException.unauthorized("invalid_credentials", "Invalid credentials");
        }
        failures.remove(ident); lockedUntil.remove(ident);
        if ("SUSPENDED".equals(user.get().get("status"))) throw ApiException.forbidden("account_suspended", "Account is suspended");
        if (!(Boolean) user.get().get("phone_verified")) throw ApiException.forbidden("phone_not_verified", "Phone number is not verified");
        return issueTokens((UUID) user.get().get("id"), UUID.randomUUID());
    }

    @Transactional(noRollbackFor = ApiException.class)
    public TokenResponse refresh(String refreshToken) {
        String hash = sha256(refreshToken);
        var row = jdbc.sql("SELECT id, user_id, family_id, revoked_at, expires_at > now() AS valid FROM refresh_tokens WHERE token_hash=:h FOR UPDATE")
                .param("h", hash).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.unauthorized("invalid_refresh", "Invalid refresh token"));
        UUID family = (UUID) row.get("family_id");
        if (row.get("revoked_at") != null) {                             // reuse of a rotated token => assume theft, kill the family
            jdbc.sql("UPDATE refresh_tokens SET revoked_at=now() WHERE family_id=:f AND revoked_at IS NULL").param("f", family).update();
            throw ApiException.unauthorized("refresh_reuse", "Refresh token reuse detected");
        }
        if (!(Boolean) row.get("valid")) throw ApiException.unauthorized("invalid_refresh", "Invalid refresh token");
        jdbc.sql("UPDATE refresh_tokens SET revoked_at=now() WHERE id=:id").param("id", row.get("id")).update();
        UUID userId = (UUID) row.get("user_id");
        boolean active = jdbc.sql("SELECT status='ACTIVE' FROM users WHERE id=:id AND deleted_at IS NULL").param("id", userId).query(Boolean.class).optional().orElse(false);
        if (!active) throw ApiException.forbidden("account_suspended", "Account is not active");
        return issueTokens(userId, family);
    }

    @Transactional
    public void logout(String refreshToken) {
        jdbc.sql("UPDATE refresh_tokens SET revoked_at=now() WHERE token_hash=:h AND revoked_at IS NULL").param("h", sha256(refreshToken)).update();
    }

    private TokenResponse issueTokens(UUID userId, UUID family) {
        byte[] raw = new byte[32];
        RNG.nextBytes(raw);
        String refresh = Base64.getUrlEncoder().withoutPadding().encodeToString(raw);
        jdbc.sql("INSERT INTO refresh_tokens(user_id,family_id,token_hash,expires_at) VALUES (:u,:f,:h,:e)")
                .param("u", userId).param("f", family).param("h", sha256(refresh))
                .param("e", OffsetDateTime.now(ZoneOffset.UTC).plus(props.refreshTtl())).update();
        UserView view = userView(userId);
        return new TokenResponse(jwt.issueAccess(userId, view.roles()), refresh, jwt.accessTtlSeconds(), view);
    }

    public UserView userView(UUID id) {
        var u = jdbc.sql("SELECT id, full_name, phone, email, locale FROM users WHERE id=:id").param("id", id).query().listOfRows().get(0);
        Set<String> roles = Set.copyOf(jdbc.sql("SELECT role FROM user_roles WHERE user_id=:id").param("id", id).query(String.class).list());
        return new UserView(id, (String) u.get("full_name"), (String) u.get("phone"), (String) u.get("email"), roles, (String) u.get("locale"));
    }

    // ---------- password recovery ----------
    @Transactional
    public void forgotPassword(String identifier) {
        String ident = identifier.trim().toLowerCase();
        String col = ident.contains("@") ? "lower(email)" : "phone";
        String value;
        try { value = ident.contains("@") ? ident : normalizePhone(ident); } catch (ApiException e) { return; }
        List<String> phones = jdbc.sql("SELECT phone FROM users WHERE " + col + "=:v AND phone_verified AND status='ACTIVE' AND deleted_at IS NULL")
                .param("v", value).query(String.class).list();
        // Response is identical whether or not the account exists (no user enumeration).
        for (String p : phones) {
            try { sendOtp(p, "RESET"); } catch (ApiException ignored) { /* rate limited: stay silent */ }
        }
    }

    @Transactional(noRollbackFor = ApiException.class)
    public void resetPassword(ResetRequest r) {
        checkPasswordPolicy(r.newPassword());
        String ident = r.identifier().trim().toLowerCase();
        String phone = ident.contains("@")
                ? jdbc.sql("SELECT phone FROM users WHERE lower(email)=:e AND deleted_at IS NULL").param("e", ident).query(String.class).optional()
                        .orElseThrow(() -> ApiException.badRequest("otp_invalid", "Invalid or expired code"))
                : normalizePhone(ident);
        consumeOtp(phone, r.code(), "RESET");
        UUID id = jdbc.sql("UPDATE users SET password_hash=:h, updated_at=now() WHERE phone=:p AND deleted_at IS NULL RETURNING id")
                .param("h", encoder.encode(r.newPassword())).param("p", phone).query(UUID.class).single();
        jdbc.sql("UPDATE refresh_tokens SET revoked_at=now() WHERE user_id=:u AND revoked_at IS NULL").param("u", id).update();
    }
}
