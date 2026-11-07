package kz.jolay.admin;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import kz.jolay.common.*;
import kz.jolay.drivers.DocumentService;
import kz.jolay.notifications.Notifier;
import kz.jolay.payments.PaymentService;
import kz.jolay.rides.RideDtos.RideView;
import kz.jolay.rides.RideService;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.*;

/** Staff API. Every route is protected by method-level role checks (not only by the UI) and writes an audit record. */
@RestController
@RequestMapping("/api/v1/admin")
public class AdminController {
    private static final String OPS = "hasAnyRole('SUPER_ADMIN','OPERATIONS_ADMIN')";
    private static final String FIN = "hasAnyRole('SUPER_ADMIN','FINANCE_ADMIN')";
    private static final String ANY = "hasAnyRole('SUPER_ADMIN','OPERATIONS_ADMIN','FINANCE_ADMIN','SUPPORT_AGENT')";

    private final JdbcClient jdbc;
    private final Audit audit;
    private final RideService rides;
    private final PaymentService payments;
    private final DocumentService documents;
    private final Notifier notifier;
    private final PasswordEncoder encoder;

    public AdminController(JdbcClient jdbc, Audit audit, RideService rides, PaymentService payments, DocumentService documents, Notifier notifier, PasswordEncoder encoder) {
        this.jdbc = jdbc; this.audit = audit; this.rides = rides; this.payments = payments; this.documents = documents; this.notifier = notifier; this.encoder = encoder;
    }

    private String role() { return Auth.user().roles().stream().filter(r -> !r.equals("CUSTOMER") && !r.equals("DRIVER")).findFirst().orElse("?"); }

    // ---------------- dashboard ----------------
    /**
     * Metric definitions: GBV = sum of final fares of completed rides. Platform revenue = balance of the PLATFORM_REVENUE ledger
     * account (commissions net of refunds) - NOT the GBV. Driver payouts = payouts marked PAID.
     */
    @GetMapping("/dashboard") @PreAuthorize(ANY)
    public Map<String, Object> dashboard() {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("totalCustomers", jdbc.sql("SELECT count(*) FROM users u JOIN user_roles r ON r.user_id=u.id AND r.role='CUSTOMER' WHERE u.deleted_at IS NULL AND u.phone_verified").query(Long.class).single());
        m.put("approvedDrivers", jdbc.sql("SELECT count(*) FROM drivers WHERE verification='APPROVED'").query(Long.class).single());
        m.put("onlineDrivers", jdbc.sql("SELECT count(*) FROM drivers WHERE availability IN ('ONLINE','OFFERED','BUSY')").query(Long.class).single());
        m.put("activeRides", jdbc.sql("SELECT count(*) FROM rides WHERE status IN ('SEARCHING_DRIVER','DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS')").query(Long.class).single());
        m.put("completedRides", jdbc.sql("SELECT count(*) FROM rides WHERE status='COMPLETED'").query(Long.class).single());
        m.put("cancelledRides", jdbc.sql("SELECT count(*) FROM rides WHERE status IN ('CANCELLED','EXPIRED')").query(Long.class).single());
        m.put("grossBookingValue", jdbc.sql("SELECT COALESCE(sum(final_fare),0) FROM rides WHERE status='COMPLETED'").query(BigDecimal.class).single());
        m.put("platformRevenue", jdbc.sql("SELECT balance FROM accounts WHERE type='PLATFORM_REVENUE'").query(BigDecimal.class).single());
        m.put("driverPayouts", jdbc.sql("SELECT COALESCE(sum(amount),0) FROM payouts WHERE status='PAID'").query(BigDecimal.class).single());
        m.put("averageRating", jdbc.sql("SELECT COALESCE(round(avg(stars),2),0) FROM ratings").query(BigDecimal.class).single());
        m.put("ordersPerDay", jdbc.sql("""
                SELECT to_char(d::date,'YYYY-MM-DD') AS day,
                       (SELECT count(*) FROM rides r WHERE (r.created_at AT TIME ZONE 'Asia/Almaty')::date = d::date) AS orders,
                       (SELECT COALESCE(sum(final_fare),0) FROM rides r WHERE r.status='COMPLETED' AND (r.completed_at AT TIME ZONE 'Asia/Almaty')::date = d::date) AS gbv
                FROM generate_series((now() AT TIME ZONE 'Asia/Almaty')::date - 13, (now() AT TIME ZONE 'Asia/Almaty')::date, interval '1 day') d ORDER BY d""").query().listOfRows());
        m.put("ridesByCategory", jdbc.sql("SELECT category_code AS category, count(*) AS rides FROM rides GROUP BY 1 ORDER BY 1").query().listOfRows());
        m.put("cancellationRate", jdbc.sql("SELECT CASE WHEN count(*)=0 THEN 0 ELSE round(100.0*count(*) FILTER (WHERE status IN ('CANCELLED','EXPIRED'))/count(*),1) END FROM rides WHERE status IN ('COMPLETED','CANCELLED','EXPIRED')").query(BigDecimal.class).single());
        m.put("avgMatchSeconds", jdbc.sql("SELECT COALESCE(round(avg(EXTRACT(EPOCH FROM (assigned_at - created_at)))::numeric,1),0) FROM rides WHERE assigned_at IS NOT NULL").query(BigDecimal.class).single());
        return m;
    }

    @GetMapping("/live") @PreAuthorize(ANY)
    public Map<String, Object> live() {
        return Map.of(
                "drivers", jdbc.sql("SELECT d.user_id AS id, u.full_name AS name, d.availability, ST_Y(l.location::geometry) lat, ST_X(l.location::geometry) lng FROM drivers d JOIN users u ON u.id=d.user_id JOIN driver_locations l ON l.driver_id=d.user_id WHERE d.availability IN ('ONLINE','OFFERED','BUSY')").query().listOfRows(),
                "rides", jdbc.sql("SELECT id, status, pickup_address, dropoff_address, ST_Y(pickup::geometry) plat, ST_X(pickup::geometry) plng, ST_Y(dropoff::geometry) dlat, ST_X(dropoff::geometry) dlng FROM rides WHERE status IN ('SEARCHING_DRIVER','DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS')").query().listOfRows());
    }

    // ---------------- rides ----------------
    @GetMapping("/rides") @PreAuthorize(ANY)
    public List<Map<String, Object>> rides(@RequestParam(required = false) String status, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "25") int size) {
        var q = jdbc.sql("SELECT r.id, r.status, r.category_code, r.pickup_address, r.dropoff_address, r.est_fare, r.final_fare, r.payment_method, r.payment_status, r.created_at, cu.full_name AS customer, du.full_name AS driver FROM rides r JOIN users cu ON cu.id=r.customer_id LEFT JOIN users du ON du.id=r.driver_id WHERE (:s::text IS NULL OR r.status=:s) ORDER BY r.created_at DESC LIMIT :l OFFSET :o")
                .param("s", status).param("l", Math.min(size, 100)).param("o", Math.max(0, page) * Math.min(size, 100));
        return q.query().listOfRows();
    }

    @GetMapping("/rides/{id}") @PreAuthorize(ANY)
    public RideView ride(@PathVariable UUID id) { return rides.get(id, Auth.id(), Auth.user().roles()); }

    @GetMapping("/rides/{id}/history") @PreAuthorize(ANY)
    public List<Map<String, Object>> rideHistory(@PathVariable UUID id) {
        return jdbc.sql("SELECT from_status, to_status, actor, created_at FROM ride_status_history WHERE ride_id=:r ORDER BY id").param("r", id).query().listOfRows();
    }

    // ---------------- drivers ----------------
    @GetMapping("/drivers") @PreAuthorize(ANY)
    public List<Map<String, Object>> drivers(@RequestParam(required = false) String verification) {
        return jdbc.sql("""
                SELECT d.user_id AS id, u.full_name, u.phone, d.verification, d.availability, d.rating_avg, d.rating_count, d.created_at,
                       v.brand, v.model, v.plate, v.category_code, v.approved AS vehicle_approved,
                       (SELECT count(*) FROM driver_documents x WHERE x.driver_id=d.user_id) AS documents
                FROM drivers d JOIN users u ON u.id=d.user_id LEFT JOIN vehicles v ON v.driver_id=d.user_id AND v.active
                WHERE (:v::text IS NULL OR d.verification=:v) ORDER BY d.created_at DESC LIMIT 200""").param("v", verification).query().listOfRows();
    }

    @GetMapping("/drivers/{id}/documents") @PreAuthorize(OPS)
    public List<Map<String, Object>> driverDocs(@PathVariable UUID id) {
        return jdbc.sql("SELECT id, doc_type AS type, status, content_type, size_bytes, created_at FROM driver_documents WHERE driver_id=:d ORDER BY created_at DESC").param("d", id).query().listOfRows();
    }

    @GetMapping("/drivers/documents/{docId}/file") @PreAuthorize(OPS)
    public ResponseEntity<byte[]> doc(@PathVariable UUID docId) {
        var f = documents.adminFile(docId);
        audit.log(Auth.id(), role(), "DOCUMENT_VIEWED", "driver_document", docId, null);
        return ResponseEntity.ok().contentType(MediaType.parseMediaType((String) f.get("contentType"))).header("X-Content-Type-Options", "nosniff")
                .header("Content-Disposition", "attachment").body((byte[]) f.get("bytes"));
    }

    public record VerificationRequest(@NotBlank @Pattern(regexp = "APPROVED|REJECTED|SUSPENDED") String status, @Size(max = 300) String reason) {}

    @PutMapping("/drivers/{id}/verification") @PreAuthorize(OPS) @Transactional
    public Map<String, Object> verify(@PathVariable UUID id, @Valid @RequestBody VerificationRequest r) {
        var cur = jdbc.sql("SELECT verification, availability FROM drivers WHERE user_id=:u FOR UPDATE").param("u", id).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> ApiException.notFound("driver_not_found", "Driver not found"));
        if (!"APPROVED".equals(r.status()) && (r.reason() == null || r.reason().isBlank())) throw ApiException.badRequest("reason_required", "A reason is required");
        String avail = "APPROVED".equals(r.status()) ? ("SUSPENDED".equals(cur.get("availability")) ? "OFFLINE" : (String) cur.get("availability")) : ("SUSPENDED".equals(r.status()) ? "SUSPENDED" : "OFFLINE");
        if (!"APPROVED".equals(r.status()) && jdbc.sql("SELECT count(*) FROM rides WHERE driver_id=:d AND status IN ('DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS')").param("d", id).query(Integer.class).single() > 0)
            throw ApiException.conflict("driver_has_active_ride", "Driver has an active ride");
        jdbc.sql("UPDATE drivers SET verification=:v, availability=:a, rejection_reason=:r, updated_at=now() WHERE user_id=:u").param("v", r.status()).param("a", avail).param("r", r.reason()).param("u", id).update();
        jdbc.sql("UPDATE vehicles SET approved=:ok WHERE driver_id=:u").param("ok", "APPROVED".equals(r.status())).param("u", id).update();
        if (!"APPROVED".equals(r.status())) {
            jdbc.sql("DELETE FROM driver_locations WHERE driver_id=:u").param("u", id).update();
            jdbc.sql("UPDATE ride_offers SET status='CANCELLED', responded_at=now() WHERE driver_id=:u AND status='OFFERED'").param("u", id).update();
        }
        audit.log(Auth.id(), role(), "DRIVER_VERIFICATION", "driver", id, Map.of("status", r.status(), "reason", r.reason() == null ? "" : r.reason()));
        notifier.notify(id, "VERIFICATION_STATUS", "verification-" + id + "-" + r.status() + "-" + System.nanoTime(), Map.of("status", r.status()));
        return Map.of("id", id, "verification", r.status());
    }

    // ---------------- customers ----------------
    @GetMapping("/customers") @PreAuthorize(ANY)
    public List<Map<String, Object>> customers(@RequestParam(required = false) String q) {
        return jdbc.sql("""
                SELECT u.id, u.full_name, u.phone, u.email, u.status, u.created_at,
                       (SELECT count(*) FROM rides r WHERE r.customer_id=u.id AND r.status='COMPLETED') AS completed_rides
                FROM users u JOIN user_roles ur ON ur.user_id=u.id AND ur.role='CUSTOMER'
                WHERE u.deleted_at IS NULL AND (:q::text IS NULL OR u.full_name ILIKE :like OR u.phone LIKE :like OR u.email ILIKE :like)
                ORDER BY u.created_at DESC LIMIT 100""").param("q", q).param("like", q == null ? null : "%" + q.replace("%", "") + "%").query().listOfRows();
    }

    public record StatusRequest(@NotBlank @Pattern(regexp = "ACTIVE|SUSPENDED") String status, @Size(max = 300) String reason) {}

    @PutMapping("/users/{id}/status") @PreAuthorize(OPS) @Transactional
    public Map<String, Object> userStatus(@PathVariable UUID id, @Valid @RequestBody StatusRequest r) {
        if (id.equals(Auth.id())) throw ApiException.badRequest("self_suspend", "You cannot change your own status");
        int n = jdbc.sql("UPDATE users SET status=:s, updated_at=now() WHERE id=:id AND deleted_at IS NULL").param("s", r.status()).param("id", id).update();
        if (n == 0) throw ApiException.notFound("user_not_found", "User not found");
        if ("SUSPENDED".equals(r.status())) {
            jdbc.sql("UPDATE refresh_tokens SET revoked_at=now() WHERE user_id=:id AND revoked_at IS NULL").param("id", id).update();
            jdbc.sql("UPDATE drivers SET availability='SUSPENDED' WHERE user_id=:id AND availability IN ('OFFLINE','ONLINE','PAUSED')").param("id", id).update();
            jdbc.sql("DELETE FROM driver_locations WHERE driver_id=:id AND driver_id IN (SELECT user_id FROM drivers WHERE availability='SUSPENDED')").param("id", id).update();
        } else jdbc.sql("UPDATE drivers SET availability='OFFLINE' WHERE user_id=:id AND availability='SUSPENDED' AND verification='APPROVED'").param("id", id).update();
        audit.log(Auth.id(), role(), "USER_STATUS", "user", id, Map.of("status", r.status(), "reason", r.reason() == null ? "" : r.reason()));
        return Map.of("id", id, "status", r.status());
    }

    // ---------------- pricing ----------------
    @GetMapping("/pricing") @PreAuthorize(ANY)
    public List<Map<String, Object>> pricing() {
        return jdbc.sql("SELECT p.id, c.code AS city, p.category_code, p.base_fare, p.per_km, p.per_minute, p.min_fare, p.booking_fee, p.cancellation_fee, p.free_cancel_seconds, p.commission_rate, p.demand_multiplier, p.rounding_step, p.active FROM pricing_rules p JOIN cities c ON c.id=p.city_id ORDER BY c.code, p.category_code").query().listOfRows();
    }

    public record PricingUpdate(@NotNull @DecimalMin("0") @DecimalMax("1000000") BigDecimal baseFare, @NotNull @DecimalMin("0") @DecimalMax("100000") BigDecimal perKm,
                                @NotNull @DecimalMin("0") @DecimalMax("100000") BigDecimal perMinute, @NotNull @DecimalMin("0") @DecimalMax("1000000") BigDecimal minFare,
                                @NotNull @DecimalMin("0") @DecimalMax("100000") BigDecimal bookingFee, @NotNull @DecimalMin("0") @DecimalMax("100000") BigDecimal cancellationFee,
                                @Min(0) @Max(3600) int freeCancelSeconds, @NotNull @DecimalMin("0") @DecimalMax("0.5") BigDecimal commissionRate,
                                @NotNull @DecimalMin("1") @DecimalMax("5") BigDecimal demandMultiplier, boolean active) {}

    @PutMapping("/pricing/{id}") @PreAuthorize(FIN) @Transactional
    public Map<String, Object> updatePricing(@PathVariable UUID id, @Valid @RequestBody PricingUpdate r) {
        var before = jdbc.sql("SELECT base_fare, per_km, per_minute, min_fare, commission_rate, demand_multiplier, active FROM pricing_rules WHERE id=:id").param("id", id).query().listOfRows();
        if (before.isEmpty()) throw ApiException.notFound("pricing_not_found", "Pricing rule not found");
        jdbc.sql("UPDATE pricing_rules SET base_fare=:b, per_km=:k, per_minute=:m, min_fare=:mf, booking_fee=:bf, cancellation_fee=:cf, free_cancel_seconds=:fc, commission_rate=:cr, demand_multiplier=:dm, active=:a, updated_at=now() WHERE id=:id")
                .param("b", Money.scale(r.baseFare())).param("k", Money.scale(r.perKm())).param("m", Money.scale(r.perMinute())).param("mf", Money.scale(r.minFare()))
                .param("bf", Money.scale(r.bookingFee())).param("cf", Money.scale(r.cancellationFee())).param("fc", r.freeCancelSeconds()).param("cr", r.commissionRate())
                .param("dm", r.demandMultiplier()).param("a", r.active()).param("id", id).update();
        audit.log(Auth.id(), role(), "PRICING_UPDATED", "pricing_rule", id, Map.of("before", before.get(0).toString(), "after", r.toString()));
        return Map.of("id", id);
    }

    // ---------------- peak-hour windows ----------------
    public record PeakWindowRequest(@NotBlank String city, @NotBlank @Size(max = 60) String label,
                                    @NotNull @Size(min = 1, max = 7) List<@Min(1) @Max(7) Integer> days,
                                    @NotNull @Pattern(regexp = "([01]\\d|2[0-3]):[0-5]\\d") String start, @NotNull @Pattern(regexp = "([01]\\d|2[0-3]):[0-5]\\d") String end,
                                    @NotNull @DecimalMin("1") @DecimalMax("3") BigDecimal multiplier, boolean active) {}

    private UUID cityId(String code) {
        return jdbc.sql("SELECT id FROM cities WHERE code=:c").param("c", code).query(UUID.class).optional().orElseThrow(() -> ApiException.badRequest("city_not_found", "Unknown city code"));
    }

    @GetMapping("/pricing/peak-windows") @PreAuthorize(ANY)
    public List<Map<String, Object>> peakWindows() {
        var rows = jdbc.sql("SELECT w.id, c.code AS city, w.label, array_to_string(w.days, ',') AS days, to_char(w.start_time,'HH24:MI') AS start, to_char(w.end_time,'HH24:MI') AS \"end\", w.multiplier, w.active FROM peak_windows w JOIN cities c ON c.id=w.city_id ORDER BY c.code, w.start_time").query().listOfRows();
        List<Map<String, Object>> out = new ArrayList<>();
        for (var row : rows) {            // days as a JSON array of ISO weekdays
            Map<String, Object> m = new LinkedHashMap<>(row);
            m.put("days", Arrays.stream(((String) row.get("days")).split(",")).map(Integer::valueOf).toList());
            out.add(m);
        }
        return out;
    }

    @PostMapping("/pricing/peak-windows") @ResponseStatus(HttpStatus.CREATED) @PreAuthorize(FIN) @Transactional
    public Map<String, Object> createPeakWindow(@Valid @RequestBody PeakWindowRequest r) {
        UUID city = cityId(r.city());
        UUID id = jdbc.sql("INSERT INTO peak_windows(city_id,label,days,start_time,end_time,multiplier,active) VALUES (:c, :l, :d::smallint[], :s::time, :e::time, :m, :a) RETURNING id")
                .param("c", city).param("l", r.label().trim()).param("d", "{" + r.days().stream().distinct().sorted().map(String::valueOf).collect(java.util.stream.Collectors.joining(",")) + "}")
                .param("s", r.start()).param("e", r.end()).param("m", r.multiplier()).param("a", r.active()).query(UUID.class).single();
        audit.log(Auth.id(), role(), "PEAK_WINDOW_CREATED", "peak_window", id, Map.of("after", r.toString()));
        return Map.of("id", id);
    }

    @PutMapping("/pricing/peak-windows/{id}") @PreAuthorize(FIN) @Transactional
    public Map<String, Object> updatePeakWindow(@PathVariable UUID id, @Valid @RequestBody PeakWindowRequest r) {
        UUID city = cityId(r.city());
        int n = jdbc.sql("UPDATE peak_windows SET city_id=:c, label=:l, days=:d::smallint[], start_time=:s::time, end_time=:e::time, multiplier=:m, active=:a, updated_at=now() WHERE id=:id")
                .param("c", city).param("l", r.label().trim()).param("d", "{" + r.days().stream().distinct().sorted().map(String::valueOf).collect(java.util.stream.Collectors.joining(",")) + "}")
                .param("s", r.start()).param("e", r.end()).param("m", r.multiplier()).param("a", r.active()).param("id", id).update();
        if (n == 0) throw ApiException.notFound("peak_window_not_found", "Peak window not found");
        audit.log(Auth.id(), role(), "PEAK_WINDOW_UPDATED", "peak_window", id, Map.of("after", r.toString()));
        return Map.of("id", id);
    }

    @DeleteMapping("/pricing/peak-windows/{id}") @ResponseStatus(HttpStatus.NO_CONTENT) @PreAuthorize(FIN) @Transactional
    public void deletePeakWindow(@PathVariable UUID id) {
        if (jdbc.sql("DELETE FROM peak_windows WHERE id=:id").param("id", id).update() == 0) throw ApiException.notFound("peak_window_not_found", "Peak window not found");
        audit.log(Auth.id(), role(), "PEAK_WINDOW_DELETED", "peak_window", id, Map.of());
    }

    // ---------------- promo codes ----------------
    public record PromoRequest(@NotBlank @Pattern(regexp = "[A-Za-z0-9_-]{3,30}") String code, @Size(max = 200) String description,
                               @NotBlank @Pattern(regexp = "PERCENT|FIXED") String kind, @NotNull @DecimalMin("0.01") @DecimalMax("1000000") BigDecimal value,
                               @DecimalMin("0.01") @DecimalMax("1000000") BigDecimal maxDiscount, @DecimalMin("0") @DecimalMax("1000000") BigDecimal minFare,
                               String startsAt, String endsAt, @Min(1) Integer maxRedemptions, @Min(1) @Max(1000) Integer perUserLimit, boolean firstRideOnly, boolean active) {}

    private void checkPromo(PromoRequest r) {
        if ("PERCENT".equals(r.kind()) && r.value().compareTo(new BigDecimal("100")) > 0) throw ApiException.badRequest("invalid_promo", "A percentage cannot exceed 100");
        try {
            if (r.startsAt() != null && !r.startsAt().isBlank() && r.endsAt() != null && !r.endsAt().isBlank()
                    && !java.time.OffsetDateTime.parse(r.endsAt()).isAfter(java.time.OffsetDateTime.parse(r.startsAt()))) throw ApiException.badRequest("invalid_promo", "The end must be after the start");
            if (r.startsAt() != null && !r.startsAt().isBlank()) java.time.OffsetDateTime.parse(r.startsAt());
            if (r.endsAt() != null && !r.endsAt().isBlank()) java.time.OffsetDateTime.parse(r.endsAt());
        } catch (java.time.format.DateTimeParseException e) { throw ApiException.badRequest("invalid_promo", "Dates must be ISO-8601 with an offset, e.g. 2026-12-01T00:00:00+05:00"); }
    }
    private static String blankToNull(String s) { return s == null || s.isBlank() ? null : s; }

    @GetMapping("/promos") @PreAuthorize(ANY)
    public List<Map<String, Object>> promos() {
        return jdbc.sql("""
                SELECT p.id, p.code, p.description, p.kind, p.value, p.max_discount, p.min_fare, p.starts_at, p.ends_at, p.max_redemptions, p.per_user_limit, p.first_ride_only, p.active,
                       (SELECT count(*) FROM promo_redemptions x WHERE x.promo_id=p.id AND x.status='APPLIED') AS applied,
                       (SELECT count(*) FROM promo_redemptions x WHERE x.promo_id=p.id AND x.status='RESERVED') AS reserved,
                       (SELECT COALESCE(sum(x.discount),0) FROM promo_redemptions x WHERE x.promo_id=p.id AND x.status='APPLIED') AS total_discount
                FROM promo_codes p ORDER BY p.created_at DESC""").query().listOfRows();
    }

    @PostMapping("/promos") @ResponseStatus(HttpStatus.CREATED) @PreAuthorize(FIN) @Transactional
    public Map<String, Object> createPromo(@Valid @RequestBody PromoRequest r) {
        checkPromo(r);
        try {
            UUID id = jdbc.sql("INSERT INTO promo_codes(code,description,kind,value,max_discount,min_fare,starts_at,ends_at,max_redemptions,per_user_limit,first_ride_only,active) VALUES (:c,:d,:k,:v,:md,:mf,:s::timestamptz,:e::timestamptz,:mr,:pu,:fr,:a) RETURNING id")
                    .param("c", r.code().toUpperCase()).param("d", r.description()).param("k", r.kind()).param("v", r.value()).param("md", r.maxDiscount()).param("mf", r.minFare() == null ? BigDecimal.ZERO : r.minFare())
                    .param("s", blankToNull(r.startsAt())).param("e", blankToNull(r.endsAt())).param("mr", r.maxRedemptions()).param("pu", r.perUserLimit() == null ? 1 : r.perUserLimit()).param("fr", r.firstRideOnly()).param("a", r.active())
                    .query(UUID.class).single();
            audit.log(Auth.id(), role(), "PROMO_CREATED", "promo_code", id, Map.of("after", r.toString()));
            return Map.of("id", id);
        } catch (org.springframework.dao.DuplicateKeyException e) { throw ApiException.conflict("promo_exists", "A promo code with this name already exists"); }
    }

    /** The code itself cannot be renamed (riders may have it); everything else can change, and a code is switched off with active=false rather than deleted. */
    @PutMapping("/promos/{id}") @PreAuthorize(FIN) @Transactional
    public Map<String, Object> updatePromo(@PathVariable UUID id, @Valid @RequestBody PromoRequest r) {
        checkPromo(r);
        int n = jdbc.sql("UPDATE promo_codes SET description=:d, kind=:k, value=:v, max_discount=:md, min_fare=:mf, starts_at=:s::timestamptz, ends_at=:e::timestamptz, max_redemptions=:mr, per_user_limit=:pu, first_ride_only=:fr, active=:a, updated_at=now() WHERE id=:id AND code=:c")
                .param("c", r.code().toUpperCase()).param("d", r.description()).param("k", r.kind()).param("v", r.value()).param("md", r.maxDiscount()).param("mf", r.minFare() == null ? BigDecimal.ZERO : r.minFare())
                .param("s", blankToNull(r.startsAt())).param("e", blankToNull(r.endsAt())).param("mr", r.maxRedemptions()).param("pu", r.perUserLimit() == null ? 1 : r.perUserLimit()).param("fr", r.firstRideOnly()).param("a", r.active()).param("id", id).update();
        if (n == 0) throw ApiException.notFound("promo_not_found", "Promo code not found (the code itself cannot be changed)");
        audit.log(Auth.id(), role(), "PROMO_UPDATED", "promo_code", id, Map.of("after", r.toString()));
        return Map.of("id", id);
    }

    // ---------------- payments / refunds ----------------
    @GetMapping("/payments") @PreAuthorize(FIN)
    public List<Map<String, Object>> payments(@RequestParam(required = false) String status) {
        return jdbc.sql("SELECT p.id, p.purpose, p.provider, p.amount, p.status, p.failure_reason, p.ride_id, p.created_at, u.full_name AS customer FROM payment_transactions p JOIN users u ON u.id=p.user_id WHERE (:s::text IS NULL OR p.status=:s) ORDER BY p.created_at DESC LIMIT 100").param("s", status).query().listOfRows();
    }

    public record RefundRequest(@NotBlank @Size(max = 200) String reason) {}

    @PostMapping("/payments/{id}/refund") @PreAuthorize(FIN) @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> refund(@PathVariable UUID id, @Valid @RequestBody RefundRequest r) {
        UUID refundId = payments.refund(Auth.id(), id, r.reason());
        audit.log(Auth.id(), role(), "PAYMENT_REFUNDED", "payment", id, Map.of("reason", r.reason()));
        return Map.of("refundId", refundId);
    }

    @GetMapping("/wallets") @PreAuthorize(FIN)
    public List<Map<String, Object>> wallets() {
        return jdbc.sql("SELECT a.id, a.type, a.balance, u.full_name AS owner FROM accounts a LEFT JOIN users u ON u.id=a.owner_id ORDER BY a.type, a.balance DESC LIMIT 200").query().listOfRows();
    }

    // ---------------- support ----------------
    @GetMapping("/support/tickets") @PreAuthorize(ANY)
    public List<Map<String, Object>> tickets(@RequestParam(required = false) String status) {
        return jdbc.sql("SELECT t.id, t.category, t.subject, t.status, t.updated_at, u.full_name AS user_name FROM support_tickets t JOIN users u ON u.id=t.user_id WHERE (:s::text IS NULL OR t.status=:s) ORDER BY t.updated_at DESC LIMIT 100").param("s", status).query().listOfRows();
    }

    @GetMapping("/support/tickets/{id}/messages") @PreAuthorize(ANY)
    public List<Map<String, Object>> ticketMessages(@PathVariable UUID id) {
        return jdbc.sql("SELECT id, body, from_agent, created_at FROM support_messages WHERE ticket_id=:t ORDER BY created_at").param("t", id).query().listOfRows();
    }

    public record ReplyRequest(@NotBlank @Size(max = 2000) String body, @Pattern(regexp = "OPEN|PENDING|RESOLVED|CLOSED") String status) {}

    @PostMapping("/support/tickets/{id}/messages") @PreAuthorize(ANY) @Transactional @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> reply(@PathVariable UUID id, @Valid @RequestBody ReplyRequest r) {
        UUID owner = jdbc.sql("SELECT user_id FROM support_tickets WHERE id=:t").param("t", id).query(UUID.class).optional().orElseThrow(() -> ApiException.notFound("ticket_not_found", "Ticket not found"));
        UUID mid = jdbc.sql("INSERT INTO support_messages(ticket_id,sender_id,from_agent,body) VALUES (:t,:u,true,:b) RETURNING id").param("t", id).param("u", Auth.id()).param("b", r.body()).query(UUID.class).single();
        jdbc.sql("UPDATE support_tickets SET status=COALESCE(:s,'PENDING'), updated_at=now() WHERE id=:t").param("s", r.status()).param("t", id).update();
        notifier.notify(owner, "SUPPORT_MESSAGE", "support-" + mid, Map.of("ticketId", id.toString(), "messageId", mid.toString()));
        return Map.of("id", mid);
    }

    // ---------------- settings / audit / staff ----------------
    @GetMapping("/settings") @PreAuthorize("hasRole('SUPER_ADMIN')")
    public List<Map<String, Object>> settings() { return jdbc.sql("SELECT key, value, description FROM application_settings ORDER BY key").query().listOfRows(); }

    public record SettingUpdate(@NotBlank @Size(max = 500) String value) {}

    @PutMapping("/settings/{key}") @PreAuthorize("hasRole('SUPER_ADMIN')")
    public Map<String, Object> setSetting(@PathVariable String key, @Valid @RequestBody SettingUpdate r) {
        String old = jdbc.sql("SELECT value FROM application_settings WHERE key=:k").param("k", key).query(String.class).optional().orElseThrow(() -> ApiException.notFound("setting_not_found", "Unknown setting"));
        try { new BigDecimal(r.value()); } catch (NumberFormatException e) { throw ApiException.badRequest("invalid_value", "Setting must be numeric"); }
        jdbc.sql("UPDATE application_settings SET value=:v, updated_at=now() WHERE key=:k").param("v", r.value()).param("k", key).update();
        audit.log(Auth.id(), role(), "SETTING_UPDATED", "setting", key, Map.of("old", old, "new", r.value()));
        return Map.of("key", key, "value", r.value());
    }

    @GetMapping("/audit-logs") @PreAuthorize("hasRole('SUPER_ADMIN')")
    public List<Map<String, Object>> auditLogs(@RequestParam(defaultValue = "100") int limit) {
        return jdbc.sql("SELECT a.id, a.actor_id, u.full_name AS actor, a.actor_role, a.action, a.entity_type, a.entity_id, a.details, a.created_at FROM audit_logs a LEFT JOIN users u ON u.id=a.actor_id ORDER BY a.id DESC LIMIT :l").param("l", Math.min(limit, 500)).query().listOfRows();
    }

    public record StaffRequest(@NotBlank @Size(min = 2, max = 120) String fullName, @NotBlank String phone, @NotBlank @Size(min = 10, max = 72) String password,
                               @NotBlank @Pattern(regexp = "OPERATIONS_ADMIN|FINANCE_ADMIN|SUPPORT_AGENT|PARTNER_ADMIN") String role) {}

    @PostMapping("/staff") @PreAuthorize("hasRole('SUPER_ADMIN')") @Transactional @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> createStaff(@Valid @RequestBody StaffRequest r) {
        String phone = kz.jolay.identity.AuthService.normalizePhone(r.phone());
        UUID id = jdbc.sql("INSERT INTO users(phone,password_hash,full_name,phone_verified) VALUES (:p,:h,:n,true) RETURNING id").param("p", phone).param("h", encoder.encode(r.password())).param("n", r.fullName()).query(UUID.class).single();
        jdbc.sql("INSERT INTO user_roles(user_id,role) VALUES (:u,:r)").param("u", id).param("r", r.role()).update();
        audit.log(Auth.id(), role(), "STAFF_CREATED", "user", id, Map.of("role", r.role()));
        return Map.of("id", id, "role", r.role());
    }
}
