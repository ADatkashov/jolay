package kz.jolay.common;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import kz.jolay.identity.JwtService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Fixed-window API rate limiting (per instance; use the ingress/gateway for a global limit).
 *  - /api/v1/auth/** and payment webhooks: per client IP (brute force / OTP abuse)
 *  - everything else: per authenticated user (JWT subject), or per IP when unauthenticated
 * Behind a reverse proxy set server.forward-headers-strategy=framework so the IP is the real client.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 10)
public class RateLimitFilter extends OncePerRequestFilter {
    private record Window(long start, AtomicInteger count) {}
    private final Map<String, Window> windows = new ConcurrentHashMap<>();
    private final JwtService jwt;
    private final boolean enabled;
    private final int authPerMinute, apiPerMinute;

    public RateLimitFilter(JwtService jwt, @Value("${jolay.ratelimit.enabled:true}") boolean enabled,
                           @Value("${jolay.ratelimit.auth-per-minute:30}") int authPerMinute,
                           @Value("${jolay.ratelimit.api-per-minute:600}") int apiPerMinute) {
        this.jwt = jwt; this.enabled = enabled; this.authPerMinute = authPerMinute; this.apiPerMinute = apiPerMinute;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest r) {
        String p = r.getRequestURI();
        return !enabled || p.startsWith("/actuator") || p.equals("/ws");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain) throws ServletException, IOException {
        String path = req.getRequestURI();
        String key; int limit;
        if (path.startsWith("/api/v1/auth/") || path.startsWith("/api/v1/payments/webhooks/")) { key = "auth|" + req.getRemoteAddr(); limit = authPerMinute; }
        else {
            String h = req.getHeader("Authorization");
            var user = h != null && h.startsWith("Bearer ") ? jwt.parse(h.substring(7)) : java.util.Optional.<kz.jolay.identity.AuthUser>empty();
            user.ifPresent(u -> req.setAttribute(kz.jolay.identity.JwtAuthFilter.PARSED_USER, u));   // reused by JwtAuthFilter: one signature check per request
            key = user.map(u -> "u|" + u.id()).orElse("ip|" + req.getRemoteAddr());
            limit = user.isPresent() ? apiPerMinute : Math.max(60, apiPerMinute / 5);
        }
        long now = System.currentTimeMillis() / 60000;
        Window w = windows.compute(key, (k, old) -> old == null || old.start() != now ? new Window(now, new AtomicInteger(0)) : old);
        if (windows.size() > 100_000) windows.entrySet().removeIf(e -> e.getValue().start() != now);
        if (w.count().incrementAndGet() > limit) {
            res.setStatus(429);
            res.setHeader("Retry-After", String.valueOf(60 - (System.currentTimeMillis() / 1000) % 60));
            res.setContentType("application/json");
            res.getWriter().write("{\"code\":\"rate_limited\",\"message\":\"Too many requests\"}");
            return;
        }
        chain.doFilter(req, res);
    }
}
