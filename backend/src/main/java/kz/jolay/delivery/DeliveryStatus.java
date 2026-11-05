package kz.jolay.delivery;

import java.util.EnumSet;
import java.util.Map;
import java.util.Set;

public enum DeliveryStatus {
    SEARCHING_COURIER, COURIER_ASSIGNED, PICKED_UP, DELIVERED, CANCELLED, EXPIRED, FAILED;

    private static final Map<DeliveryStatus, Set<DeliveryStatus>> ALLOWED = Map.of(
            SEARCHING_COURIER, EnumSet.of(COURIER_ASSIGNED, CANCELLED, EXPIRED, FAILED),
            // COURIER_ASSIGNED -> SEARCHING_COURIER is the "courier cancelled, find another" re-queue
            COURIER_ASSIGNED, EnumSet.of(PICKED_UP, SEARCHING_COURIER, CANCELLED, FAILED),
            PICKED_UP, EnumSet.of(DELIVERED, FAILED));

    public boolean canMoveTo(DeliveryStatus next) { return ALLOWED.getOrDefault(this, Set.of()).contains(next); }
    public boolean isTerminal() { return this == DELIVERED || this == CANCELLED || this == EXPIRED || this == FAILED; }
}
