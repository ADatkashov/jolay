package kz.jolay.identity;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.BeanFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;

import java.time.Duration;

/** Enables WhatsApp as the primary channel for OTPs and SOS alerts (jolay.whatsapp.enabled=true). The existing SmsSender stays as the fallback. */
@Configuration
@ConditionalOnProperty(name = "jolay.whatsapp.enabled", havingValue = "true")
public class MessagingConfig {

    @Bean
    WhatsAppClient whatsAppClient(@Value("${jolay.whatsapp.base-url}") String baseUrl, @Value("${jolay.whatsapp.phone-number-id:}") String phoneNumberId,
                                  @Value("${jolay.whatsapp.token:}") String token, @Value("${jolay.whatsapp.template:}") String template, @Value("${jolay.whatsapp.otp-template:}") String otpTemplate,
                                  @Value("${jolay.whatsapp.language:ru}") String language, @Value("${jolay.whatsapp.timeout:PT5S}") Duration timeout,
                                  ObjectMapper mapper) {
        if (phoneNumberId.isBlank() || token.isBlank() || template.isBlank())
            throw new IllegalStateException("jolay.whatsapp.enabled=true requires JOLAY_WHATSAPP_PHONE_NUMBER_ID, JOLAY_WHATSAPP_TOKEN and JOLAY_WHATSAPP_TEMPLATE");
        return new WhatsAppClient(baseUrl, phoneNumberId, token, template, otpTemplate, language, timeout, mapper);
    }

    @Bean @Primary
    SmsSender whatsAppFirstSender(WhatsAppClient client, BeanFactory beans) {
        // The SMS gateway: a production adapter named "productionSmsSender" when present, otherwise the development log sender.
        SmsSender sms = beans.getBean(beans.containsBean("productionSmsSender") ? "productionSmsSender" : "smsGateway", SmsSender.class);
        if (!sms.deliversMessages())
            LoggerFactory.getLogger(MessagingConfig.class).warn("WhatsApp is the only working OTP/SOS channel: no SMS gateway is configured, so people without WhatsApp cannot receive codes");
        return new WhatsAppFirstSender(client, sms);
    }
}
