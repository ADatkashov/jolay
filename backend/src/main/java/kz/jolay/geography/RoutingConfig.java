package kz.jolay.geography;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.micrometer.core.instrument.MeterRegistry;
import kz.jolay.common.AppSettings;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Duration;

/**
 * Chooses the routing implementation. With {@code JOLAY_OSRM_URL} set, routes come from that OSRM server and the estimate is only the fallback;
 * otherwise the development estimate is used and every route is flagged ESTIMATED.
 */
@Configuration
public class RoutingConfig {
    @Bean
    RouteProvider routeProvider(AppSettings settings, ObjectMapper mapper, MeterRegistry metrics,
                                @Value("${jolay.routing.osrm-url:}") String osrmUrl,
                                @Value("${jolay.routing.timeout-ms:2000}") long timeoutMs,
                                @Value("${jolay.routing.failures-to-open:3}") int failuresToOpen,
                                @Value("${jolay.routing.open-seconds:30}") long openSeconds) {
        RouteProvider estimate = new EstimatedRouteProvider(settings);
        if (osrmUrl == null || osrmUrl.isBlank()) return estimate;
        return new OsrmRouteProvider(osrmUrl.trim(), Duration.ofMillis(timeoutMs), mapper, estimate, metrics, failuresToOpen, Duration.ofSeconds(openSeconds));
    }
}
