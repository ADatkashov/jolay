package kz.jolay.identity;

import java.util.Set;
import java.util.UUID;

public record AuthUser(UUID id, Set<String> roles) {
    public boolean has(String role) { return roles.contains(role); }
}
