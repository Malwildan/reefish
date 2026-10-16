import 'package:geolocator/geolocator.dart';

import '../domain/geo_point.dart';

abstract interface class DeviceLocationService {
  Future<GeoPoint> getCurrentPosition();
}

class GeolocatorDeviceLocationService implements DeviceLocationService {
  const GeolocatorDeviceLocationService();

  @override
  Future<GeoPoint> getCurrentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationServiceFailure(
        'Layanan lokasi mati. Kamu tetap bisa memilih titik di peta.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationServiceFailure(
        'Izin lokasi ditolak. Kamu tetap bisa memilih titik di peta.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationServiceFailure(
        'Izin lokasi dimatikan. Kamu tetap bisa memilih titik di peta.',
      );
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return GeoPoint(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } on LocationServiceDisabledException {
      throw const LocationServiceFailure(
        'Layanan lokasi mati. Kamu tetap bisa memilih titik di peta.',
      );
    } on PermissionDeniedException {
      throw const LocationServiceFailure(
        'Izin lokasi belum tersedia. Kamu tetap bisa memilih titik di peta.',
      );
    } on Exception {
      throw const LocationServiceFailure(
        'Lokasi perangkat belum tersedia. Kamu tetap bisa memilih titik di peta.',
      );
    }
  }
}

class LocationServiceFailure implements Exception {
  const LocationServiceFailure(this.message);

  final String message;
}
