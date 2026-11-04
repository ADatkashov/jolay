package kz.jolay.catalog;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/** Public, admin-configurable service catalog (categories, cities). */
@RestController
@RequestMapping("/api/v1/catalog")
public class CatalogController {
    private final JdbcClient jdbc;
    public CatalogController(JdbcClient jdbc) { this.jdbc = jdbc; }

    @GetMapping("/categories")
    public List<Map<String, Object>> categories(@RequestParam(defaultValue = "en") String lang) {
        String l = switch (lang) { case "kk" -> "kk"; case "ru" -> "ru"; default -> "en"; };
        return jdbc.sql("SELECT code, name_" + l + " AS name, desc_" + l + " AS description, capacity, rank FROM vehicle_categories WHERE active ORDER BY rank").query().listOfRows();
    }

    @GetMapping("/cities")
    public List<Map<String, Object>> cities(@RequestParam(defaultValue = "en") String lang) {
        String l = switch (lang) { case "kk" -> "kk"; case "ru" -> "ru"; default -> "en"; };
        return jdbc.sql("SELECT id, code, name_" + l + " AS name, timezone, currency FROM cities WHERE active ORDER BY code").query().listOfRows();
    }
}
