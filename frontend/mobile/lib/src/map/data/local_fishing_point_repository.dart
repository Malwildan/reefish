import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/departure_repository.dart';
import '../domain/fishing_point_repository.dart';
import '../domain/geo_point.dart';
import '../domain/metric_grid_500.dart';

/// Stores an explicitly chosen fishing point separately from the departure.
/// This draft is not evidence that fishing activity or a catch took place.
class LocalFishingPointRepository implements FishingPointRepository {
  LocalFishingPointRepository({
    required SharedPreferences preferences,
    required String ownerId,
  }) : _preferences = preferences,
       _storageKey = 'reefish.fishing-point.v1.$ownerId' {
    if (ownerId.trim().isEmpty) throw ArgumentError.value(ownerId, 'ownerId');
  }

  final SharedPreferences _preferences;
  final String _storageKey;
  final _grid = MetricGrid500();

  @override
  Future<void> save(FishingPointSelection selection) async {
    _validate(selection.point, selection.cellId);
    _validate(selection.departure.point, selection.departure.cellId);
    final value = jsonEncode({
      'latitude': selection.point.latitude,
      'longitude': selection.point.longitude,
      'cell_id': selection.cellId,
      'saved_at': selection.savedAt.toUtc().toIso8601String(),
      'departure': {
        'latitude': selection.departure.point.latitude,
        'longitude': selection.departure.point.longitude,
        'cell_id': selection.departure.cellId,
        'saved_at': selection.departure.savedAt.toUtc().toIso8601String(),
      },
    });
    if (!await _preferences.setString(_storageKey, value)) {
      throw StateError('Could not save fishing point');
    }
  }

  @override
  Future<FishingPointSelection?> read() async {
    final raw = _preferences.getString(_storageKey);
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value['departure'] is! Map<String, dynamic>) {
        throw const FormatException('Fishing point must contain a departure');
      }
      final departure = _readPoint(value['departure'] as Map<String, dynamic>);
      final fishing = _readPoint(value);
      return FishingPointSelection(
        point: fishing.point,
        cellId: fishing.cellId,
        departure: departure,
        savedAt: fishing.savedAt,
      );
    } on ArgumentError {
      throw const FormatException('Stored fishing point is invalid; preserved');
    }
  }

  DeparturePoint _readPoint(Map<String, dynamic> value) {
    final latitude = value['latitude'];
    final longitude = value['longitude'];
    final cellId = value['cell_id'];
    final savedAt = value['saved_at'];
    if (latitude is! num ||
        longitude is! num ||
        cellId is! String ||
        savedAt is! String) {
      throw const FormatException('Invalid stored point fields');
    }
    final point = GeoPoint(
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
    );
    _validate(point, cellId);
    return DeparturePoint(
      point: point,
      cellId: cellId,
      savedAt: DateTime.parse(savedAt),
    );
  }

  void _validate(GeoPoint point, String cellId) {
    if (_grid.resolve(point).id != cellId) {
      throw ArgumentError('Fishing point grid does not match coordinates');
    }
  }
}
