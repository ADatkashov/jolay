package kz.jolay;

import org.junit.jupiter.api.Test;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.WebSocket;
import java.util.List;
import java.util.Map;
import java.util.concurrent.*;

import static org.junit.jupiter.api.Assertions.*;

/** WebSocket endpoint: authenticated handshake, per-user delivery of events after commit, ping/pong. */
class RealtimeIT extends IntegrationTestBase {

    /** Collects text frames from a JDK WebSocket client. */
    static class Collector implements WebSocket.Listener {
        final BlockingQueue<String> messages = new LinkedBlockingQueue<>();
        private final StringBuilder partial = new StringBuilder();
        @Override public CompletionStage<?> onText(WebSocket ws, CharSequence data, boolean last) {
            partial.append(data);
            if (last) { messages.add(partial.toString()); partial.setLength(0); }
            ws.request(1);
            return null;
        }
        @Override public void onOpen(WebSocket ws) { ws.request(1); }
        String next(long seconds) throws InterruptedException { return messages.poll(seconds, TimeUnit.SECONDS); }
    }

    private WebSocket connect(String query, Collector c) throws Exception {
        return HttpClient.newHttpClient().newWebSocketBuilder().buildAsync(URI.create("ws://localhost:" + port + "/ws" + query), c).get(10, TimeUnit.SECONDS);
    }

    @Test
    void handshakeRequiresAValidAccessToken() {
        assertThrows(ExecutionException.class, () -> connect("", new Collector()));
        assertThrows(ExecutionException.class, () -> connect("?token=not-a-jwt", new Collector()));
        Session c = customer();
        assertThrows(ExecutionException.class, () -> connect("?token=" + c.refresh(), new Collector()));   // a refresh token is not an access token
    }

    @Test
    void pingGetsPong() throws Exception {
        Session c = customer(); Collector col = new Collector();
        WebSocket ws = connect("?token=" + c.token(), col);
        ws.sendText("ping", true);
        assertEquals("pong", col.next(5));
        ws.sendClose(WebSocket.NORMAL_CLOSURE, "bye").get(5, TimeUnit.SECONDS);
    }

    @Test
    void eventsReachOnlyTheirAddresseeAfterTheTransactionCommits() throws Exception {
        Session c = customer(); Session other = customer(); Session d = driver("ECONOMY", 43.2336, 76.9568);
        Collector mine = new Collector(), theirs = new Collector(), driverCol = new Collector();
        WebSocket w1 = connect("?token=" + c.token(), mine), w2 = connect("?token=" + other.token(), theirs), w3 = connect("?token=" + d.token(), driverCol);

        String rideId = requestRide(c, "ECONOMY", "CASH").s("id");
        String offerJson = driverCol.next(10);                                   // the driver is told about the offer
        assertNotNull(offerJson, "driver should receive the ride offer");
        assertTrue(offerJson.contains("RIDE_OFFER"), offerJson);

        post("/api/v1/drivers/offers/" + currentOfferId(d) + "/accept", d.token(), null);
        String got = mine.next(10);                                              // the customer is told the driver was found
        assertNotNull(got, "customer should be told about the accepted ride");
        var json = mapper.readTree(got);
        assertEquals("DRIVER_ACCEPTED", json.path("type").asText(), got);
        assertEquals(rideId, json.path("data").path("rideId").asText());
        assertTrue(json.has("ts"));
        // the committed state matches what the event announced
        assertEquals("DRIVER_ASSIGNED", get("/api/v1/rides/" + rideId, c.token()).s("status"));

        assertNull(theirs.next(2), "another customer must not receive someone else's events");
        for (WebSocket w : List.of(w1, w2, w3)) w.sendClose(WebSocket.NORMAL_CLOSURE, "bye");
    }

    @Test
    void closedSocketsAreForgottenAndMultipleDevicesAllReceive() throws Exception {
        Session c = customer(); Session d = driver("ECONOMY", 43.2336, 76.9568);
        Collector a = new Collector(), b = new Collector();
        WebSocket wa = connect("?token=" + c.token(), a), wb = connect("?token=" + c.token(), b);     // two devices
        requestRide(c, "ECONOMY", "CASH");
        post("/api/v1/drivers/offers/" + currentOfferId(d) + "/accept", d.token(), null);
        assertNotNull(a.next(10)); assertNotNull(b.next(10));
        wa.sendClose(WebSocket.NORMAL_CLOSURE, "bye").get(5, TimeUnit.SECONDS);
        wb.sendClose(WebSocket.NORMAL_CLOSURE, "bye").get(5, TimeUnit.SECONDS);
        // publishing to a user with no open sockets must not fail the REST call
        assertEquals(200, post("/api/v1/drivers/rides/" + get("/api/v1/rides/active", c.token()).s("id") + "/en-route", d.token(), null).status());
    }
}
