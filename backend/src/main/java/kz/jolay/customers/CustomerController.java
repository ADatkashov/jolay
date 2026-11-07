package kz.jolay.customers;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import kz.jolay.common.ApiException;
import kz.jolay.common.Auth;
import kz.jolay.common.GeoPoint;
import kz.jolay.identity.AuthDtos.UserView;
import kz.jolay.identity.AuthService;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1")
public class CustomerController {
    private final JdbcClient jdbc;
    private final AuthService auth;
    public CustomerController(JdbcClient jdbc, AuthService auth) { this.jdbc = jdbc; this.auth = auth; }

    public record ProfileUpdate(@Size(min = 2, max = 120) String fullName, @Email @Size(max = 254) String email, @Pattern(regexp = "kk|ru|en") String locale) {}
    public record AddressRequest(@NotBlank @Size(max = 40) String label, @NotBlank @Size(max = 300) String address, @NotNull @Valid GeoPoint point) {}

    @GetMapping("/customers/me")
    public UserView me() { return auth.userView(Auth.id()); }

    /** Works for any authenticated role (drivers edit their profile here too). */
    @PutMapping("/customers/me")
    public UserView update(@Valid @RequestBody ProfileUpdate r) {
        UUID id = Auth.id();
        String email = r.email() == null || r.email().isBlank() ? null : r.email().trim().toLowerCase();
        if (email != null && jdbc.sql("SELECT count(*) FROM users WHERE lower(email)=:e AND id<>:id AND deleted_at IS NULL").param("e", email).param("id", id).query(Integer.class).single() > 0)
            throw ApiException.conflict("email_taken", "An account with this email already exists");
        jdbc.sql("UPDATE users SET full_name=COALESCE(:n, full_name), email=COALESCE(:e, email), locale=COALESCE(:l, locale), updated_at=now() WHERE id=:id")
                .param("n", r.fullName()).param("e", email).param("l", r.locale()).param("id", id).update();
        return auth.userView(id);
    }

    /** Account deletion: anonymises personal data, revokes sessions; financial records are retained as required by law. */
    @DeleteMapping("/customers/me") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete() {
        UUID id = Auth.id();
        if (jdbc.sql("SELECT count(*) FROM rides WHERE (customer_id=:u OR driver_id=:u) AND status IN ('SEARCHING_DRIVER','DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS')").param("u", id).query(Integer.class).single() > 0)
            throw ApiException.conflict("active_ride_exists", "Finish your active ride before deleting the account");
        jdbc.sql("UPDATE users SET status='DELETED', deleted_at=now(), full_name='Deleted user', email=NULL, avatar_url=NULL, phone='del:'||substr(replace(id::text,'-',''),1,15), updated_at=now() WHERE id=:id").param("id", id).update();
        jdbc.sql("UPDATE refresh_tokens SET revoked_at=now() WHERE user_id=:id AND revoked_at IS NULL").param("id", id).update();
        jdbc.sql("UPDATE customer_addresses SET deleted_at=now() WHERE user_id=:id").param("id", id).update();
        jdbc.sql("DELETE FROM user_devices WHERE user_id=:id").param("id", id).update();
        jdbc.sql("UPDATE drivers SET availability='OFFLINE', verification='SUSPENDED' WHERE user_id=:id").param("id", id).update();
    }

    @GetMapping("/customers/me/addresses") @PreAuthorize("hasRole('CUSTOMER')")
    public List<Map<String, Object>> addresses() {
        return jdbc.sql("SELECT id,label,address,ST_Y(location::geometry) lat,ST_X(location::geometry) lng FROM customer_addresses WHERE user_id=:u AND deleted_at IS NULL ORDER BY created_at")
                .param("u", Auth.id()).query().listOfRows();
    }

    @PostMapping("/customers/me/addresses") @ResponseStatus(HttpStatus.CREATED) @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> addAddress(@Valid @RequestBody AddressRequest r) {
        if (jdbc.sql("SELECT count(*) FROM customer_addresses WHERE user_id=:u AND deleted_at IS NULL").param("u", Auth.id()).query(Integer.class).single() >= 30)
            throw ApiException.badRequest("too_many_addresses", "Address limit reached");
        UUID id = jdbc.sql("INSERT INTO customer_addresses(user_id,label,address,location) VALUES (:u,:l,:a,ST_SetSRID(ST_MakePoint(:lng,:lat),4326)::geography) RETURNING id")
                .param("u", Auth.id()).param("l", r.label()).param("a", r.address()).param("lng", r.point().lng()).param("lat", r.point().lat()).query(UUID.class).single();
        return Map.of("id", id, "label", r.label(), "address", r.address(), "lat", r.point().lat(), "lng", r.point().lng());
    }

    public record ContactRequest(@NotBlank @Size(min = 2, max = 80) String name, @NotBlank String phone) {}

    @GetMapping("/customers/me/emergency-contacts") @PreAuthorize("hasRole('CUSTOMER')")
    public List<Map<String, Object>> contacts() {
        return jdbc.sql("SELECT id, name, phone FROM emergency_contacts WHERE user_id=:u ORDER BY created_at").param("u", Auth.id()).query().listOfRows();
    }

    @PostMapping("/customers/me/emergency-contacts") @ResponseStatus(HttpStatus.CREATED) @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> addContact(@Valid @RequestBody ContactRequest r) {
        String phone = r.phone().replaceAll("[\\s()\\-]", "");
        if (!phone.matches("\\+[1-9]\\d{9,14}")) throw ApiException.badRequest("invalid_phone", "Enter the phone number in international format");
        if (jdbc.sql("SELECT count(*) FROM emergency_contacts WHERE user_id=:u").param("u", Auth.id()).query(Integer.class).single() >= 3)
            throw ApiException.badRequest("too_many_contacts", "You can add up to 3 emergency contacts");
        if (jdbc.sql("SELECT count(*) FROM emergency_contacts WHERE user_id=:u AND phone=:p").param("u", Auth.id()).param("p", phone).query(Integer.class).single() > 0)
            throw ApiException.conflict("contact_exists", "This contact is already added");
        UUID id = jdbc.sql("INSERT INTO emergency_contacts(user_id,name,phone) VALUES (:u,:n,:p) RETURNING id").param("u", Auth.id()).param("n", r.name().trim()).param("p", phone).query(UUID.class).single();
        return Map.of("id", id, "name", r.name().trim(), "phone", phone);
    }

    @DeleteMapping("/customers/me/emergency-contacts/{id}") @ResponseStatus(HttpStatus.NO_CONTENT) @PreAuthorize("hasRole('CUSTOMER')")
    public void deleteContact(@PathVariable UUID id) {
        jdbc.sql("DELETE FROM emergency_contacts WHERE id=:i AND user_id=:u").param("i", id).param("u", Auth.id()).update();
    }

    @DeleteMapping("/customers/me/addresses/{id}") @ResponseStatus(HttpStatus.NO_CONTENT) @PreAuthorize("hasRole('CUSTOMER')")
    public void deleteAddress(@PathVariable UUID id) {
        jdbc.sql("UPDATE customer_addresses SET deleted_at=now() WHERE id=:i AND user_id=:u").param("i", id).param("u", Auth.id()).update();
    }

    @GetMapping("/customers/me/recent-destinations") @PreAuthorize("hasRole('CUSTOMER')")
    public List<Map<String, Object>> recent() {
        return jdbc.sql("""
                SELECT DISTINCT ON (dropoff_address) dropoff_address AS address, ST_Y(dropoff::geometry) lat, ST_X(dropoff::geometry) lng, created_at
                FROM rides WHERE customer_id=:u AND status='COMPLETED' ORDER BY dropoff_address, created_at DESC""").param("u", Auth.id()).query().listOfRows()
                .stream().sorted((a, b) -> ((java.time.OffsetDateTime) b.get("created_at")).compareTo((java.time.OffsetDateTime) a.get("created_at"))).limit(5).toList();
    }
}
