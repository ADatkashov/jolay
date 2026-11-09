package kz.jolay.identity;

public interface SmsSender {
    void send(String phone, String text);

    /** False for development senders that deliver nothing (the prod profile refuses to start with such a channel). */
    default boolean deliversMessages() { return true; }

    /** One-time code. Channels with a dedicated OTP format (WhatsApp authentication template) override this; SMS sends the plain text. */
    default void sendOtp(String phone, String code) {
        send(phone, "JOLAY: " + code + " - your verification code. Do not share it.");
    }
}
