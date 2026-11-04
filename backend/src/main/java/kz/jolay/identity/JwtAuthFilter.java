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

@Component
public class JwtAuthFilter extends OncePerRequestFilter {
    private final JwtService jwt;
    private final JdbcClient jdbc;

    public JwtAuthFilter(JwtService jwt, JdbcClient jdbc) { this.jwt = jwt; this.jdbc = jdbc; }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        String h = req.getHeader("Authorization");
        if (h != null && h.startsWith("Bearer ")) {
            jwt.parse(h.substring(7)).ifPresent(u -> {
                // Suspended / deleted accounts lose access immediately, even with a valid token.
                boolean active = jdbc.sql("SELECT status='ACTIVE' FROM users WHERE id=:id AND deleted_at IS NULL")
                        .param("id", u.id()).query(Boolean.class).optional().orElse(false);
                if (active) {
                    var auth = new UsernamePasswordAuthenticationToken(u, null,
                            u.roles().stream().map(r -> new SimpleGrantedAuthority("ROLE_" + r)).toList());
                    SecurityContextHolder.getContext().setAuthentication(auth);
                }
            });
        }
        chain.doFilter(req, res);
    }
}
