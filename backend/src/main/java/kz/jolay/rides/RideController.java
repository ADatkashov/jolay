package kz.jolay.rides;

import jakarta.validation.Valid;
import kz.jolay.common.Auth;
import kz.jolay.rides.RideDtos.*;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/rides")
@PreAuthorize("hasRole('CUSTOMER')")
public class RideController {
    private final RideService rides;
    public RideController(RideService rides) { this.rides = rides; }

    @PostMapping("/estimate")
    public EstimateResponse estimate(@Valid @RequestBody EstimateRequest r, @RequestHeader(value = "Accept-Language", defaultValue = "en") String lang) {
        return rides.estimate(r, lang.length() >= 2 ? lang.substring(0, 2) : "en", Auth.id());
    }

    @PostMapping @ResponseStatus(HttpStatus.CREATED)
    public RideView create(@Valid @RequestBody CreateRideRequest r, @RequestHeader(value = "Idempotency-Key", required = false) String key) {
        return rides.create(Auth.id(), r, key);
    }

    @GetMapping("/active")
    public RideView active() { return rides.activeForCustomer(Auth.id()).orElse(null); }

    @GetMapping("/history")
    public List<RideView> history(@RequestParam(defaultValue = "completed") String tab, @RequestParam(defaultValue = "20") int limit, @RequestParam(defaultValue = "0") int offset) {
        return rides.history(Auth.id(), false, tab, limit, offset);
    }

    @GetMapping("/{id}")
    public RideView get(@PathVariable UUID id) { return rides.get(id, Auth.id(), Auth.user().roles()); }

    @GetMapping("/{id}/fare")
    public List<Map<String, Object>> fare(@PathVariable UUID id) { return rides.fareBreakdown(id, Auth.id(), Auth.user().roles()); }

    @PostMapping("/{id}/cancel")
    public RideView cancel(@PathVariable UUID id, @Valid @RequestBody(required = false) CancelRequest r) {
        return rides.cancelByCustomer(id, Auth.id(), r == null ? null : r.reason());
    }

    @PostMapping("/{id}/rating") @ResponseStatus(HttpStatus.CREATED)
    public void rate(@PathVariable UUID id, @Valid @RequestBody RatingRequest r) { rides.rate(id, Auth.id(), r); }
}
