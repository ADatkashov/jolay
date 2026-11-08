package kz.jolay.geography;

import kz.jolay.common.GeoPoint;

/**
 * Routing abstraction. Production uses {@link TwoGisRouteProvider} (see {@link RoutingConfig}).
 * The default {@link EstimatedRouteProvider} is a DEVELOPMENT FALLBACK: great-circle distance scaled by a detour factor.
 * Its result is flagged source=ESTIMATED so clients never present it as live navigation.
 */
public interface RouteProvider {
    RouteInfo route(GeoPoint from, GeoPoint to);

    record RouteInfo(int distanceM, int durationS, String source) {}
}
