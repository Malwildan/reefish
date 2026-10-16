import 'geo_point.dart';

class DeparturePoint {
  const DeparturePoint({
    required this.point,
    required this.cellId,
    required this.savedAt,
  });

  final GeoPoint point;
  final String cellId;
  final DateTime savedAt;
}

abstract interface class DepartureRepository {
  Future<void> save(DeparturePoint departure);
  Future<DeparturePoint?> read();
}
