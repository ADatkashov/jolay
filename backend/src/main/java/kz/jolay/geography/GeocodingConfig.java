package kz.jolay.geography;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.micrometer.core.instrument.MeterRegistry;
import kz.jolay.common.SimpleBreaker;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Duration;

/**
 * 2GIS is the only map/geocoding provider. With {@code JOLAY_2GIS_KEY} set it provides address search, reverse geocoding and map tiles (routing: see
 * {@link RoutingConfig}); without it the seeded places table is the only search source and the tile endpoint answers 503.
 */
@Configuration
public class GeocodingConfig {
    @Bean
    @ConditionalOnExpression("!'${jolay.geocoding.twogis-key:}'.trim().isEmpty()")
    ExternalGeocoder twoGisGeocoder(ObjectMapper mapper, MeterRegistry metrics,
                                    @Value("${jolay.geocoding.twogis-key}") String key,
                                    @Value("${jolay.geocoding.twogis-url:https://catalog.api.2gis.com}") String url,
                                    @Value("${jolay.geocoding.twogis-region-id:}") String regionId,
                                    @Value("${jolay.geocoding.timeout-ms:1500}") long timeoutMs,
                                    @Value("${jolay.geocoding.failures-to-open:3}") int failuresToOpen,
                                    @Value("${jolay.geocoding.open-seconds:30}") long openSeconds) {
        return new TwoGisGeocoder(url.trim(), key.trim(), regionId, Duration.ofMillis(timeoutMs), mapper, metrics, new SimpleBreaker(failuresToOpen, Duration.ofSeconds(openSeconds)));
    }

    @Bean
    @ConditionalOnExpression("!'${jolay.geocoding.twogis-key:}'.trim().isEmpty()")
    TwoGisTileProxy twoGisTileProxy(MeterRegistry metrics,
                                    @Value("${jolay.geocoding.twogis-key}") String key,
                                    @Value("${jolay.maps.tile-host:https://tile{n}.maps.2gis.com}") String host,
                                    @Value("${jolay.maps.tileset:online_hd}") String tileset,
                                    @Value("${jolay.maps.timeout-ms:3000}") long timeoutMs,
                                    @Value("${jolay.maps.cache-tiles:1500}") int cacheTiles,
                                    @Value("${jolay.maps.failures-to-open:5}") int failuresToOpen,
                                    @Value("${jolay.maps.open-seconds:20}") long openSeconds) {
        return new TwoGisTileProxy(host.trim(), tileset.trim(), key.trim(), Duration.ofMillis(timeoutMs), cacheTiles, metrics, new SimpleBreaker(failuresToOpen, Duration.ofSeconds(openSeconds)));
    }
}
