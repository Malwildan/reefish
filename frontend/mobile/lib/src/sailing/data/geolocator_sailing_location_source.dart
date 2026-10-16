import 'package:geolocator/geolocator.dart';

import '../domain/sailing_location_source.dart';
import '../domain/sailing_session.dart';

/// Geolocator foreground stream only. The host app owns lifecycle disposal;
/// this source does not request background permission or enable background mode.
class GeolocatorSailingLocationSource implements SailingLocationSource {
  const GeolocatorSailingLocationSource();

  @override
  Future<SailingPermission> requestForegroundPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return SailingPermission.serviceDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return SailingPermission.deniedForever;
    }
    if (permission == LocationPermission.denied) {
      return SailingPermission.denied;
    }
    return SailingPermission.granted;
  }

  @override
  Stream<SailingPosition> get positions =>
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).map(
        (position) => SailingPosition(
          point: SailingPoint(lat: position.latitude, lng: position.longitude),
          recordedAt: position.timestamp.toUtc(),
          accuracyM: position.accuracy,
          speedMs: position.speed < 0 ? null : position.speed,
        ),
      );
}
