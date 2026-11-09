package kz.jolay.identity;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/** Text delivery policy: WhatsApp first; the SMS gateway only for people who are not reachable on WhatsApp. Callers keep using {@link SmsSender}. */
public class WhatsAppFirstSender implements SmsSender {
    private static final Logger log = LoggerFactory.getLogger(WhatsAppFirstSender.class);
    private final WhatsAppClient whatsApp;
    private final SmsSender smsFallback;

    public WhatsAppFirstSender(WhatsAppClient whatsApp, SmsSender smsFallback) { this.whatsApp = whatsApp; this.smsFallback = smsFallback; }

    @Override public void sendOtp(String phone, String code) {
        if (whatsApp.sendOtp(phone, code)) return;
        smsFallback.sendOtp(phone, code);
    }

    @Override public void send(String phone, String text) {
        if (whatsApp.send(phone, text)) return;
        log.debug("Sending via SMS fallback");
        smsFallback.send(phone, text);
    }
}
