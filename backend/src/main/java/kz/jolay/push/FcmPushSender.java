package kz.jolay.push;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.jsonwebtoken.Jwts;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Primary;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.stereotype.Component;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.Date;
import java.util.Map;
import java.util.UUID;

/**
 * Firebase Cloud Messaging (HTTP v1) sender. ACTIVE ONLY when jolay.push.fcm.service-account-file points to a Google service-account JSON.
 * STATUS: request format is covered by a test against a local stub server; it has NOT been verified against Google's real endpoints (no credentials were available).
 */
@Component
@Primary
@ConditionalOnExpression("'${jolay.push.fcm.service-account-file:}' != ''")
public class FcmPushSender implements PushSender {
    private static final Logger log = LoggerFactory.getLogger(FcmPushSender.class);
    private final ObjectMapper mapper;
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();
    private final String projectId, clientEmail, tokenUri, sendBase;
    private final PrivateKey key;
    private volatile String accessToken;
    private volatile Instant expires = Instant.EPOCH;

    public FcmPushSender(ObjectMapper mapper, @Value("${jolay.push.fcm.service-account-file}") String file,
                         @Value("${jolay.push.fcm.send-base-url:https://fcm.googleapis.com}") String sendBase) throws Exception {
        this.mapper = mapper;
        JsonNode sa = mapper.readTree(Files.readString(Path.of(file)));
        this.projectId = sa.path("project_id").asText();
        this.clientEmail = sa.path("client_email").asText();
        this.tokenUri = sa.path("token_uri").asText("https://oauth2.googleapis.com/token");
        String pem = sa.path("private_key").asText().replaceAll("-----[A-Z ]+-----", "").replaceAll("\\s", "");
        this.key = KeyFactory.getInstance("RSA").generatePrivate(new PKCS8EncodedKeySpec(Base64.getDecoder().decode(pem)));
        this.sendBase = sendBase;
    }

    private synchronized String token() throws Exception {
        if (accessToken != null && Instant.now().isBefore(expires.minusSeconds(60))) return accessToken;
        Instant now = Instant.now();
        String assertion = Jwts.builder().issuer(clientEmail).claim("scope", "https://www.googleapis.com/auth/firebase.messaging").audience().add(tokenUri).and()
                .issuedAt(Date.from(now)).expiration(Date.from(now.plusSeconds(3600))).signWith(key, Jwts.SIG.RS256).compact();
        String form = "grant_type=" + URLEncoder.encode("urn:ietf:params:oauth:grant-type:jwt-bearer", StandardCharsets.UTF_8) + "&assertion=" + URLEncoder.encode(assertion, StandardCharsets.UTF_8);
        HttpResponse<String> r = http.send(HttpRequest.newBuilder(URI.create(tokenUri)).timeout(Duration.ofSeconds(10)).header("Content-Type", "application/x-www-form-urlencoded").POST(HttpRequest.BodyPublishers.ofString(form)).build(), HttpResponse.BodyHandlers.ofString());
        if (r.statusCode() != 200) throw new IllegalStateException("FCM token endpoint returned " + r.statusCode());
        JsonNode j = mapper.readTree(r.body());
        accessToken = j.path("access_token").asText();
        expires = now.plusSeconds(j.path("expires_in").asLong(3000));
        return accessToken;
    }

    @Override
    public boolean send(UUID userId, String deviceToken, String type, String title, String body, Map<String, String> data) {
        try {
            String payload = mapper.writeValueAsString(Map.of("message", Map.of("token", deviceToken, "notification", Map.of("title", title, "body", body), "data", data,
                    "android", Map.of("priority", "HIGH"), "apns", Map.of("headers", Map.of("apns-priority", "10")))));
            HttpResponse<String> r = http.send(HttpRequest.newBuilder(URI.create(sendBase + "/v1/projects/" + projectId + "/messages:send")).timeout(Duration.ofSeconds(10))
                    .header("Authorization", "Bearer " + token()).header("Content-Type", "application/json").POST(HttpRequest.BodyPublishers.ofString(payload)).build(), HttpResponse.BodyHandlers.ofString());
            if (r.statusCode() == 404 || r.statusCode() == 400 && r.body().contains("INVALID_ARGUMENT") && r.body().contains("registration token")) return false;   // unregistered / invalid token
            if (r.statusCode() / 100 != 2) log.warn("FCM send failed: HTTP {}", r.statusCode());
            return true;
        } catch (Exception e) { log.warn("FCM send error: {}", e.toString()); return true; }
    }
}
