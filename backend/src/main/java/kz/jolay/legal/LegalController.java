package kz.jolay.legal;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import kz.jolay.common.ApiException;
import kz.jolay.common.Audit;
import kz.jolay.common.Auth;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/**
 * Legal texts (Terms, Privacy, About) are published by SUPER_ADMIN, versioned, never edited in place and NEVER pre-filled by the developers:
 * their content must come from qualified Kazakhstan counsel. Until a document is published for a language the apps show "not published yet".
 */
@RestController
public class LegalController {
    private final JdbcClient jdbc;
    private final Audit audit;
    public LegalController(JdbcClient jdbc, Audit audit) { this.jdbc = jdbc; this.audit = audit; }

    public record Publish(@NotBlank @Size(max = 200000) String body) {}

    @GetMapping("/api/v1/catalog/legal/{type}")
    public Map<String, Object> get(@PathVariable String type, @RequestParam(defaultValue = "en") String lang) {
        String t = type.toUpperCase(), l = lang.length() >= 2 ? lang.substring(0, 2) : "en";
        return jdbc.sql("SELECT doc_type AS type, locale, version, body, published_at FROM legal_documents WHERE doc_type=:t AND locale=:l ORDER BY version DESC LIMIT 1")
                .param("t", t).param("l", l).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.notFound("legal_not_published", "This document has not been published yet"));
    }

    @PutMapping("/api/v1/admin/legal/{type}/{locale}") @PreAuthorize("hasRole('SUPER_ADMIN')") @Transactional @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> publish(@PathVariable String type, @PathVariable String locale, @Valid @RequestBody Publish p) {
        String t = type.toUpperCase();
        if (!List.of("TERMS", "PRIVACY", "ABOUT").contains(t) || !List.of("kk", "ru", "en").contains(locale)) throw ApiException.badRequest("invalid_document", "Unknown document type or language");
        int version = jdbc.sql("SELECT COALESCE(max(version),0)+1 FROM legal_documents WHERE doc_type=:t AND locale=:l").param("t", t).param("l", locale).query(Integer.class).single();
        jdbc.sql("INSERT INTO legal_documents(doc_type,locale,version,body,published_by) VALUES (:t,:l,:v,:b,:u)").param("t", t).param("l", locale).param("v", version).param("b", p.body()).param("u", Auth.id()).update();
        audit.log(Auth.id(), "SUPER_ADMIN", "LEGAL_PUBLISHED", "legal_document", t + "/" + locale, Map.of("version", version));
        return Map.of("type", t, "locale", locale, "version", version);
    }

    @GetMapping("/api/v1/admin/legal") @PreAuthorize("hasRole('SUPER_ADMIN')")
    public List<Map<String, Object>> overview() {
        return jdbc.sql("SELECT doc_type AS type, locale, max(version) AS version, max(published_at) AS published_at FROM legal_documents GROUP BY 1,2 ORDER BY 1,2").query().listOfRows();
    }
}
