package kz.jolay;

import org.junit.jupiter.api.Test;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.*;
import org.springframework.util.LinkedMultiValueMap;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class DocumentUploadIT extends IntegrationTestBase {
    private static final byte[] PNG = {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0};

    private ResponseEntity<String> upload(Session d, String type, String filename, byte[] bytes) {
        var body = new LinkedMultiValueMap<String, Object>();
        body.add("type", type);
        body.add("file", new ByteArrayResource(bytes) { @Override public String getFilename() { return filename; } });
        HttpHeaders h = new HttpHeaders();
        h.setContentType(MediaType.MULTIPART_FORM_DATA);
        h.setBearerAuth(d.token());
        return rest.exchange("http://localhost:" + port + "/api/v1/drivers/documents", HttpMethod.POST, new HttpEntity<>(body, h), String.class);
    }

    @Test
    void uploadValidationAndAdminOnlyAuditedDownload() throws Exception {
        Session d = register("DRIVER");
        post("/api/v1/drivers/register", d.token(), Map.of("vehicle", Map.of("brand", "Kia", "model", "Rio", "year", 2019, "color", "Black", "plate", "777ABC02", "category", "ECONOMY")));

        assertEquals(201, upload(d, "ID_CARD", "id.png", PNG).getStatusCode().value());
        // a text file renamed to .png is rejected by content sniffing, not by its name or declared type
        assertEquals(400, upload(d, "ID_CARD", "evil.png", "<script>alert(1)</script>".getBytes()).getStatusCode().value());
        assertEquals(400, upload(d, "NOT_A_TYPE", "id.png", PNG).getStatusCode().value());
        assertEquals(400, upload(d, "ID_CARD", "empty.png", new byte[0]).getStatusCode().value());
        // Oversized file: the server may answer 413 or drop the connection while the client is still streaming (timing dependent);
        // both mean "rejected". What must hold is that nothing was stored.
        try { assertEquals(413, upload(d, "INSURANCE", "big.png", new byte[5 * 1024 * 1024 + 512 * 1024]).getStatusCode().value()); }
        catch (org.springframework.web.client.ResourceAccessException connectionDropped) { /* rejected mid-stream */ }
        assertEquals(1, jdbc.sql("SELECT count(*) FROM driver_documents").query(Integer.class).single(), "oversized upload must not be stored");

        String docId = get("/api/v1/drivers/documents", d.token()).body().get(0).path("id").asText();
        // the driver cannot read the stored file back through any endpoint, other roles are refused
        assertEquals(403, get("/api/v1/admin/drivers/documents/" + docId + "/file", d.token()).status());
        assertEquals(403, get("/api/v1/admin/drivers/documents/" + docId + "/file", admin("SUPPORT_AGENT").token()).status());
        assertEquals(403, get("/api/v1/admin/drivers/documents/" + docId + "/file", admin("FINANCE_ADMIN").token()).status());

        Session ops = admin("OPERATIONS_ADMIN");
        HttpHeaders h = new HttpHeaders(); h.setBearerAuth(ops.token());
        ResponseEntity<byte[]> file = rest.exchange("http://localhost:" + port + "/api/v1/admin/drivers/documents/" + docId + "/file", HttpMethod.GET, new HttpEntity<>(h), byte[].class);
        assertEquals(200, file.getStatusCode().value());
        assertArrayEquals(PNG, file.getBody());
        assertEquals("image/png", file.getHeaders().getContentType().toString());
        assertEquals("nosniff", file.getHeaders().getFirst("X-Content-Type-Options"));
        assertTrue(file.getHeaders().getFirst("Content-Disposition").startsWith("attachment"));
        assertEquals(1, jdbc.sql("SELECT count(*) FROM audit_logs WHERE action='DOCUMENT_VIEWED'").query(Integer.class).single());
        // stored under a server-generated name, never the client's
        assertFalse(jdbc.sql("SELECT storage_key FROM driver_documents").query(String.class).single().contains("id.png"));
    }
}
