package kz.jolay.identity;

public interface SmsSender {
    void send(String phone, String text);
}
