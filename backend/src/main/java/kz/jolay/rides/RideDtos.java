package kz.jolay.rides;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import kz.jolay.common.GeoPoint;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

public final class RideDtos {
    private RideDtos() {}

    public record Stop(@NotNull @Valid GeoPoint point, @Size(max = 300) String address) {}
    public record EstimateRequest(@NotNull @Valid GeoPoint pickup, @NotNull @Valid GeoPoint dropoff) {}
    public record CreateRideRequest(@NotNull @Valid Stop pickup, @NotNull @Valid Stop dropoff,
                                    @NotBlank String category, @NotBlank @Pattern(regexp = "CASH|CARD|WALLET") String paymentMethod) {}
    public record CancelRequest(@Size(max = 200) String reason) {}
    public record RatingRequest(@Min(1) @Max(5) int stars, @Size(max = 5) List<@Size(max = 40) String> tags, @Size(max = 500) String comment) {}
    public record LocationRequest(@NotNull @Valid GeoPoint point, @DecimalMin("0") @DecimalMax("360") Double heading, @DecimalMin("0") @DecimalMax("250") Double speedKmh) {}

    public record FareView(BigDecimal baseFare, BigDecimal distanceFare, BigDecimal timeFare, BigDecimal fees, BigDecimal discount,
                           BigDecimal multiplier, BigDecimal total, String currency) {}
    public record CategoryEstimate(String code, String name, String description, int capacity, FareView fare, Integer etaSeconds, boolean available) {}
    public record EstimateResponse(int distanceM, int durationS, String routeSource, List<CategoryEstimate> categories) {}

    public record DriverView(UUID id, String name, String phone, BigDecimal rating, String vehicle, String color, String plate, Double lat, Double lng) {}
    public record RideView(UUID id, String status, String category, String pickupAddress, GeoPoint pickup, String dropoffAddress, GeoPoint dropoff,
                           int distanceM, int durationS, BigDecimal estimatedFare, BigDecimal finalFare, String paymentMethod, String paymentStatus,
                           BigDecimal cancellationFee, DriverView driver, UUID customerId, String customerName, String customerPhone,
                           Integer driverEtaSeconds, Object createdAt, Object completedAt, Integer rating) {}
}
