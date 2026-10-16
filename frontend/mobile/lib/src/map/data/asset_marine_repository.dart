import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/geo_point.dart';
import '../domain/marine_data.dart';
import '../domain/marine_repository.dart';
import '../domain/metric_grid_500.dart';

typedef MarineAssetLoader = Future<String> Function(String assetPath);

/// Loads the bundled marine snapshot and individual chlorophyll entries.
///
/// Asset reads stay on the UI isolate; CSV and GeoJSON decoding runs through
/// [compute]. The entry index is source export order only and is never treated
/// as a timestamp or combined with another entry.
class AssetMarineRepository implements MarineRepository {
  AssetMarineRepository({
    MarineAssetLoader? assetLoader,
    this.expectedCellCount = 31354,
  }) : _assetLoader = assetLoader ?? _loadBundledAsset {
    if (expectedCellCount != null && expectedCellCount! < 0) {
      throw ArgumentError.value(expectedCellCount, 'expectedCellCount');
    }
  }

  static const fishAsset = 'assets/geodata/potensi_ikan.csv';
  static const temperatureAsset = 'assets/geodata/suhu_laut.csv';
  static const depthAsset = 'assets/geodata/kedalaman_laut.csv';
  static const coralAsset = 'assets/geodata/coral.geojson';
  static const mangroveAsset = 'assets/geodata/mangrove.geojson';
  static const chlorophyllDirectory = 'assets/geodata/klorofil_a';
  static const maxCachedChlorophyllEntries = 2;

  /// Set to null only for intentionally sparse fixtures or alternate snapshots.
  final int? expectedCellCount;
  final MarineAssetLoader _assetLoader;
  MarineDataset? _baseCache;
  Future<MarineDataset>? _baseFuture;
  final Map<int, Map<String, double>> _chlorophyllCache = {};
  final Map<int, Future<Map<String, double>>> _chlorophyllFutures = {};

  @override
  Future<MarineDataset> loadBase() {
    final cached = _baseCache;
    if (cached != null) return Future.value(cached);
    return _baseFuture ??= _loadBaseUncached();
  }

  @override
  Future<Map<String, double>> loadChlorophyll(int entry) {
    if (entry < 1 || entry > 24) throw RangeError.range(entry, 1, 24);
    final cached = _chlorophyllCache.remove(entry);
    if (cached != null) {
      _chlorophyllCache[entry] = cached;
      return Future.value(cached);
    }
    return _chlorophyllFutures[entry] ??= _loadChlorophyllUncached(entry);
  }

  Future<MarineDataset> _loadBaseUncached() async {
    try {
      final texts = await Future.wait([
        _assetLoader(fishAsset),
        _assetLoader(temperatureAsset),
        _assetLoader(depthAsset),
        _assetLoader(coralAsset),
        _assetLoader(mangroveAsset),
      ]);
      final dataset = await compute(_decodeBaseOnWorker, <String, String>{
        'fish': texts[0],
        'temperature': texts[1],
        'depth': texts[2],
        'coral': texts[3],
        'mangrove': texts[4],
        'expectedCellCount': expectedCellCount?.toString() ?? '',
      });
      _baseCache = dataset;
      return dataset;
    } catch (_) {
      _baseFuture = null;
      rethrow;
    }
  }

  Future<Map<String, double>> _loadChlorophyllUncached(int entry) async {
    try {
      final base = await loadBase();
      final name = entry.toString().padLeft(2, '0');
      final text = await _assetLoader('$chlorophyllDirectory/blok_$name.csv');
      final rows = await compute(_decodeCsvOnWorker, text);
      if (rows.length != base.cells.length) {
        throw FormatException(
          'Chlorophyll entry $entry has ${rows.length} cells; '
          'expected ${base.cells.length}',
        );
      }
      final values = <String, double>{};
      for (final row in rows.entries) {
        final localKey = row.key;
        final sample = row.value;
        final cellId = _cellIdFromLocalKey(localKey);
        final cell = base.cells[cellId];
        if (cell == null ||
            (cell.point.latitude - sample[0]).abs() > 1e-7 ||
            (cell.point.longitude - sample[1]).abs() > 1e-7) {
          throw FormatException(
            'Chlorophyll entry $entry is misaligned at $localKey',
          );
        }
        values[cellId] = sample[2];
      }
      if (values.length != base.cells.length) {
        throw FormatException('Chlorophyll entry $entry is missing grid keys');
      }
      final immutable = Map<String, double>.unmodifiable(values);
      _chlorophyllCache[entry] = immutable;
      while (_chlorophyllCache.length > maxCachedChlorophyllEntries) {
        _chlorophyllCache.remove(_chlorophyllCache.keys.first);
      }
      return immutable;
    } catch (_) {
      rethrow;
    } finally {
      _chlorophyllFutures.remove(entry);
    }
  }
}

Future<String> _loadBundledAsset(String path) => rootBundle.loadString(path);

/// Top-level worker entry points keep bundle access outside the isolate.
MarineDataset _decodeBaseOnWorker(Map<String, String> texts) {
  final fish = _parseMarineCsv(texts['fish']!);
  final temperature = _parseMarineCsv(texts['temperature']!);
  final depth = _parseMarineCsv(texts['depth']!);
  final expectedText = texts['expectedCellCount']!;
  final expectedCount = expectedText.isEmpty ? null : int.parse(expectedText);
  if (expectedCount != null && fish.length != expectedCount) {
    throw FormatException(
      'Base snapshot has ${fish.length} cells; expected $expectedCount',
    );
  }
  if (temperature.length != fish.length || depth.length != fish.length) {
    throw const FormatException('Base CSV files have different grid keys');
  }

  final cells = <String, MarineCell>{};
  for (final entry in fish.entries) {
    final t = temperature[entry.key];
    final d = depth[entry.key];
    if (t == null || d == null) {
      throw FormatException('Base CSV join is missing ${entry.key}');
    }
    final f = entry.value;
    if (!_coordinatesMatch(f, t) || !_coordinatesMatch(f, d)) {
      throw FormatException('Base CSV coordinates disagree at ${entry.key}');
    }
    final (gridX, gridY) = _decodeLocalKey(entry.key);
    final cellId = _canonicalCellId(gridX, gridY);
    cells[cellId] = MarineCell(
      gridX: gridX,
      gridY: gridY,
      point: GeoPoint(latitude: f[0], longitude: f[1]),
      fish: f[2],
      temperature: t[2],
      depth: d[2],
      cellId: cellId,
    );
  }

  return MarineDataset(
    cells: Map.unmodifiable(cells),
    coral: _parseGeoJson(texts['coral']!, 'coral'),
    mangrove: _parseGeoJson(texts['mangrove']!, 'mangrove'),
  );
}

Map<String, List<double>> _decodeCsvOnWorker(String text) =>
    _parseMarineCsv(text);

/// Parses the source's unquoted, comma-delimited numeric five-column format.
/// Quoted CSV fields are rejected because the shipped assets contain none.
Map<String, List<double>> _parseMarineCsv(String source) {
  final text = source.replaceFirst('\uFEFF', '');
  final lines = text.split(RegExp(r'\r?\n'));
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  if (lines.isEmpty) throw const FormatException('CSV is empty');

  final headers = lines.first.split(',').map((value) => value.trim()).toList();
  const requiredHeaders = {
    'grid_x',
    'grid_y',
    'latitude',
    'longitude',
    'value',
  };
  if (headers.length != 5 ||
      headers.toSet().length != 5 ||
      !headers.toSet().containsAll(requiredHeaders)) {
    throw FormatException('CSV must have five unique source headers: $headers');
  }
  final indexes = <String, int>{
    for (var i = 0; i < headers.length; i++) headers[i]: i,
  };
  final result = <String, List<double>>{};

  for (var lineIndex = 1; lineIndex < lines.length; lineIndex++) {
    final line = lines[lineIndex];
    if (line.trim().isEmpty) continue;
    if (line.contains('"')) {
      throw FormatException(
        'Quoted CSV fields are not supported at line ${lineIndex + 1}',
      );
    }
    final values = line.split(',');
    if (values.length != headers.length) {
      throw FormatException(
        'CSV column count is invalid at line ${lineIndex + 1}',
      );
    }
    double number(String field) {
      final value = double.tryParse(values[indexes[field]!].trim());
      if (value == null || !value.isFinite) {
        throw FormatException(
          '$field is not finite numeric data at line ${lineIndex + 1}',
        );
      }
      return value;
    }

    final rawX = number('grid_x');
    final rawY = number('grid_y');
    if (rawX != rawX.roundToDouble() ||
        rawY != rawY.roundToDouble() ||
        rawX < 1 ||
        rawX > 187 ||
        rawY < 1 ||
        rawY > 177) {
      throw FormatException(
        'Local grid index is invalid at line ${lineIndex + 1}',
      );
    }
    final latitude = number('latitude');
    final longitude = number('longitude');
    if (latitude < -9.15 ||
        latitude > -8.35 ||
        longitude < 112.25 ||
        longitude > 113.10) {
      throw FormatException(
        'Coordinate is outside the source AOI at line ${lineIndex + 1}',
      );
    }
    final value = number('value');
    final key = _localKey(rawX.toInt(), rawY.toInt());
    if (result.containsKey(key)) {
      throw FormatException('Duplicate local grid key $key');
    }
    result[key] = [latitude, longitude, value];
  }
  return result;
}

List<MarineAreaFeature> _parseGeoJson(String text, String sourceName) {
  final root = _asStringMap(jsonDecode(text), '$sourceName root');
  if (root['type'] != 'FeatureCollection' || root['features'] is! List) {
    throw FormatException('$sourceName must be a GeoJSON FeatureCollection');
  }
  final output = <MarineAreaFeature>[];
  final features = root['features'] as List<dynamic>;
  for (var featureIndex = 0; featureIndex < features.length; featureIndex++) {
    final feature = _asStringMap(features[featureIndex], '$sourceName feature');
    if (feature['type'] != 'Feature') {
      throw FormatException('$sourceName entry $featureIndex is not a Feature');
    }
    final geometry = _asStringMap(feature['geometry'], '$sourceName geometry');
    final properties = feature['properties'] == null
        ? <String, Object?>{}
        : Map<String, Object?>.from(
            _asStringMap(feature['properties'], '$sourceName properties'),
          );
    final rawCoordinates = geometry['coordinates'];
    final List<dynamic> polygons;
    switch (geometry['type']) {
      case 'Polygon':
        polygons = [rawCoordinates];
        break;
      case 'MultiPolygon':
        if (rawCoordinates is! List) {
          throw FormatException(
            '$sourceName MultiPolygon coordinates are invalid',
          );
        }
        polygons = rawCoordinates;
        break;
      default:
        throw FormatException('$sourceName geometry type is unsupported');
    }

    final decodedPolygons = <List<List<GeoPoint>>>[];
    for (final rawPolygon in polygons) {
      if (rawPolygon is! List || rawPolygon.isEmpty) {
        throw FormatException('$sourceName polygon has no rings');
      }
      final rings = <List<GeoPoint>>[];
      for (final rawRing in rawPolygon) {
        if (rawRing is! List || rawRing.length < 4) {
          throw FormatException('$sourceName ring has fewer than four points');
        }
        final ring = <GeoPoint>[];
        for (final rawPoint in rawRing) {
          if (rawPoint is! List ||
              rawPoint.length < 2 ||
              rawPoint[0] is! num ||
              rawPoint[1] is! num) {
            throw FormatException('$sourceName coordinate pair is invalid');
          }
          final longitude = (rawPoint[0] as num).toDouble();
          final latitude = (rawPoint[1] as num).toDouble();
          if (!longitude.isFinite ||
              !latitude.isFinite ||
              longitude < -180 ||
              longitude > 180 ||
              latitude < -90 ||
              latitude > 90) {
            throw FormatException('$sourceName coordinate is outside WGS84');
          }
          ring.add(GeoPoint(latitude: latitude, longitude: longitude));
        }
        if (ring.first != ring.last) {
          throw FormatException('$sourceName ring is not closed');
        }
        rings.add(List.unmodifiable(ring));
      }
      decodedPolygons.add(List.unmodifiable(rings));
    }
    final featureId = feature['id']?.toString() ?? '$sourceName-$featureIndex';
    output.add(
      MarineAreaFeature(
        id: featureId,
        polygons: List.unmodifiable(decodedPolygons),
        properties: Map.unmodifiable(properties),
      ),
    );
  }
  return List.unmodifiable(output);
}

Map<String, Object?> _asStringMap(Object? value, String description) {
  if (value is! Map) throw FormatException('$description must be an object');
  try {
    return Map<String, Object?>.from(value);
  } on TypeError {
    throw FormatException('$description must have string keys');
  }
}

bool _coordinatesMatch(List<double> first, List<double> second) =>
    (first[0] - second[0]).abs() <= 1e-7 &&
    (first[1] - second[1]).abs() <= 1e-7;

String _localKey(int gridX, int gridY) => '$gridX:$gridY';

(int, int) _decodeLocalKey(String key) {
  final parts = key.split(':');
  return (int.parse(parts[0]), int.parse(parts[1]));
}

String _cellIdFromLocalKey(String key) {
  final (gridX, gridY) = _decodeLocalKey(key);
  return _canonicalCellId(gridX, gridY);
}

String _canonicalCellId(int gridX, int gridY) {
  final row = gridY + 17975;
  final col = gridX + 1274;
  String signed(int value) => value < 0 ? 'n${-value}' : 'p$value';
  return '${MetricGrid500.namespace}:${MetricGrid500.version}:'
      'r${signed(row)}:c${signed(col)}';
}
