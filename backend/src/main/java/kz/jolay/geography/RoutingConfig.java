package kz.jolay.geography;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.micrometer.core.instrument.MeterRegistry;
import kz.jolay.common.AppSettings;
import kz.jolay.common.SimpleBreaker;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Duration;

/**
 * Chooses the routing implementation. With {@code JOLAY_2GIS_KEY} set, routes come from the 2GIS Routing API and the estimate is only the fallback;
 * otherwise the development estimate is used and every route is flagged ESTIMATED.
 */
@Configuration
public class RoutingConfig {
    @Bean
    RouteProvider routeProvider(AppSettings settings, ObjectMapper mapper, MeterRegistry metrics,
                                @Value("${jolay.geocoding.twogis-key:}") String key,
                                @Value("${jolay.routing.twogis-url:https://routing.api.2gis.com}") String url,
                                @Value("${jolay.routing.timeout-ms:2000}") long timeoutMs,
                                @Value("${jolay.routing.failures-to-open:3}") int failuresToOpen,
                                @Value("${jolay.routing.open-seconds:30}") long openSeconds) {
        RouteProvider estimate = new EstimatedRouteProvider(settings);
        if (key == null || key.isBlank()) return estimate;
        return new TwoGisRouteProvider(url.trim(), key.trim(), Duration.ofMillis(timeoutMs), mapper, estimate, metrics, new SimpleBreaker(failuresToOpen, Duration.ofSeconds(openSeconds)));
    }
}
