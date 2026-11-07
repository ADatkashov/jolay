package kz.jolay.geography;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.micrometer.core.instrument.MeterRegistry;
import kz.jolay.common.SimpleBreaker;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Duration;

/** Enables Nominatim geocoding when {@code JOLAY_NOMINATIM_URL} is set; otherwise the seeded places table is the only source. */
@Configuration
public class GeocodingConfig {
    @Bean
    @ConditionalOnExpression("!'${jolay.geocoding.nominatim-url:}'.trim().isEmpty()")
    ExternalGeocoder nominatimGeocoder(ObjectMapper mapper, MeterRegistry metrics,
                                       @Value("${jolay.geocoding.nominatim-url}") String url,
                                       @Value("${jolay.geocoding.country-codes:kz}") String countryCodes,
                                       @Value("${jolay.geocoding.user-agent:JOLAY-backend (ops@jolay.kz)}") String userAgent,
                                       @Value("${jolay.geocoding.timeout-ms:1500}") long timeoutMs,
                                       @Value("${jolay.geocoding.failures-to-open:3}") int failuresToOpen,
                                       @Value("${jolay.geocoding.open-seconds:30}") long openSeconds) {
        return new NominatimGeocoder(url.trim(), countryCodes, userAgent, Duration.ofMillis(timeoutMs), mapper, metrics, new SimpleBreaker(failuresToOpen, Duration.ofSeconds(openSeconds)));
    }
}
