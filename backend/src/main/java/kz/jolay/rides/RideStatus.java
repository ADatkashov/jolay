package kz.jolay.rides;

import java.util.EnumSet;
import java.util.Map;
import java.util.Set;

public enum RideStatus {
    CREATED, SEARCHING_DRIVER, DRIVER_ASSIGNED, DRIVER_ARRIVING, DRIVER_ARRIVED, IN_PROGRESS, COMPLETED, CANCELLED, EXPIRED, FAILED;

    private static final Map<RideStatus, Set<RideStatus>> ALLOWED = Map.of(
            CREATED, EnumSet.of(SEARCHING_DRIVER, CANCELLED, FAILED),
            SEARCHING_DRIVER, EnumSet.of(DRIVER_ASSIGNED, CANCELLED, EXPIRED, FAILED),
            // DRIVER_ASSIGNED/ARRIVING/ARRIVED -> SEARCHING_DRIVER is the "driver cancelled, find another driver" re-queue
            DRIVER_ASSIGNED, EnumSet.of(DRIVER_ARRIVING, SEARCHING_DRIVER, CANCELLED, FAILED),
            DRIVER_ARRIVING, EnumSet.of(DRIVER_ARRIVED, SEARCHING_DRIVER, CANCELLED, FAILED),
            DRIVER_ARRIVED, EnumSet.of(IN_PROGRESS, SEARCHING_DRIVER, CANCELLED, FAILED),
            IN_PROGRESS, EnumSet.of(COMPLETED, FAILED));

    public boolean canMoveTo(RideStatus next) { return ALLOWED.getOrDefault(this, Set.of()).contains(next); }
    public boolean isTerminal() { return this == COMPLETED || this == CANCELLED || this == EXPIRED || this == FAILED; }
    public boolean isActive() { return !isTerminal(); }
}
