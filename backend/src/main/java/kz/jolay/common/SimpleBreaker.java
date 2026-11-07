package kz.jolay.common;

import java.time.Duration;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

/** Minimal circuit breaker for optional external services: after N consecutive failures the service is skipped for a while. */
public class SimpleBreaker {
    private final int failuresToOpen;
    private final Duration openFor;
    private final AtomicInteger consecutive = new AtomicInteger();
    private final AtomicLong openUntilMillis = new AtomicLong();

    public SimpleBreaker(int failuresToOpen, Duration openFor) { this.failuresToOpen = failuresToOpen; this.openFor = openFor; }

    public boolean isOpen() { return System.currentTimeMillis() < openUntilMillis.get(); }
    public void success() { consecutive.set(0); }
    /** Returns true when this failure opened the breaker. */
    public boolean failure() {
        if (consecutive.incrementAndGet() < failuresToOpen) return false;
        openUntilMillis.set(System.currentTimeMillis() + openFor.toMillis());
        consecutive.set(0);
        return true;
    }
}
