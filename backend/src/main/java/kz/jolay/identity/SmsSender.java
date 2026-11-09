package kz.jolay.identity;

public interface SmsSender {
    void send(String phone, String text);

    /** One-time code. Channels with a dedicated OTP format (WhatsApp authentication template) override this; SMS sends the plain text. */
    default void sendOtp(String phone, String code) {
        send(phone, "JOLAY: " + code + " - your verification code. Do not share it.");
    }
}
