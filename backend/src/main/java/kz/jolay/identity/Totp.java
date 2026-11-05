package kz.jolay.identity;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.ByteBuffer;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;

/** RFC 6238 TOTP (HMAC-SHA1, 6 digits, 30 s) and RFC 4648 base32, without external dependencies. Compatible with Google Authenticator, Authy, 1Password etc. */
public final class Totp {
    private Totp() {}
    private static final String ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    public static final int STEP_SECONDS = 30;

    public static String newSecret() {
        byte[] b = new byte[20];
        new SecureRandom().nextBytes(b);
        return base32(b);
    }

    public static String base32(byte[] data) {
        StringBuilder out = new StringBuilder();
        int buffer = 0, bits = 0;
        for (byte x : data) {
            buffer = (buffer << 8) | (x & 0xff); bits += 8;
            while (bits >= 5) { out.append(ALPHABET.charAt((buffer >> (bits - 5)) & 31)); bits -= 5; }
        }
        if (bits > 0) out.append(ALPHABET.charAt((buffer << (5 - bits)) & 31));
        return out.toString();
    }

    public static byte[] fromBase32(String s) {
        String in = s.replace(" ", "").replace("=", "").toUpperCase();
        ByteBuffer out = ByteBuffer.allocate(in.length() * 5 / 8 + 1);
        int buffer = 0, bits = 0;
        for (char c : in.toCharArray()) {
            int v = ALPHABET.indexOf(c);
            if (v < 0) throw new IllegalArgumentException("not base32");
            buffer = (buffer << 5) | v; bits += 5;
            if (bits >= 8) { out.put((byte) ((buffer >> (bits - 8)) & 0xff)); bits -= 8; }
        }
        byte[] r = new byte[out.position()];
        out.flip(); out.get(r);
        return r;
    }

    public static String code(String base32Secret, long step) {
        try {
            Mac mac = Mac.getInstance("HmacSHA1");
            mac.init(new SecretKeySpec(fromBase32(base32Secret), "HmacSHA1"));
            byte[] h = mac.doFinal(ByteBuffer.allocate(8).putLong(step).array());
            int o = h[h.length - 1] & 0x0f;
            int bin = ((h[o] & 0x7f) << 24) | ((h[o + 1] & 0xff) << 16) | ((h[o + 2] & 0xff) << 8) | (h[o + 3] & 0xff);
            return String.format("%06d", bin % 1_000_000);
        } catch (GeneralSecurityException e) { throw new IllegalStateException(e); }
    }

    public static long stepAt(long epochSeconds) { return epochSeconds / STEP_SECONDS; }

    /** Returns the matching time step (within +-1 step of clock drift) or -1. Compares in constant time. */
    public static long verify(String base32Secret, String submitted, long nowStep) {
        if (submitted == null || !submitted.matches("\\d{6}")) return -1;
        long found = -1;
        for (long s = nowStep - 1; s <= nowStep + 1; s++) {
            if (java.security.MessageDigest.isEqual(code(base32Secret, s).getBytes(), submitted.getBytes())) found = s;
        }
        return found;
    }

    public static String otpauthUri(String issuer, String account, String secret) {
        String i = java.net.URLEncoder.encode(issuer, java.nio.charset.StandardCharsets.UTF_8).replace("+", "%20");
        String a = java.net.URLEncoder.encode(account, java.nio.charset.StandardCharsets.UTF_8).replace("+", "%20");
        return "otpauth://totp/" + i + ":" + a + "?secret=" + secret + "&issuer=" + i + "&algorithm=SHA1&digits=6&period=" + STEP_SECONDS;
    }
}
