package kz.jolay.push;

import java.util.Map;

/** Delivery of a single push message to a single device token. Implementations: {@link DevPushSender} (mock) and {@link FcmPushSender}. */
public interface PushSender {
    /** Returns false when the token is permanently invalid and should be forgotten. */
    boolean send(java.util.UUID userId, String token, String type, String title, String body, Map<String, String> data);
}
