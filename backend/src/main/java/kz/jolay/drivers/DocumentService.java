package kz.jolay.drivers;

import kz.jolay.common.ApiException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * Driver document storage. Strict allow-list (type, size, magic bytes), random server-side file names, files are stored
 * outside any web root and are only readable by admins through an authorized endpoint.
 */
@Service
public class DocumentService {
    private static final Set<String> TYPES = Set.of("ID_CARD", "DRIVER_LICENSE", "VEHICLE_REGISTRATION", "INSURANCE", "PHOTO");
    private static final long MAX = 5L * 1024 * 1024;
    private final JdbcClient jdbc;
    private final Path dir;

    public DocumentService(JdbcClient jdbc, @Value("${jolay.storage.documents-dir}") String dir) { this.jdbc = jdbc; this.dir = Path.of(dir).toAbsolutePath(); }

    private static String sniff(byte[] h) {
        if (h.length >= 3 && (h[0] & 0xFF) == 0xFF && (h[1] & 0xFF) == 0xD8 && (h[2] & 0xFF) == 0xFF) return "image/jpeg";
        if (h.length >= 8 && (h[0] & 0xFF) == 0x89 && h[1] == 'P' && h[2] == 'N' && h[3] == 'G') return "image/png";
        if (h.length >= 5 && h[0] == '%' && h[1] == 'P' && h[2] == 'D' && h[3] == 'F' && h[4] == '-') return "application/pdf";
        return null;
    }

    public Map<String, Object> store(UUID driverId, String type, MultipartFile file) {
        if (!TYPES.contains(type)) throw ApiException.badRequest("invalid_document_type", "Unknown document type");
        if (file.isEmpty() || file.getSize() > MAX) throw ApiException.badRequest("invalid_file", "File must be between 1 byte and 5 MB");
        if (jdbc.sql("SELECT count(*) FROM drivers WHERE user_id=:u").param("u", driverId).query(Integer.class).single() == 0)
            throw ApiException.notFound("driver_not_registered", "Driver profile not found");
        try {
            byte[] bytes = file.getBytes();
            String ct = sniff(bytes);
            if (ct == null) throw ApiException.badRequest("invalid_file_type", "Only JPEG, PNG or PDF files are accepted");
            Files.createDirectories(dir);
            String key = UUID.randomUUID() + (ct.equals("application/pdf") ? ".pdf" : ct.equals("image/png") ? ".png" : ".jpg");
            Files.write(dir.resolve(key), bytes);
            UUID id = jdbc.sql("INSERT INTO driver_documents(driver_id,doc_type,storage_key,content_type,size_bytes) VALUES (:d,:t,:k,:c,:s) RETURNING id")
                    .param("d", driverId).param("t", type).param("k", key).param("c", ct).param("s", bytes.length).query(UUID.class).single();
            return Map.of("id", id, "type", type, "status", "PENDING");
        } catch (IOException e) { throw new IllegalStateException("document storage failed", e); }
    }

    public List<Map<String, Object>> list(UUID driverId) {
        return jdbc.sql("SELECT id, doc_type AS type, status, created_at FROM driver_documents WHERE driver_id=:d ORDER BY created_at DESC").param("d", driverId).query().listOfRows();
    }

    public Map<String, Object> adminFile(UUID docId) {
        var d = jdbc.sql("SELECT storage_key, content_type FROM driver_documents WHERE id=:id").param("id", docId).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.notFound("document_not_found", "Document not found"));
        try { return Map.of("bytes", Files.readAllBytes(dir.resolve((String) d.get("storage_key")).normalize()), "contentType", d.get("content_type")); }
        catch (IOException e) { throw ApiException.notFound("document_not_found", "Document not found"); }
    }
}
