package kz.jolay.identity;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.time.Duration;
import java.util.List;

@ConfigurationProperties(prefix = "jolay.security")
public record SecurityProps(String jwtSecret, Duration accessTtl, Duration refreshTtl, List<String> corsOrigins,
                            int otpLength, Duration otpTtl, int otpMaxAttempts, int otpMaxPerHour,
                            int loginMaxFailures, Duration loginLockout) {}
