package kz.jolay.realtime;

import kz.jolay.identity.AuthUser;
import kz.jolay.identity.JwtService;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.server.ServerHttpRequest;
import org.springframework.http.server.ServerHttpResponse;
import org.springframework.http.server.ServletServerHttpRequest;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketHandler;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;
import org.springframework.web.socket.handler.TextWebSocketHandler;
import org.springframework.web.socket.server.HandshakeInterceptor;

import java.util.Map;
import java.util.UUID;

/**
 * Endpoint: wss://host/ws?token=<access JWT>. The handshake is rejected for missing/invalid tokens.
 * Each user only receives events addressed to their own user id.
 */
@Configuration
@EnableWebSocket
public class WebSocketConfig implements WebSocketConfigurer {
    private final JwtService jwt;
    private final RealtimeService realtime;
    public WebSocketConfig(JwtService jwt, RealtimeService realtime) { this.jwt = jwt; this.realtime = realtime; }

    @Override
    public void registerWebSocketHandlers(WebSocketHandlerRegistry r) {
        r.addHandler(new Handler(), "/ws")
                .addInterceptors(new HandshakeInterceptor() {
                    @Override public boolean beforeHandshake(ServerHttpRequest req, ServerHttpResponse res, WebSocketHandler h, Map<String, Object> attrs) {
                        String token = ((ServletServerHttpRequest) req).getServletRequest().getParameter("token");
                        if (token == null) return false;
                        AuthUser u = jwt.parse(token).orElse(null);
                        if (u == null) return false;
                        attrs.put("userId", u.id());
                        return true;
                    }
                    @Override public void afterHandshake(ServerHttpRequest q, ServerHttpResponse s, WebSocketHandler h, Exception e) {}
                })
                .setAllowedOriginPatterns("*");   // bearer token (not ambient cookies) authenticates; origin is not a credential
    }

    private class Handler extends TextWebSocketHandler {
        @Override public void afterConnectionEstablished(WebSocketSession s) { realtime.register((UUID) s.getAttributes().get("userId"), s); }
        @Override public void afterConnectionClosed(WebSocketSession s, CloseStatus st) { realtime.unregister((UUID) s.getAttributes().get("userId"), s); }
        @Override protected void handleTextMessage(WebSocketSession s, TextMessage m) throws Exception {
            if ("ping".equals(m.getPayload())) s.sendMessage(new TextMessage("pong"));
        }
    }
}
