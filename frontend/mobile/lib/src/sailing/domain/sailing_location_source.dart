import 'sailing_session.dart';

class SailingPosition {
  const SailingPosition({
    required this.point,
    required this.recordedAt,
    required this.accuracyM,
    this.speedMs,
  });

  final SailingPoint point;
  final DateTime recordedAt;
  final double accuracyM;
  final double? speedMs;
}

enum SailingPermission { granted, denied, deniedForever, serviceDisabled }

abstract interface class SailingLocationSource {
  Future<SailingPermission> requestForegroundPermission();

  Stream<SailingPosition> get positions;
}
