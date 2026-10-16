import 'departure_repository.dart';
import 'geo_point.dart';

/// A fishing location chosen after the departure has been recorded.
///
/// The departure is retained as context; saving a fishing point must never
/// overwrite the separately stored departure selection.
class FishingPointSelection {
  const FishingPointSelection({
    required this.point,
    required this.cellId,
    required this.departure,
    required this.savedAt,
  });

  final GeoPoint point;
  final String cellId;
  final DeparturePoint departure;
  final DateTime savedAt;
}

abstract interface class FishingPointRepository {
  Future<void> save(FishingPointSelection selection);
  Future<FishingPointSelection?> read();
}
