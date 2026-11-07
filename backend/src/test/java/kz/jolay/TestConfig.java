package kz.jolay;

import kz.jolay.identity.SmsSender;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@TestConfiguration
public class TestConfig {
    public static final Map<String, String> OTPS = new ConcurrentHashMap<>();
    /** Every SMS sent during a test: {phone, text}. */
    public static final java.util.List<String[]> SENT = new java.util.concurrent.CopyOnWriteArrayList<>();

    @Bean @Primary
    SmsSender capturingSms() {
        return (phone, text) -> {
            SENT.add(new String[]{phone, text});
            Matcher m = Pattern.compile("(\\d{6})").matcher(text);
            if (m.find()) OTPS.put(phone, m.group(1));
        };
    }
}
