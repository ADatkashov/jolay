package kz.jolay.identity;

import kz.jolay.common.ApiException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/** Optional TOTP second factor for staff (any *_ADMIN role or SUPPORT_AGENT). Login without a valid code is refused once it is enabled. */
@Service
public class MfaService {
    private static final SecureRandom RNG = new SecureRandom();
    private static final String RECOVERY_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
    private final JdbcClient jdbc;
    private final PasswordEncoder encoder;
    private final byte[] key;

    public MfaService(JdbcClient jdbc, PasswordEncoder encoder, SecurityProps props, @Value("${jolay.security.mfa-key:}") String mfaKey) {
        this.jdbc = jdbc; this.encoder = encoder;
        this.key = sha256Bytes((mfaKey == null || mfaKey.isBlank() ? props.jwtSecret() : mfaKey) + "|mfa-secret-encryption");
    }

    public static boolean isStaff(Set<String> roles) { return roles.stream().anyMatch(r -> r.endsWith("_ADMIN") || r.equals("SUPPORT_AGENT")); }

    public boolean enabled(UUID userId) {
        return jdbc.sql("SELECT mfa_enabled_at IS NOT NULL FROM users WHERE id=:id").param("id", userId).query(Boolean.class).optional().orElse(false);
    }

    public Map<String, Object> status(UUID userId) {
        int left = jdbc.sql("SELECT count(*) FROM mfa_recovery_codes WHERE user_id=:u AND used_at IS NULL").param("u", userId).query(Integer.class).single();
        boolean required = "true".equals(jdbc.sql("SELECT value FROM application_settings WHERE key='security.staff_mfa_required'").query(String.class).optional().orElse("false"));
        Set<String> roles = Set.copyOf(jdbc.sql("SELECT role FROM user_roles WHERE user_id=:u").param("u", userId).query(String.class).list());
        boolean mustEnrol = required && roles.stream().anyMatch(JwtAuthFilter.MFA_ENFORCED_ROLES::contains) && !enabled(userId);
        return Map.of("enabled", enabled(userId), "recoveryCodesLeft", left, "enrolmentRequired", mustEnrol);
    }

    /** Step 1: creates a pending secret (replacing any earlier pending one). Nothing is enforced until {@link #enable} confirms a code. */
    @Transactional
    public Map<String, Object> setup(UUID userId, Set<String> roles, String accountLabel) {
        if (!isStaff(roles)) throw ApiException.forbidden("mfa_staff_only", "Two-factor authentication is available for staff accounts");
        if (enabled(userId)) throw ApiException.conflict("mfa_already_enabled", "Two-factor authentication is already enabled");
        String secret = Totp.newSecret();
        jdbc.sql("UPDATE users SET mfa_pending_enc=:s WHERE id=:id").param("s", encrypt(secret)).param("id", userId).update();
        return Map.of("secret", secret, "otpauthUri", Totp.otpauthUri("JOLAY", accountLabel, secret));
    }

    /** Step 2: the user proves their authenticator works. Returns single-use recovery codes, shown exactly once. */
    @Transactional
    public List<String> enable(UUID userId, String code) {
        String pending = jdbc.sql("SELECT mfa_pending_enc FROM users WHERE id=:id FOR UPDATE").param("id", userId).query(String.class).optional().orElse(null);
        if (pending == null) throw ApiException.conflict("mfa_not_started", "Start the setup first");
        long step = Totp.verify(decrypt(pending), code, Totp.stepAt(Instant.now().getEpochSecond()));
        if (step < 0) throw ApiException.badRequest("invalid_mfa_code", "The code is not valid");
        jdbc.sql("UPDATE users SET mfa_secret_enc=mfa_pending_enc, mfa_pending_enc=NULL, mfa_enabled_at=now(), mfa_last_step=:s WHERE id=:id").param("s", step).param("id", userId).update();
        jdbc.sql("DELETE FROM mfa_recovery_codes WHERE user_id=:u").param("u", userId).update();
        List<String> codes = new ArrayList<>();
        for (int i = 0; i < 8; i++) {
            String c = randomRecovery();
            codes.add(c);
            jdbc.sql("INSERT INTO mfa_recovery_codes(user_id, code_hash) VALUES (:u,:h)").param("u", userId).param("h", hash(c)).update();
        }
        return codes;
    }

    /** Turning it off needs the current password and a valid code, so a stolen session alone cannot remove the second factor. */
    @Transactional
    public void disable(UUID userId, String password, String code) {
        String hashPw = jdbc.sql("SELECT password_hash FROM users WHERE id=:id").param("id", userId).query(String.class).single();
        if (!encoder.matches(password, hashPw)) throw ApiException.unauthorized("invalid_credentials", "Invalid credentials");
        if (!verifyLogin(userId, code)) throw ApiException.badRequest("invalid_mfa_code", "The code is not valid");
        jdbc.sql("UPDATE users SET mfa_secret_enc=NULL, mfa_pending_enc=NULL, mfa_enabled_at=NULL, mfa_last_step=0 WHERE id=:id").param("id", userId).update();
        jdbc.sql("DELETE FROM mfa_recovery_codes WHERE user_id=:u").param("u", userId).update();
    }

    /** True when the code is a fresh TOTP (not replayed) or an unused recovery code (which is consumed). */
    @Transactional
    public boolean verifyLogin(UUID userId, String rawCode) {
        if (rawCode == null || rawCode.isBlank()) return false;
        String code = rawCode.trim();
        var row = jdbc.sql("SELECT mfa_secret_enc, mfa_last_step FROM users WHERE id=:id FOR UPDATE").param("id", userId).query().listOfRows().stream().findFirst().orElse(null);
        if (row == null || row.get("mfa_secret_enc") == null) return false;
        if (code.matches("\\d{6}")) {
            long step = Totp.verify(decrypt((String) row.get("mfa_secret_enc")), code, Totp.stepAt(Instant.now().getEpochSecond()));
            if (step < 0 || step <= (Long) row.get("mfa_last_step")) return false;       // wrong, or the same/older step was already used
            jdbc.sql("UPDATE users SET mfa_last_step=:s WHERE id=:id").param("s", step).param("id", userId).update();
            return true;
        }
        String normalized = code.replace("-", "").replace(" ", "").toUpperCase();
        return jdbc.sql("UPDATE mfa_recovery_codes SET used_at=now() WHERE user_id=:u AND code_hash=:h AND used_at IS NULL").param("u", userId).param("h", hash(normalized)).update() == 1;
    }

    private static String randomRecovery() {
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < 10; i++) { if (i == 5) b.append('-'); b.append(RECOVERY_ALPHABET.charAt(RNG.nextInt(RECOVERY_ALPHABET.length()))); }
        return b.toString();
    }
    private static String hash(String normalizedOrDashed) { return HexFormat.of().formatHex(sha256Bytes(normalizedOrDashed.replace("-", "").toUpperCase())); }
    private static byte[] sha256Bytes(String s) {
        try { return MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8)); } catch (GeneralSecurityException e) { throw new IllegalStateException(e); }
    }

    private String encrypt(String plain) {
        try {
            byte[] iv = new byte[12]; RNG.nextBytes(iv);
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(key, "AES"), new GCMParameterSpec(128, iv));
            byte[] ct = c.doFinal(plain.getBytes(StandardCharsets.UTF_8));
            byte[] all = new byte[iv.length + ct.length];
            System.arraycopy(iv, 0, all, 0, iv.length); System.arraycopy(ct, 0, all, iv.length, ct.length);
            return Base64.getEncoder().encodeToString(all);
        } catch (GeneralSecurityException e) { throw new IllegalStateException(e); }
    }
    private String decrypt(String enc) {
        try {
            byte[] all = Base64.getDecoder().decode(enc);
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.DECRYPT_MODE, new SecretKeySpec(key, "AES"), new GCMParameterSpec(128, all, 0, 12));
            return new String(c.doFinal(all, 12, all.length - 12), StandardCharsets.UTF_8);
        } catch (GeneralSecurityException e) { throw ApiException.conflict("mfa_unreadable", "Two-factor data cannot be decrypted (key changed?). Ask a super administrator to reset it"); }
    }
}
