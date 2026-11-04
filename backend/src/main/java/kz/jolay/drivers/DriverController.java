package kz.jolay.drivers;

import jakarta.validation.Valid;
import kz.jolay.common.ApiException;
import kz.jolay.common.Auth;
import kz.jolay.dispatch.DispatchService;
import kz.jolay.drivers.DriverDtos.*;
import kz.jolay.rides.RideDtos.*;
import kz.jolay.rides.RideService;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/drivers")
@PreAuthorize("hasRole('DRIVER')")
public class DriverController {
    private final DriverService drivers;
    private final DispatchService dispatch;
    private final RideService rides;
    private final DocumentService documents;

    public DriverController(DriverService drivers, DispatchService dispatch, RideService rides, DocumentService documents) {
        this.drivers = drivers; this.dispatch = dispatch; this.rides = rides; this.documents = documents;
    }

    @PostMapping("/register") @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> register(@Valid @RequestBody DriverRegisterRequest r) { drivers.register(Auth.id(), r); return drivers.me(Auth.id()); }

    @GetMapping("/me")
    public Map<String, Object> me() { return drivers.me(Auth.id()); }

    @PostMapping("/documents") @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> upload(@RequestParam String type, @RequestParam("file") MultipartFile file) { return documents.store(Auth.id(), type, file); }

    @GetMapping("/documents")
    public List<Map<String, Object>> documents() { return documents.list(Auth.id()); }

    @PutMapping("/availability")
    public Map<String, Object> availability(@RequestBody AvailabilityRequest r) { drivers.setAvailability(Auth.id(), r.online()); return drivers.me(Auth.id()); }

    @PostMapping("/location") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void location(@Valid @RequestBody LocationRequest r) { drivers.updateLocation(Auth.id(), r); }

    @GetMapping("/offers")
    public Map<String, Object> offer() { return drivers.currentOffer(Auth.id()); }

    @PostMapping("/offers/{id}/accept")
    public RideView accept(@PathVariable UUID id) { UUID ride = dispatch.accept(Auth.id(), id); return rides.get(ride, Auth.id(), Auth.user().roles()); }

    @PostMapping("/offers/{id}/decline") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void decline(@PathVariable UUID id) { dispatch.decline(Auth.id(), id); }

    @GetMapping("/rides/active")
    public RideView active() { return rides.activeForDriver(Auth.id()).orElse(null); }

    @GetMapping("/rides/history")
    public List<RideView> history(@RequestParam(defaultValue = "completed") String tab, @RequestParam(defaultValue = "20") int limit, @RequestParam(defaultValue = "0") int offset) {
        return rides.history(Auth.id(), true, tab, limit, offset);
    }

    @PostMapping("/rides/{id}/en-route") public RideView enRoute(@PathVariable UUID id) { return rides.enRoute(id, Auth.id()); }
    @PostMapping("/rides/{id}/arrived") public RideView arrived(@PathVariable UUID id) { return rides.arrived(id, Auth.id()); }
    @PostMapping("/rides/{id}/start") public RideView start(@PathVariable UUID id) { return rides.start(id, Auth.id()); }
    @PostMapping("/rides/{id}/complete") public RideView complete(@PathVariable UUID id) { return rides.complete(id, Auth.id()); }

    @PostMapping("/rides/{id}/cancel") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void cancel(@PathVariable UUID id, @RequestBody(required = false) CancelRequest r) { rides.cancelByDriver(id, Auth.id(), r == null ? null : r.reason()); }

    @GetMapping("/earnings")
    public Map<String, Object> earnings(@RequestParam(defaultValue = "today") String period) { return drivers.earnings(Auth.id(), period); }
}
