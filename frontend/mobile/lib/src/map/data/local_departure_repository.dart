import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/departure_repository.dart';
import '../domain/geo_point.dart';
import '../domain/metric_grid_500.dart';

class LocalDepartureRepository implements DepartureRepository {
  LocalDepartureRepository({
    required SharedPreferences preferences,
    String? ownerId,
    String? storageKey,
    MetricGrid500? grid,
  }) : _preferences = preferences,
       _grid = grid ?? MetricGrid500(),
       _storageKey =
           storageKey ??
           (ownerId == null
               ? 'reefish.departure-point.v1.preview'
               : 'reefish.departure-point.v1.$ownerId') {
    if (ownerId != null && ownerId.trim().isEmpty) {
      throw ArgumentError.value(ownerId, 'ownerId');
    }
    if (_storageKey.trim().isEmpty) {
      throw ArgumentError.value(storageKey, 'storageKey');
    }
  }

  final SharedPreferences _preferences;
  final MetricGrid500 _grid;
  final String _storageKey;

  @override
  Future<void> save(DeparturePoint departure) async {
    _validate(departure);
    final encoded = jsonEncode({
      'latitude': departure.point.latitude,
      'longitude': departure.point.longitude,
      'cell_id': departure.cellId,
      'saved_at': departure.savedAt.toUtc().toIso8601String(),
    });
    if (!await _preferences.setString(_storageKey, encoded)) {
      throw StateError('Could not save departure point');
    }
  }

  @override
  Future<DeparturePoint?> read() async {
    final raw = _preferences.getString(_storageKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        throw const FormatException('Stored departure must be an object');
      }
      final latitude = json['latitude'];
      final longitude = json['longitude'];
      final cellId = json['cell_id'];
      final savedAt = json['saved_at'];
      if (latitude is! num ||
          longitude is! num ||
          cellId is! String ||
          savedAt is! String) {
        throw const FormatException('Stored departure fields are invalid');
      }
      _validateStoredGridMetadata(json);
      final point = GeoPoint(
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
      );
      final departure = DeparturePoint(
        point: point,
        cellId: cellId,
        savedAt: DateTime.parse(savedAt),
      );
      _validate(departure);
      return departure;
    } on FormatException catch (error) {
      throw FormatException(
        'Stored departure is invalid; it was preserved: $error',
      );
    } on ArgumentError catch (error) {
      throw FormatException(
        'Stored departure is invalid; it was preserved: $error',
      );
    }
  }

  void _validate(DeparturePoint departure) {
    if (!_grid.initialBounds.contains(departure.point)) {
      throw ArgumentError(
        'Departure point is outside the configured map bounds',
      );
    }
    if (_grid.resolve(departure.point).id != departure.cellId) {
      throw ArgumentError('Departure cell ID does not match its coordinates');
    }
  }

  void _validateStoredGridMetadata(Map<String, dynamic> json) {
    final gridId = json['grid_id'];
    final rawDefinition = json['grid_definition'];
    if (gridId == null && rawDefinition == null) return;
    if (gridId != '${MetricGrid500.namespace}:${MetricGrid500.version}' ||
        rawDefinition is! Map ||
        rawDefinition['id'] != gridId ||
        rawDefinition['cell_size_m'] != MetricGrid500.resolutionMeters ||
        rawDefinition['srid'] != 32749 ||
        rawDefinition['origin_x_m'] != 0 ||
        rawDefinition['origin_y_m'] != 0) {
      throw const FormatException(
        'Stored departure uses an unsupported grid definition',
      );
    }
    final bounds = rawDefinition['bounds'];
    if (bounds is! List ||
        bounds.length != 4 ||
        bounds[0] != _grid.initialBounds.west ||
        bounds[1] != _grid.initialBounds.south ||
        bounds[2] != _grid.initialBounds.east ||
        bounds[3] != _grid.initialBounds.north) {
      throw const FormatException(
        'Stored departure grid bounds do not match this map',
      );
    }
  }
}
