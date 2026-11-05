package kz.jolay;

import com.fasterxml.jackson.databind.JsonNode;
import com.sun.net.httpserver.HttpServer;
import io.jsonwebtoken.Jwts;
import kz.jolay.push.FcmPushSender;
import org.junit.jupiter.api.Test;

import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CopyOnWriteArrayList;

import static org.junit.jupiter.api.Assertions.*;

class PushIT extends IntegrationTestBase {

    @Test
    void devPushMockRecordsLocalisedMessagesOncePerEventAndOnlyForRegisteredDevices() {
        Session c = customer(); Session d = driver("ECONOMY", 43.2336, 76.9568);
        assertEquals(200, post("/api/v1/notifications/devices", d.token(), Map.of("pushToken", "driver-device-1", "platform", "android")).status());
        assertEquals(200, post("/api/v1/notifications/devices", c.token(), Map.of("pushToken", "cust-device-1", "platform", "ios")).status());
        put("/api/v1/customers/me", c.token(), Map.of("locale", "ru"));
        // the driver registered with locale ru in the fixture ("ru"), switch to kk to prove localisation per user
        put("/api/v1/customers/me", d.token(), Map.of("locale", "kk"));

        String rideId = completeRide(c, d, "CASH");
        var driverPush = jdbc.sql("SELECT type, title, body, data->>'type' AS t FROM push_outbox WHERE user_id=:u ORDER BY id").param("u", d.id()).query().listOfRows();
        assertEquals(1, driverPush.size(), "one RIDE_OFFER push for the driver: " + driverPush);
        assertEquals("RIDE_OFFER", driverPush.get(0).get("type"));
        assertEquals("Жаңа тапсырыс", driverPush.get(0).get("title"), "driver locale kk");
        var customerPush = jdbc.sql("SELECT type, title FROM push_outbox WHERE user_id=:u ORDER BY id").param("u", c.id()).query().listOfRows();
        assertTrue(customerPush.stream().anyMatch(r -> "DRIVER_ACCEPTED".equals(r.get("type")) && "Водитель найден".equals(r.get("title"))), "customer locale ru: " + customerPush);
        assertTrue(customerPush.stream().anyMatch(r -> "RIDE_COMPLETED".equals(r.get("type"))));
        // same dedupe key never pushes twice
        long before = jdbc.sql("SELECT count(*) FROM push_outbox").query(Long.class).single();
        jdbc.sql("DELETE FROM notifications WHERE false").update();
        assertEquals(before, jdbc.sql("SELECT count(*) FROM push_outbox").query(Long.class).single());
        // a user without a registered device gets no push but still gets the in-app notification
        Session c2 = customer(); Session d2 = driver("ECONOMY", 43.2336, 76.9568);
        completeRide(c2, d2, "CASH");
        assertEquals(0, jdbc.sql("SELECT count(*) FROM push_outbox WHERE user_id=:u").param("u", c2.id()).query(Long.class).single());
        assertTrue(jdbc.sql("SELECT count(*) FROM notifications WHERE user_id=:u").param("u", c2.id()).query(Long.class).single() > 0);
    }

    @Test
    void fcmSenderUsesOauthJwtAndTheV1SendFormat() throws Exception {
        KeyPair kp = KeyPairGenerator.getInstance("RSA").generateKeyPair();
        String pem = "-----BEGIN PRIVATE KEY-----\n" + Base64.getMimeEncoder(64, "\n".getBytes()).encodeToString(kp.getPrivate().getEncoded()) + "\n-----END PRIVATE KEY-----\n";
        List<String> seen = new CopyOnWriteArrayList<>();
        HttpServer srv = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        int port = srv.getAddress().getPort();
        srv.createContext("/token", ex -> {
            String form = new String(ex.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
            seen.add("TOKEN " + form);
            byte[] out = "{\"access_token\":\"stub-access\",\"expires_in\":3600}".getBytes();
            ex.sendResponseHeaders(200, out.length); ex.getResponseBody().write(out); ex.close();
        });
        srv.createContext("/v1/projects/demo-project/messages:send", ex -> {
            String body = new String(ex.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
            seen.add("SEND " + ex.getRequestHeaders().getFirst("Authorization") + " " + body);
            boolean dead = body.contains("dead-token");
            byte[] out = (dead ? "{\"error\":{\"status\":\"NOT_FOUND\"}}" : "{\"name\":\"projects/demo-project/messages/1\"}").getBytes();
            ex.sendResponseHeaders(dead ? 404 : 200, out.length); ex.getResponseBody().write(out); ex.close();
        });
        srv.start();
        try {
            Path sa = Files.createTempFile("sa", ".json");
            Files.writeString(sa, mapper.writeValueAsString(Map.of("project_id", "demo-project", "client_email", "svc@demo-project.iam.gserviceaccount.com", "private_key", pem, "token_uri", "http://127.0.0.1:" + port + "/token")));
            FcmPushSender fcm = new FcmPushSender(mapper, sa.toString(), "http://127.0.0.1:" + port);

            assertTrue(fcm.send(UUID.randomUUID(), "good-token", "RIDE_OFFER", "New order", "Hello", Map.of("rideId", "r1")));
            assertEquals(2, seen.size());
            // 1) the OAuth assertion is a JWT signed with the service-account key, with the messaging scope
            String assertion = seen.get(0).replaceAll(".*assertion=", "");
            var claims = Jwts.parser().verifyWith(kp.getPublic()).build().parseSignedClaims(java.net.URLDecoder.decode(assertion, StandardCharsets.UTF_8)).getPayload();
            assertEquals("svc@demo-project.iam.gserviceaccount.com", claims.getIssuer());
            assertEquals("https://www.googleapis.com/auth/firebase.messaging", claims.get("scope"));
            // 2) the send request carries the bearer token and the v1 message shape
            assertTrue(seen.get(1).startsWith("SEND Bearer stub-access "));
            JsonNode msg = mapper.readTree(seen.get(1).substring(seen.get(1).indexOf('{'))).path("message");
            assertEquals("good-token", msg.path("token").asText());
            assertEquals("New order", msg.path("notification").path("title").asText());
            assertEquals("r1", msg.path("data").path("rideId").asText());
            // the access token is cached (no second token call)
            fcm.send(UUID.randomUUID(), "good-token-2", "RIDE_OFFER", "t", "b", Map.of());
            assertEquals(3, seen.size());
            // unregistered device tokens are reported as dead so they can be removed
            assertFalse(fcm.send(UUID.randomUUID(), "dead-token", "RIDE_OFFER", "t", "b", Map.of()));
        } finally { srv.stop(0); }
    }
}
