import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/geo_point.dart';
import '../domain/marine_data.dart';
import '../domain/marine_repository.dart';
import 'asset_marine_repository.dart';

typedef MarineRpcCall =
    Future<Object?> Function(String function, Map<String, dynamic> params);

/// Reads the authenticated marine layer RPCs and joins their source grid IDs
/// onto the bundled coordinate grid. The bundled data remains an explicit
/// unknown-date snapshot used only when the backend cannot be reached.
class SupabaseMarineRepository implements MarineRepository {
  SupabaseMarineRepository({
    required this.client,
    MarineRepository? snapshot,
    MarineRpcCall? rpc,
    bool Function()? hasSession,
  }) : _snapshot = snapshot ?? AssetMarineRepository(),
       _rpc =
           rpc ?? ((function, params) => client.rpc(function, params: params)),
       _hasSession = hasSession ?? (() => client.auth.currentSession != null);

  final SupabaseClient client;
  final MarineRepository _snapshot;
  final MarineRpcCall _rpc;
  final bool Function() _hasSession;
  List<String> _periods = const [];
  bool _backendAvailable = false;

  @override
  Future<MarineDataset> loadBase() async {
    if (!_hasSession()) {
      _backendAvailable = false;
      _periods = const [];
      return _snapshot.loadBase();
    }
    try {
      final responses = await Future.wait<Object?>([
        _rpc('api_layers', const {}),
        _rpc('api_habitat', const {}),
      ]);
      final layers = _asMap(responses[0], 'api_layers');
      final habitat = _asMap(responses[1], 'api_habitat');
      _periods = _parsePeriods(layers['periods']);
      _backendAvailable = true;
      final baseline = await _snapshot.loadBase();
      final rows = _parseLayerRows(layers['cells']);
      final cells = <String, MarineCell>{};
      for (final entry in baseline.cells.entries) {
        final base = entry.value;
        final values = rows[_sourceGridId(base.gridX, base.gridY)];
        cells[entry.key] = MarineCell(
          gridX: base.gridX,
          gridY: base.gridY,
          point: base.point,
          cellId: base.cellId,
          fish: values?['potensi_ikan'],
          temperature: values?['sst'],
          depth: values?['depth_m'],
        );
      }
      return MarineDataset(
        cells: Map.unmodifiable(cells),
        coral: _parseFeatureCollection(habitat['coral'], 'coral'),
        mangrove: _parseFeatureCollection(habitat['mangrove'], 'mangrove'),
        origin: MarineDataOrigin.authenticatedBackend,
        period: layers['period'] as String?,
        chlorophyllPeriods: _periods,
      );
    } catch (_) {
      // Keep the offline data visibly identified as an unknown-date snapshot.
      _backendAvailable = false;
      _periods = const [];
      return _snapshot.loadBase();
    }
  }

  @override
  Future<Map<String, double>> loadChlorophyll(int entry) async {
    if (entry < 1 || entry > 24) throw RangeError.range(entry, 1, 24);
    if (_hasSession() && _backendAvailable) {
      final index = entry - 1;
      if (index >= _periods.length) return const {};
      {
        try {
          final response = await _rpc('api_layers', {
            'p_period': _periods[index],
          });
          final layers = _asMap(response, 'api_layers');
          final rows = _parseLayerRows(layers['cells']);
          return Map.unmodifiable({
            for (final row in rows.entries)
              if (row.value['chlor_a'] != null)
                _canonicalIdFromSourceId(row.key): row.value['chlor_a']!,
          });
        } catch (_) {
          // Surface the outage instead of relabeling the offline snapshot as
          // the backend's selected period.
          rethrow;
        }
      }
    }
    return _snapshot.loadChlorophyll(entry);
  }
}

Map<String, Object?> _asMap(Object? value, String name) {
  if (value is! Map) throw FormatException('$name response must be an object');
  try {
    return Map<String, Object?>.from(value);
  } on TypeError {
    throw FormatException('$name response keys must be strings');
  }
}

List<String> _parsePeriods(Object? value) {
  if (value is! List ||
      value.any(
        (period) =>
            period is! String || !RegExp(r'^\d{4}-\d{2}$').hasMatch(period),
      )) {
    throw const FormatException('periods must contain YYYY-MM strings');
  }
  return List.unmodifiable(value.cast<String>());
}

Map<String, Map<String, double?>> _parseLayerRows(Object? value) {
  if (value is! List) throw const FormatException('cells must be a list');
  final rows = <String, Map<String, double?>>{};
  for (final row in value) {
    if (row is! List || row.length < 7 || row[0] is! String) {
      throw const FormatException('api_layers cell tuple is invalid');
    }
    final sourceId = row[0] as String;
    if (!RegExp(r'^X\d{3}_Y\d{3}$').hasMatch(sourceId)) {
      throw FormatException('api_layers returned invalid grid ID: $sourceId');
    }
    double? number(Object? value) {
      if (value == null) return null;
      if (value is! num || !value.isFinite) {
        throw const FormatException('api_layers value must be numeric or null');
      }
      return value.toDouble();
    }

    if (rows.containsKey(sourceId)) {
      throw FormatException('api_layers returned duplicate grid ID: $sourceId');
    }
    rows[sourceId] = {
      'sst': number(row[3]),
      'chlor_a': number(row[4]),
      'depth_m': number(row[5]),
      'potensi_ikan': number(row[6]),
    };
  }
  return rows;
}

String _sourceGridId(int x, int y) =>
    'X${x.toString().padLeft(3, '0')}_Y${y.toString().padLeft(3, '0')}';

String _canonicalIdFromSourceId(String sourceId) {
  final match = RegExp(r'^X(\d{3})_Y(\d{3})$').firstMatch(sourceId)!;
  final x = int.parse(match.group(1)!);
  final y = int.parse(match.group(2)!);
  return 'tp-id-utm49s-500m:v2:rp${y + 17975}:cp${x + 1274}';
}

List<MarineAreaFeature> _parseFeatureCollection(Object? value, String name) {
  final collection = _asMap(value, '$name FeatureCollection');
  if (collection['type'] != 'FeatureCollection' ||
      collection['features'] is! List) {
    throw FormatException('$name must be a GeoJSON FeatureCollection');
  }
  final features = <MarineAreaFeature>[];
  for (final item in collection['features'] as List) {
    final feature = _asMap(item, '$name feature');
    final geometry = _asMap(feature['geometry'], '$name geometry');
    final properties = feature['properties'] == null
        ? <String, Object?>{}
        : _asMap(feature['properties'], '$name properties');
    final raw = geometry['coordinates'];
    final List polygons;
    switch (geometry['type']) {
      case 'Polygon':
        if (raw is! List) throw FormatException('$name polygon is invalid');
        polygons = [raw];
        break;
      case 'MultiPolygon':
        if (raw is! List) {
          throw FormatException('$name multipolygon is invalid');
        }
        polygons = raw;
        break;
      default:
        throw FormatException('$name geometry type is unsupported');
    }
    final decoded = <List<List<GeoPoint>>>[];
    for (final polygon in polygons) {
      if (polygon is! List || polygon.isEmpty) {
        throw FormatException('$name polygon has no rings');
      }
      final rings = <List<GeoPoint>>[];
      for (final ring in polygon) {
        if (ring is! List || ring.length < 4) {
          throw FormatException('$name ring is invalid');
        }
        final points = <GeoPoint>[];
        for (final point in ring) {
          if (point is! List ||
              point.length < 2 ||
              point[0] is! num ||
              point[1] is! num) {
            throw FormatException('$name coordinate must be [lon, lat]');
          }
          final longitude = (point[0] as num).toDouble();
          final latitude = (point[1] as num).toDouble();
          if (!longitude.isFinite ||
              !latitude.isFinite ||
              longitude < -180 ||
              longitude > 180 ||
              latitude < -90 ||
              latitude > 90) {
            throw FormatException('$name coordinate is outside WGS84');
          }
          points.add(GeoPoint(latitude: latitude, longitude: longitude));
        }
        if (points.first != points.last) {
          throw FormatException('$name ring is not closed');
        }
        rings.add(List.unmodifiable(points));
      }
      decoded.add(List.unmodifiable(rings));
    }
    features.add(
      MarineAreaFeature(
        id: feature['id']?.toString() ?? '$name-${features.length}',
        polygons: List.unmodifiable(decoded),
        properties: Map.unmodifiable(properties),
      ),
    );
  }
  return List.unmodifiable(features);
}
