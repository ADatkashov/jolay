package kz.jolay.identity;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.AnnotatedElementUtils;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import java.io.IOException;
import java.util.HashSet;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Fail-early role check. {@code @PreAuthorize} is enforced when the controller method is invoked, which is AFTER Spring has bound and validated the
 * request body: a signed-in user without the role would otherwise get a 400 describing the request fields instead of a 403. This interceptor runs
 * before argument resolution and rejects the call with 403 when the caller holds none of the roles of a plain {@code hasRole('X')} /
 * {@code hasAnyRole('X','Y')} rule. It is defence in depth only: method security still runs afterwards and remains the authority, and any rule that is
 * not that simple shape (custom expressions) is left entirely to method security.
 */
@Configuration
public class RolePreCheckInterceptor implements WebMvcConfigurer, HandlerInterceptor {
    private static final Pattern SIMPLE = Pattern.compile("^\\s*(?:hasRole|hasAnyRole)\\(\\s*'[A-Z_]+'(?:\\s*,\\s*'[A-Z_]+')*\\s*\\)\\s*$");
    private static final Pattern ROLE = Pattern.compile("'([A-Z_]+)'");

    @Override
    public void addInterceptors(InterceptorRegistry registry) { registry.addInterceptor(this).addPathPatterns("/api/**"); }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws IOException {
        if (!(handler instanceof HandlerMethod hm)) return true;
        PreAuthorize rule = AnnotatedElementUtils.findMergedAnnotation(hm.getMethod(), PreAuthorize.class);
        if (rule == null) rule = AnnotatedElementUtils.findMergedAnnotation(hm.getBeanType(), PreAuthorize.class);
        if (rule == null || !SIMPLE.matcher(rule.value()).matches()) return true;

        Authentication a = SecurityContextHolder.getContext().getAuthentication();
        if (a == null || !(a.getPrincipal() instanceof AuthUser u)) return true;          // anonymous callers are handled by the filter chain (401)
        Set<String> allowed = new HashSet<>();
        Matcher m = ROLE.matcher(rule.value());
        while (m.find()) allowed.add(m.group(1));
        for (String role : u.roles()) if (allowed.contains(role)) return true;

        response.setStatus(HttpServletResponse.SC_FORBIDDEN);
        response.setContentType("application/json");
        response.getWriter().write("{\"code\":\"forbidden\",\"message\":\"Access denied\"}");
        return false;
    }
}
