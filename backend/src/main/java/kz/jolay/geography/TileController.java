package kz.jolay.geography;

import org.springframework.beans.factory.ObjectProvider;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;

/**
 * Map tiles for all JOLAY apps (customer, driver, admin, partner): {@code GET /api/v1/geo/tiles/{z}/{x}/{y}.png}. Public (a map widget cannot send a bearer token
 * on every tile), so it only ever serves valid tile coordinates and is cacheable by clients and CDNs.
 */
@RestController
@RequestMapping("/api/v1/geo/tiles")
public class TileController {
    private final TwoGisTileProxy proxy;     // null when JOLAY_2GIS_KEY is not configured
    public TileController(ObjectProvider<TwoGisTileProxy> proxy) { this.proxy = proxy.getIfAvailable(); }

    @GetMapping(value = "/{z}/{x}/{y}.png", produces = MediaType.IMAGE_PNG_VALUE)
    public ResponseEntity<byte[]> tile(@PathVariable int z, @PathVariable int x, @PathVariable int y) {
        if (!TwoGisTileProxy.valid(z, x, y)) return ResponseEntity.badRequest().build();
        if (proxy == null) return ResponseEntity.status(503).build();
        return proxy.tile(z, x, y)
                .map(png -> ResponseEntity.ok().cacheControl(CacheControl.maxAge(Duration.ofDays(1)).cachePublic()).contentType(MediaType.IMAGE_PNG).body(png))
                .orElseGet(() -> ResponseEntity.notFound().build());
    }
}
