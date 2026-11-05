package kz.jolay.identity;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.Set;

@Component
public class JwtAuthFilter extends OncePerRequestFilter {
    public static final String PARSED_USER = "jolay.parsedUser";
    private final JwtService jwt;
    private final JdbcClient jdbc;
    /** Roles that can move money or change settings: when security.staff_mfa_required is on they must have a second factor before using anything but enrolment. */
    static final Set<String> MFA_ENFORCED_ROLES = Set.of("SUPER_ADMIN", "FINANCE_ADMIN");

    public JwtAuthFilter(JwtService jwt, JdbcClient jdbc) { this.jwt = jwt; this.jdbc = jdbc; }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        String h = req.getHeader("Authorization");
        boolean[] blocked = {false};
        if (h != null && h.startsWith("Bearer ")) {
            Object cached = req.getAttribute(PARSED_USER);
            (cached instanceof AuthUser cu ? java.util.Optional.of(cu) : jwt.parse(h.substring(7))).ifPresent(u -> {
                // Suspended / deleted accounts lose access immediately, even with a valid token.
                boolean active = jdbc.sql("SELECT status='ACTIVE' FROM users WHERE id=:id AND deleted_at IS NULL")
                        .param("id", u.id()).query(Boolean.class).optional().orElse(false);
                if (active && mfaEnrolmentMissing(u, req)) { blocked[0] = true; return; }
                if (active) {
                    var auth = new UsernamePasswordAuthenticationToken(u, null,
                            u.roles().stream().map(r -> new SimpleGrantedAuthority("ROLE_" + r)).toList());
                    SecurityContextHolder.getContext().setAuthentication(auth);
                }
            });
        }
        if (blocked[0]) {
            res.setStatus(403);
            res.setContentType("application/json");
            res.getWriter().write("{\"code\":\"mfa_enrollment_required\",\"message\":\"Set up two-factor authentication before using the console\"}");
            return;
        }
        chain.doFilter(req, res);
    }

    private boolean mfaEnrolmentMissing(AuthUser u, HttpServletRequest req) {
        if (u.roles().stream().noneMatch(MFA_ENFORCED_ROLES::contains)) return false;
        String path = req.getRequestURI();
        if (path.startsWith("/api/v1/account/mfa") || path.startsWith("/api/v1/auth/")) return false;     // enrolment and logout must stay reachable
        boolean required = "true".equals(jdbc.sql("SELECT value FROM application_settings WHERE key='security.staff_mfa_required'").query(String.class).optional().orElse("false"));
        if (!required) return false;
        return !jdbc.sql("SELECT mfa_enabled_at IS NOT NULL FROM users WHERE id=:id").param("id", u.id()).query(Boolean.class).optional().orElse(false);
    }
}
