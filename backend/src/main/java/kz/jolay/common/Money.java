package kz.jolay.common;

import java.math.BigDecimal;
import java.math.RoundingMode;

/** All monetary math is BigDecimal with scale 2 (KZT). Never use double for money. */
public final class Money {
    private Money() {}
    public static final BigDecimal ZERO = new BigDecimal("0.00");

    public static BigDecimal of(String v) { return new BigDecimal(v).setScale(2, RoundingMode.HALF_UP); }
    public static BigDecimal scale(BigDecimal v) { return v.setScale(2, RoundingMode.HALF_UP); }

    /** Round up to the next multiple of step (e.g. 10 KZT) so riders see round prices. */
    public static BigDecimal roundUp(BigDecimal v, BigDecimal step) {
        BigDecimal units = v.divide(step, 0, RoundingMode.CEILING);
        return scale(units.multiply(step));
    }
}
