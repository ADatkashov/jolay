package kz.jolay.drivers;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;

public final class DriverDtos {
    private DriverDtos() {}
    public record VehicleRequest(@NotBlank @Size(max = 60) String brand, @NotBlank @Size(max = 60) String model,
                                 @Min(1990) @Max(2100) int year, @NotBlank @Size(max = 30) String color,
                                 @NotBlank @Pattern(regexp = "[A-Za-z0-9 -]{4,15}") String plate, @NotBlank String category) {}
    public record DriverRegisterRequest(String cityCode, @NotNull @Valid VehicleRequest vehicle) {}
    public record AvailabilityRequest(boolean online) {}
}
