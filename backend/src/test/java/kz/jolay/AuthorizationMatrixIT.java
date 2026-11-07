package kz.jolay;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.annotation.AnnotatedElementUtils;
import org.springframework.http.HttpMethod;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.mvc.method.RequestMappingInfo;
import org.springframework.web.servlet.mvc.method.annotation.RequestMappingHandlerMapping;

import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Security regression guard: walks EVERY mapped endpoint that declares a role rule (@PreAuthorize on the method or its class) and proves, over real HTTP,
 * that (a) an anonymous caller gets 401 and (b) a caller holding any role the rule does not list gets 403 - before the controller code runs.
 * A new endpoint that forgets its rule is not caught here (it has none to check); {@link #everyEndpointWithoutARoleRuleIsOnTheReviewedList()} fails for that.
 */
class AuthorizationMatrixIT extends IntegrationTestBase {
    @Autowired @org.springframework.beans.factory.annotation.Qualifier("requestMappingHandlerMapping") RequestMappingHandlerMapping mapping;

    private static final Pattern ROLE = Pattern.compile("'([A-Z_]+)'");
    private static final List<String> ALL_ROLES = List.of("CUSTOMER", "DRIVER", "SUPER_ADMIN", "OPERATIONS_ADMIN", "FINANCE_ADMIN", "SUPPORT_AGENT", "PARTNER_ADMIN");

    record Endpoint(String method, String path, Set<String> allowed, String where) {}

    private Set<String> rolesOf(HandlerMethod hm) {
        PreAuthorize pa = AnnotatedElementUtils.findMergedAnnotation(hm.getMethod(), PreAuthorize.class);
        if (pa == null) pa = AnnotatedElementUtils.findMergedAnnotation(hm.getBeanType(), PreAuthorize.class);
        if (pa == null) return null;
        Matcher m = ROLE.matcher(pa.value());
        Set<String> roles = new TreeSet<>();
        while (m.find()) roles.add(m.group(1));
        return roles;
    }

    private List<Endpoint> endpoints(boolean withRules) {
        List<Endpoint> out = new ArrayList<>();
        for (Map.Entry<RequestMappingInfo, HandlerMethod> e : mapping.getHandlerMethods().entrySet()) {
            HandlerMethod hm = e.getValue();
            if (!hm.getBeanType().getName().startsWith("kz.jolay")) continue;
            Set<String> roles = rolesOf(hm);
            if ((roles != null && !roles.isEmpty()) != withRules) continue;
            var patterns = e.getKey().getPathPatternsCondition().getPatternValues();
            var methods = e.getKey().getMethodsCondition().getMethods();
            for (String p : patterns) for (var m : methods)
                out.add(new Endpoint(m.name(), p, roles == null ? Set.of() : roles, hm.getBeanType().getSimpleName() + "#" + hm.getMethod().getName()));
        }
        out.sort(Comparator.comparing(Endpoint::path).thenComparing(Endpoint::method));
        return out;
    }

    private Resp hit(Endpoint ep, String token) {
        String path = ep.path().replaceAll("\\{[^}]+}", "00000000-0000-0000-0000-000000000000");
        Object body = ep.method().equals("POST") || ep.method().equals("PUT") || ep.method().equals("PATCH") ? "{}" : null;
        return call(HttpMethod.valueOf(ep.method()), path, token, body, null);
    }

    @Test
    void roleRulesHoldForEveryRoleThatIsNotListedAndForAnonymousCallers() {
        Map<String, String> tokens = new LinkedHashMap<>();
        tokens.put("CUSTOMER", customer().token());
        tokens.put("DRIVER", register("DRIVER").token());
        for (String staff : List.of("SUPER_ADMIN", "OPERATIONS_ADMIN", "FINANCE_ADMIN", "SUPPORT_AGENT", "PARTNER_ADMIN")) tokens.put(staff, admin(staff).token());

        List<Endpoint> guarded = endpoints(true);
        assertTrue(guarded.size() > 80, "expected to find the guarded endpoints, found " + guarded.size());
        List<String> failures = new ArrayList<>();
        int checks = 0;
        for (Endpoint ep : guarded) {
            Resp anon = hit(ep, null);
            checks++;
            if (anon.status() != 401) failures.add("anonymous " + ep.method() + " " + ep.path() + " -> " + anon.status() + " (" + ep.where() + ")");
            for (String role : ALL_ROLES) {
                if (ep.allowed().contains(role)) continue;
                Resp r = hit(ep, tokens.get(role));
                checks++;
                if (r.status() != 403) failures.add(role + " " + ep.method() + " " + ep.path() + " -> " + r.status() + " (" + ep.where() + ", allowed " + ep.allowed() + ")");
            }
        }
        assertTrue(checks > 400, "the matrix should exercise hundreds of combinations, did " + checks);
        assertTrue(failures.isEmpty(), failures.size() + " authorization failures:\n" + String.join("\n", failures));
    }

    /** Endpoints without a role rule are either public on purpose or open to ANY signed-in user and scoped by the caller's id in the query. Adding one means reviewing it and adding it here. */
    @Test
    void everyEndpointWithoutARoleRuleIsOnTheReviewedList() {
        Set<String> reviewed = new TreeSet<>(List.of(
                // public by design (authentication endpoints, public catalog, trip/tracking pages, gateway callbacks authenticated by signature)
                "AuthController", "CatalogController", "LegalController", "RideShareController#view", "RideShareController#page", "DeliveryController#track", "PaymentController#webhook",
                // signed-in users of any role, every query scoped to Auth.id()
                "CustomerController#me", "CustomerController#update", "CustomerController#delete", "GeoController", "MfaController", "NotificationController", "SupportController"));
        List<String> unreviewed = new ArrayList<>();
        for (Endpoint ep : endpoints(false)) {
            String cls = ep.where().substring(0, ep.where().indexOf('#'));
            if (reviewed.contains(cls) || reviewed.contains(ep.where())) continue;
            unreviewed.add(ep.method() + " " + ep.path() + " (" + ep.where() + ")");
        }
        assertTrue(unreviewed.isEmpty(), "endpoints without a role rule that nobody has reviewed:\n" + String.join("\n", unreviewed));
    }
}
