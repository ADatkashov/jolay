package kz.jolay.geography;

import kz.jolay.common.GeoPoint;

import java.util.List;

/**
 * Routing abstraction. Production uses {@link TwoGisRouteProvider} (see {@link RoutingConfig}).
 * The default {@link EstimatedRouteProvider} is a DEVELOPMENT FALLBACK: great-circle distance scaled by a detour factor.
 * Its result is flagged source=ESTIMATED so clients never present it as live navigation.
 */
public interface RouteProvider {
    RouteInfo route(GeoPoint from, GeoPoint to);

    /** Route with its road geometry and turn-by-turn steps. Providers without geometry return a straight line and no steps. */
    default RouteDetail detail(GeoPoint from, GeoPoint to) {
        RouteInfo r = route(from, to);
        return new RouteDetail(r.distanceM(), r.durationS(), r.source(), List.of(new double[]{from.lat(), from.lng()}, new double[]{to.lat(), to.lng()}), List.of());
    }

    record RouteInfo(int distanceM, int durationS, String source) {}

    /** {@code polyline} is a list of {@code [lat, lng]} pairs. */
    record RouteDetail(int distanceM, int durationS, String source, List<double[]> polyline, List<Step> steps) {}

    /** One manoeuvre: text such as "Turn right onto ...", the 2GIS icon name, length of the segment after it and where it happens. */
    record Step(String text, String icon, int distanceM, Double lat, Double lng) {}
}
