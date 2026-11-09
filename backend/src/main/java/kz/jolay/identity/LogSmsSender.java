package kz.jolay.identity;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.stereotype.Component;

/**
 * Development SMS gateway: nothing is delivered. The message body (which contains the OTP) is written to the log
 * ONLY when jolay.sms.log-code=true. In production configure a real gateway by providing another SmsSender bean.
 */
@Component("smsGateway")
@ConditionalOnMissingBean(name = "productionSmsSender")
public class LogSmsSender implements SmsSender {
    private static final Logger log = LoggerFactory.getLogger(LogSmsSender.class);
    private final boolean logCode;
    public LogSmsSender(@Value("${jolay.sms.log-code:false}") boolean logCode) { this.logCode = logCode; }

    @Override public void send(String phone, String text) {
        String masked = phone.length() > 6 ? phone.substring(0, 4) + "****" + phone.substring(phone.length() - 2) : "****";
        if (logCode) log.warn("[DEV SMS] to={} text={}", masked, text);
        else log.info("SMS queued to={} (log-code disabled, no gateway configured)", masked);
    }
}
