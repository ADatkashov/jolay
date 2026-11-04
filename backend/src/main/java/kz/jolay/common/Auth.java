package kz.jolay.common;

import kz.jolay.identity.AuthUser;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.UUID;

public final class Auth {
    private Auth() {}
    public static AuthUser user() {
        Authentication a = SecurityContextHolder.getContext().getAuthentication();
        if (a == null || !(a.getPrincipal() instanceof AuthUser u)) throw ApiException.unauthorized("unauthorized", "Authentication required");
        return u;
    }
    public static UUID id() { return user().id(); }
}
