package kz.jolay.identity;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.stereotype.Service;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Date;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

@Service
public class JwtService {
    private final SecretKey key;
    private final SecurityProps props;

    public JwtService(SecurityProps props) {
        this.props = props;
        byte[] bytes = props.jwtSecret().getBytes(StandardCharsets.UTF_8);
        if (bytes.length < 32) throw new IllegalStateException("jolay.security.jwt-secret must be at least 32 bytes");
        this.key = Keys.hmacShaKeyFor(bytes);
    }

    public String issueAccess(UUID userId, Set<String> roles) {
        Instant now = Instant.now();
        return Jwts.builder().subject(userId.toString()).claim("roles", List.copyOf(roles))
                .issuedAt(Date.from(now)).expiration(Date.from(now.plus(props.accessTtl()))).signWith(key).compact();
    }

    public long accessTtlSeconds() { return props.accessTtl().toSeconds(); }

    @SuppressWarnings("unchecked")
    public Optional<AuthUser> parse(String token) {
        try {
            Claims c = Jwts.parser().verifyWith(key).build().parseSignedClaims(token).getPayload();
            return Optional.of(new AuthUser(UUID.fromString(c.getSubject()), Set.copyOf((List<String>) c.get("roles", List.class))));
        } catch (JwtException | IllegalArgumentException e) {
            return Optional.empty();
        }
    }
}
