package kz.jolay;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import kz.jolay.identity.WhatsAppClient;
import kz.jolay.identity.WhatsAppFirstSender;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.net.InetSocketAddress;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.*;

class WhatsAppFirstSenderTest {
    private HttpServer server;
    private int status;
    private final AtomicReference<String> lastBody = new AtomicReference<>();
    private final AtomicReference<String> lastAuth = new AtomicReference<>();

    @BeforeEach void start() throws Exception {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/PNID/messages", ex -> {
            lastBody.set(new String(ex.getRequestBody().readAllBytes()));
            lastAuth.set(ex.getRequestHeaders().getFirst("Authorization"));
            byte[] out = (status / 100 == 2 ? "{\"messages\":[{\"id\":\"x\"}]}" : "{\"error\":{\"code\":131026}}").getBytes();
            ex.sendResponseHeaders(status, out.length);
            ex.getResponseBody().write(out); ex.close();
        });
        server.start();
    }
    @AfterEach void stop() { server.stop(0); }

    private WhatsAppFirstSender sender(List<String> smsOut) {
        var client = new WhatsAppClient("http://127.0.0.1:" + server.getAddress().getPort(), "PNID", "tok", "otp_tpl", "auth_tpl", "ru", Duration.ofSeconds(2), new ObjectMapper());
        return new WhatsAppFirstSender(client, (phone, text) -> smsOut.add(phone + "|" + text));
    }

    @Test void whatsAppDeliversSoSmsIsNotUsed() {
        status = 200; var sms = new ArrayList<String>();
        sender(sms).send("+77001234567", "JOLAY: 123456\nline2");
        assertTrue(sms.isEmpty());
        assertEquals("Bearer tok", lastAuth.get());
        assertTrue(lastBody.get().contains("\"to\":\"77001234567\""));
        assertTrue(lastBody.get().contains("otp_tpl"));
        assertFalse(lastBody.get().contains("\\n"), "newlines are not allowed in template variables");
    }

    @Test void otpUsesAuthenticationTemplateWithCodeInBodyAndCopyButton() {
        status = 200; var sms = new ArrayList<String>();
        sender(sms).sendOtp("+77001234567", "482913");
        assertTrue(sms.isEmpty());
        String b = lastBody.get();
        assertTrue(b.contains("auth_tpl"));
        assertFalse(b.contains("otp_tpl"));
        assertTrue(b.contains("\"sub_type\":\"url\""));
        assertEquals(2, b.split("482913", -1).length - 1, "code goes to the body and to the Copy code button");
    }

    @Test void otpFallsBackToSmsWithPlainText() {
        status = 400; var sms = new ArrayList<String>();
        sender(sms).sendOtp("+77001234567", "482913");
        assertEquals(1, sms.size());
        assertTrue(sms.get(0).contains("482913"));
    }

    @Test void numberWithoutWhatsAppFallsBackToSms() {
        status = 400; var sms = new ArrayList<String>();
        sender(sms).send("+77001234567", "JOLAY: 123456");
        assertEquals(List.of("+77001234567|JOLAY: 123456"), sms);
    }

    @Test void unreachableWhatsAppFallsBackToSms() {
        server.stop(0); var sms = new ArrayList<String>();
        sender(sms).send("+77001234567", "JOLAY: 123456");
        assertEquals(1, sms.size());
    }
}
