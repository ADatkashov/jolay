package kz.jolay.geography;

import kz.jolay.common.AppSettings;
import kz.jolay.common.GeoPoint;
/** Development fallback (and the safety net of {@link TwoGisRouteProvider}); wired by {@link RoutingConfig}. */
public class EstimatedRouteProvider implements RouteProvider {
    private final AppSettings settings;
    public EstimatedRouteProvider(AppSettings settings) { this.settings = settings; }

    public static double haversineM(double lat1, double lng1, double lat2, double lng2) {
        double R = 6371008.8;
        double dLat = Math.toRadians(lat2 - lat1), dLng = Math.toRadians(lng2 - lng1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
        return 2 * R * Math.asin(Math.sqrt(a));
    }

    @Override
    public RouteInfo route(GeoPoint a, GeoPoint b) {
        double detour = settings.getDecimal("rides.detour_factor").doubleValue();
        double speedKmh = settings.getDecimal("rides.avg_speed_kmh").doubleValue();
        int dist = (int) Math.round(haversineM(a.lat(), a.lng(), b.lat(), b.lng()) * detour);
        int secs = (int) Math.round(dist / (speedKmh / 3.6));
        return new RouteInfo(dist, secs, "ESTIMATED");
    }
}
