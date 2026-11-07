/// Thin typed views over backend JSON. All money values stay as backend-provided strings and are only formatted for display.
class Place {
  final String name, address;
  final double lat, lng;
  const Place(this.name, this.address, this.lat, this.lng);
  factory Place.fromJson(Map<String, dynamic> j) => Place((j['name'] ?? j['address'] ?? j['label'] ?? '').toString(), (j['address'] ?? '').toString(), (j['lat'] as num).toDouble(), (j['lng'] as num).toDouble());
}

class FareView {
  final String base, distance, time, fees, discount, total;
  /// Demand/peak multiplier applied by the backend (1.0 = standard fare).
  final double multiplier;
  /// What the rider pays: total minus a platform-funded promo discount.
  final String payable;
  FareView.fromJson(Map<String, dynamic> j)
      : multiplier = double.tryParse('${j['multiplier'] ?? 1}') ?? 1,
        payable = (j['payable'] ?? j['total']).toString(),
        base = j['baseFare'].toString(), distance = j['distanceFare'].toString(), time = j['timeFare'].toString(),
        fees = j['fees'].toString(), discount = j['discount'].toString(), total = j['total'].toString();
}

class CategoryEstimate {
  final String code, name, description;
  final int capacity;
  final int? etaSeconds;
  final bool available;
  final FareView fare;
  CategoryEstimate.fromJson(Map<String, dynamic> j)
      : code = j['code'], name = j['name'], description = j['description'], capacity = j['capacity'], etaSeconds = j['etaSeconds'],
        available = j['available'] == true, fare = FareView.fromJson(j['fare']);
}

class Estimate {
  final int distanceM, durationS;
  final String routeSource;
  final List<CategoryEstimate> categories;
  Estimate.fromJson(Map<String, dynamic> j)
      : distanceM = j['distanceM'], durationS = j['durationS'], routeSource = j['routeSource'],
        categories = (j['categories'] as List).map((e) => CategoryEstimate.fromJson(e)).toList();
}

class DriverInfo {
  final String name, vehicle, color, plate;
  final String? phone;
  final String rating;
  final double? lat, lng;
  DriverInfo.fromJson(Map<String, dynamic> j)
      : name = j['name'] ?? '', vehicle = j['vehicle'] ?? '', color = j['color'] ?? '', plate = j['plate'] ?? '', phone = j['phone'],
        rating = (j['rating'] ?? '5.0').toString(), lat = (j['lat'] as num?)?.toDouble(), lng = (j['lng'] as num?)?.toDouble();
}

class Ride {
  final String id, status, category, pickupAddress, dropoffAddress, paymentMethod, paymentStatus;
  final double pickupLat, pickupLng, dropLat, dropLng;
  final int distanceM, durationS;
  final String estimatedFare;
  final String? finalFare, createdAt;
  final String cancellationFee;
  final DriverInfo? driver;
  final int? driverEtaSeconds, rating;
  final String? promoCode;
  final String promoDiscount, payable;

  Ride.fromJson(Map<String, dynamic> j)
      : id = j['id'], status = j['status'], category = j['category'], pickupAddress = j['pickupAddress'], dropoffAddress = j['dropoffAddress'],
        paymentMethod = j['paymentMethod'], paymentStatus = j['paymentStatus'], pickupLat = (j['pickup']['lat'] as num).toDouble(), pickupLng = (j['pickup']['lng'] as num).toDouble(),
        dropLat = (j['dropoff']['lat'] as num).toDouble(), dropLng = (j['dropoff']['lng'] as num).toDouble(), distanceM = j['distanceM'], durationS = j['durationS'],
        estimatedFare = j['estimatedFare'].toString(), finalFare = j['finalFare']?.toString(), createdAt = j['createdAt']?.toString(),
        cancellationFee = (j['cancellationFee'] ?? '0').toString(), driver = j['driver'] == null ? null : DriverInfo.fromJson(j['driver']),
        driverEtaSeconds = j['driverEtaSeconds'], rating = j['rating'],
        promoCode = j['promoCode'], promoDiscount = (j['promoDiscount'] ?? '0').toString(), payable = (j['payable'] ?? j['finalFare'] ?? j['estimatedFare']).toString();

  bool get isTerminal => const {'COMPLETED', 'CANCELLED', 'EXPIRED', 'FAILED'}.contains(status);
  bool get canCancel => const {'SEARCHING_DRIVER', 'DRIVER_ASSIGNED', 'DRIVER_ARRIVING', 'DRIVER_ARRIVED'}.contains(status);
  String get fare => payable;
  bool get hasPromo => (double.tryParse(promoDiscount) ?? 0) > 0;
}
