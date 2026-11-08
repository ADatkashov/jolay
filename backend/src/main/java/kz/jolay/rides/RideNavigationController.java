package kz.jolay.rides;

import jakarta.validation.Valid;
import kz.jolay.common.Auth;
import kz.jolay.common.GeoPoint;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.UUID;

/** In-app navigation for both sides of a ride: the customer sees the driver coming, the driver sees the rider and the road. */
@RestController
@RequestMapping("/api/v1/rides")
@PreAuthorize("hasAnyRole('CUSTOMER','DRIVER')")
public class RideNavigationController {
    private final RideNavigationService nav;
    public RideNavigationController(RideNavigationService nav) { this.nav = nav; }

    @GetMapping("/{id}/navigation")
    public RideNavigationService.Navigation navigation(@PathVariable UUID id) { return nav.navigation(id, Auth.id()); }

    @PostMapping("/{id}/customer-location") @ResponseStatus(HttpStatus.NO_CONTENT)
    @PreAuthorize("hasRole('CUSTOMER')")
    public void shareLocation(@PathVariable UUID id, @Valid @RequestBody GeoPoint p) { nav.shareCustomerLocation(id, Auth.id(), p); }
}
