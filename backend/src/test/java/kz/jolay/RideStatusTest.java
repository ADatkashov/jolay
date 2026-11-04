package kz.jolay;

import kz.jolay.rides.RideStatus;
import org.junit.jupiter.api.Test;

import static kz.jolay.rides.RideStatus.*;
import static org.junit.jupiter.api.Assertions.*;

class RideStatusTest {
    @Test void happyPathIsAllowed() {
        RideStatus[] path = {CREATED, SEARCHING_DRIVER, DRIVER_ASSIGNED, DRIVER_ARRIVING, DRIVER_ARRIVED, IN_PROGRESS, COMPLETED};
        for (int i = 0; i < path.length - 1; i++) assertTrue(path[i].canMoveTo(path[i + 1]), path[i] + "->" + path[i + 1]);
    }
    @Test void terminalStatesAreFinal() {
        for (RideStatus t : new RideStatus[]{COMPLETED, CANCELLED, EXPIRED, FAILED})
            for (RideStatus n : values()) assertFalse(t.canMoveTo(n), t + "->" + n);
    }
    @Test void noSkippingAndNoCancelOnceInProgress() {
        assertFalse(SEARCHING_DRIVER.canMoveTo(IN_PROGRESS));
        assertFalse(DRIVER_ASSIGNED.canMoveTo(COMPLETED));
        assertFalse(IN_PROGRESS.canMoveTo(CANCELLED));
        assertFalse(DRIVER_ARRIVED.canMoveTo(COMPLETED));
        assertFalse(CREATED.canMoveTo(IN_PROGRESS));
    }
}
