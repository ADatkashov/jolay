package kz.jolay.identity;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.List;
import java.util.Map;

/**
 * WhatsApp Business Cloud API (Meta) client. Sends one approved template whose single body variable {{1}} carries the message text
 * (business-initiated messages outside the 24h window must be templates). {@link #send} returns false for ANY failure — recipient not on
 * WhatsApp (error 131026 / 131030), template rejected, network error, timeout — so the caller can fall back to SMS. The token and the
 * recipient number are never logged in full.
 * <p>
 * NOT yet verified against a live Meta account. Known limit: the API accepts the message synchronously, but "undeliverable" can also
 * arrive later as a status webhook; that asynchronous case is not handled here (see docs/DEPLOYMENT.md).
 */
public class WhatsAppClient {
    private static final Logger log = LoggerFactory.getLogger(WhatsAppClient.class);

    private final String baseUrl, phoneNumberId, token, template, language;
    private final Duration timeout;
    private final HttpClient http;
    private final ObjectMapper mapper;

    public WhatsAppClient(String baseUrl, String phoneNumberId, String token, String template, String language, Duration timeout, ObjectMapper mapper) {
        this.baseUrl = baseUrl.endsWith("/") ? baseUrl.substring(0, baseUrl.length() - 1) : baseUrl;
        this.phoneNumberId = phoneNumberId; this.token = token; this.template = template; this.language = language;
        this.timeout = timeout; this.mapper = mapper;
        this.http = HttpClient.newBuilder().connectTimeout(timeout).build();
    }

    /** @return true when WhatsApp accepted the message for this number. */
    public boolean send(String phone, String text) {
        String to = phone.replace("+", "");
        try {
            // Template variables may not contain newlines/tabs or runs of 4+ spaces.
            String param = text.replaceAll("[\\r\\n\\t]+", " ").replaceAll(" {4,}", "   ");
            Map<String, Object> body = Map.of(
                    "messaging_product", "whatsapp", "to", to, "type", "template",
                    "template", Map.of("name", template, "language", Map.of("code", language),
                            "components", List.of(Map.of("type", "body", "parameters", List.of(Map.of("type", "text", "text", param))))));
            HttpRequest req = HttpRequest.newBuilder(URI.create(baseUrl + "/" + phoneNumberId + "/messages")).timeout(timeout)
                    .header("Authorization", "Bearer " + token).header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(mapper.writeValueAsString(body))).build();
            HttpResponse<String> res = http.send(req, HttpResponse.BodyHandlers.ofString());
            if (res.statusCode() / 100 == 2) return true;
            String code = "?";
            try { JsonNode err = mapper.readTree(res.body()).path("error"); code = err.path("code").asText("?"); } catch (Exception ignored) { /* non-JSON error body */ }
            log.info("WhatsApp not delivered to {} (http {}, code {}); falling back to SMS", mask(phone), res.statusCode(), code);
            return false;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return false;
        } catch (Exception e) {
            log.warn("WhatsApp send to {} failed ({}); falling back to SMS", mask(phone), e.getClass().getSimpleName());
            return false;
        }
    }

    private static String mask(String phone) {
        return phone.length() > 6 ? phone.substring(0, 4) + "****" + phone.substring(phone.length() - 2) : "****";
    }
}
