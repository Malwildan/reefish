import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/map/data/asset_marine_repository.dart';
import 'package:reefish_mobile/src/map/domain/geo_point.dart';
import 'package:reefish_mobile/src/map/domain/grid_cell.dart';
import 'package:reefish_mobile/src/map/domain/marine_data.dart';
import 'package:reefish_mobile/src/map/domain/marine_geometry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssetMarineRepository', () {
    test('loads the full bundled base snapshot', () async {
      final repository = AssetMarineRepository();
      final data = await repository.loadBase();
      expect(data.cells, hasLength(31354));
      expect(data.cells['tp-id-utm49s-500m:v2:rp18137:cp1355'], isNotNull);
      expect(data.coral, isNotEmpty);
      expect(data.mangrove, isNotEmpty);
      expect(await repository.loadChlorophyll(1), hasLength(31354));
    });

    test(
      'joins source rows onto canonical cells and preserves area metadata',
      () async {
        final assets = _fixtureAssets();
        final repository = AssetMarineRepository(
          expectedCellCount: 2,
          assetLoader: (path) async => assets[path]!,
        );

        final data = await repository.loadBase();

        expect(data.cells, hasLength(2));
        const id = 'tp-id-utm49s-500m:v2:rp18137:cp1355';
        final cell = data.cells[id]!;
        expect(cell.cellId, id);
        expect((cell.gridX, cell.gridY), (81, 162));
        expect(cell.point.latitude, -8.4213856);
        expect(cell.point.longitude, 112.6144838);
        expect(
          (cell.fish, cell.temperature, cell.depth),
          (16.35, 29.136, 5000.0),
        );
        expect(data.coral, hasLength(2));
        expect(data.coral.map((feature) => feature.properties['value']), [
          0,
          1,
        ]);
        expect(data.coral.first.polygons.single, hasLength(2));
        expect(data.mangrove.single.properties['year'], 2023);
      },
    );

    test(
      'shares an in-flight base load and caches the completed snapshot',
      () async {
        final assets = _fixtureAssets();
        final started = Completer<void>();
        var reads = 0;
        final repository = AssetMarineRepository(
          expectedCellCount: 2,
          assetLoader: (path) async {
            reads++;
            if (!started.isCompleted) started.complete();
            await Future<void>.delayed(const Duration(milliseconds: 2));
            return assets[path]!;
          },
        );

        final first = repository.loadBase();
        final second = repository.loadBase();
        await started.future;
        final pair = await Future.wait([first, second]);
        expect(identical(pair[0], pair[1]), isTrue);
        expect(reads, 5);
        expect(identical(await repository.loadBase(), pair[0]), isTrue);
        expect(reads, 5);
      },
    );

    test(
      'chlorophyll stays entry-specific, shares concurrent reads, and LRU-caches two',
      () async {
        final assets = _fixtureAssets();
        final counts = <int, int>{};
        final repository = AssetMarineRepository(
          expectedCellCount: 2,
          assetLoader: (path) async {
            final match = RegExp(r'blok_(\d+)\.csv$').firstMatch(path);
            if (match == null) return assets[path]!;
            final entry = int.parse(match.group(1)!);
            counts.update(entry, (count) => count + 1, ifAbsent: () => 1);
            await Future<void>.delayed(const Duration(milliseconds: 2));
            return _csv(entry.toDouble(), entry.toDouble() + 0.5);
          },
        );
        final base = await repository.loadBase();
        final firstCalls = await Future.wait([
          repository.loadChlorophyll(1),
          repository.loadChlorophyll(1),
        ]);
        final id = base.cells.keys.first;
        expect(firstCalls[0][id], 1.0);
        expect(firstCalls[1][id], 1.0);
        expect(counts[1], 1);
        await repository.loadChlorophyll(2);
        await repository.loadChlorophyll(1); // Refresh entry 1's LRU position.
        await repository.loadChlorophyll(3); // Evicts entry 2.
        await repository.loadChlorophyll(1);
        await repository.loadChlorophyll(2);
        expect(counts, {1: 1, 2: 2, 3: 1});
        expect(await repository.loadChlorophyll(24), containsPair(id, 24.0));
        expect(() => repository.loadChlorophyll(0), throwsRangeError);
      },
    );

    test(
      'failed base load can be retried without leaving a poisoned future',
      () async {
        final assets = _fixtureAssets();
        var fail = true;
        var fishReads = 0;
        final repository = AssetMarineRepository(
          expectedCellCount: 2,
          assetLoader: (path) async {
            if (path == AssetMarineRepository.fishAsset) {
              fishReads++;
              if (fail) throw StateError('temporary asset failure');
            }
            return assets[path]!;
          },
        );

        await expectLater(repository.loadBase(), throwsStateError);
        fail = false;
        expect((await repository.loadBase()).cells, hasLength(2));
        expect(fishReads, 2);
      },
    );

    test(
      'rejects malformed numeric data and any coordinate/key join mismatch',
      () async {
        final malformed = _fixtureAssets()
          ..[AssetMarineRepository.fishAsset] =
              'grid_x,grid_y,latitude,longitude,value\n81,162,NaN,112.6,2';
        final malformedRepository = AssetMarineRepository(
          expectedCellCount: 1,
          assetLoader: (path) async => malformed[path]!,
        );
        await expectLater(
          malformedRepository.loadBase(),
          throwsFormatException,
        );

        final mismatched = _fixtureAssets()
          ..[AssetMarineRepository.temperatureAsset] = _csv(
            28.0,
            30.0,
            keys: const [(81, 162), (83, 162)],
          );
        final mismatchedRepository = AssetMarineRepository(
          expectedCellCount: 2,
          assetLoader: (path) async => mismatched[path]!,
        );
        await expectLater(
          mismatchedRepository.loadBase(),
          throwsFormatException,
        );
      },
    );

    test(
      'preserves sparse valid keys without filling absent grid cells',
      () async {
        final assets = _fixtureAssets()
          ..[AssetMarineRepository.fishAsset] = _csv(
            1,
            2,
            keys: const [(81, 162)],
          )
          ..[AssetMarineRepository.temperatureAsset] = _csv(
            3,
            4,
            keys: const [(81, 162)],
          )
          ..[AssetMarineRepository.depthAsset] = _csv(
            5,
            6,
            keys: const [(81, 162)],
          );
        final repository = AssetMarineRepository(
          expectedCellCount: null,
          assetLoader: (path) async => assets[path]!,
        );
        expect((await repository.loadBase()).cells, hasLength(1));
      },
    );
  });

  group('intersectingMarineFeatures', () {
    final cell = _gridCell(0, 0, 1, 1);

    test(
      'finds containment and boundary contact but excludes bbox-only hole hits',
      () {
        final containsCell = _feature('contains', [
          _ring(-1, -1, 2, 2),
          _ring(0.1, 0.1, 0.9, 0.9),
        ]);
        final holeOnly = _feature('hole-only', [
          _ring(-1, -1, 2, 2),
          _ring(-0.5, -0.5, 1.5, 1.5),
        ]);
        final touches = _feature('touches', [_ring(1, 0.25, 1.5, 0.75)]);
        final disjoint = _feature('disjoint', [_ring(2, 2, 3, 3)]);

        expect(
          intersectingMarineFeatures([
            containsCell,
            holeOnly,
            touches,
            disjoint,
          ], cell).map((feature) => feature.id),
          ['contains', 'touches'],
        );
      },
    );

    test(
      'respects concave footprint instead of accepting bounding-box overlap',
      () {
        // This U shape has a bounding box around the cell, but its filled arms
        // miss the central cell entirely.
        const uShape = MarineAreaFeature(
          id: 'u',
          polygons: [
            [
              [
                GeoPoint(latitude: -1, longitude: -1),
                GeoPoint(latitude: -1, longitude: 2),
                GeoPoint(latitude: 0, longitude: 2),
                GeoPoint(latitude: 0, longitude: 0),
                GeoPoint(latitude: 2, longitude: 0),
                GeoPoint(latitude: 2, longitude: -1),
                GeoPoint(latitude: -1, longitude: -1),
              ],
            ],
          ],
          properties: {},
        );
        final innerCell = _gridCell(0.5, 0.5, 1, 1);
        expect(intersectingMarineFeatures([uShape], innerCell), isEmpty);
      },
    );
  });
}

Map<String, String> _fixtureAssets() => {
  AssetMarineRepository.fishAsset: _csv(16.35, 18.43),
  AssetMarineRepository.temperatureAsset: _csv(29.136, 29.081),
  AssetMarineRepository.depthAsset: _csv(5000, 4000),
  AssetMarineRepository.coralAsset: _geoJson([
    _featureJson('coral-0', 0, holes: true),
    _featureJson('coral-1', 1),
  ]),
  AssetMarineRepository.mangroveAsset: _geoJson([
    _featureJson('mangrove-0', null, year: 2023),
  ]),
};

String _csv(
  double firstValue,
  double secondValue, {
  List<(int, int)> keys = const [(81, 162), (82, 162)],
}) {
  const first = '-8.4213856,112.6144838';
  const second = '-8.4213856,112.6144838';
  final coords = [first, second];
  final values = [firstValue, secondValue];
  final rows = <String>[
    'grid_x,grid_y,latitude,longitude,value',
    for (var index = 0; index < keys.length; index++)
      '${keys[index].$1},${keys[index].$2},${coords[index]},${values[index]}',
  ];
  return rows.join('\n');
}

String _geoJson(List<Map<String, Object?>> features) =>
    '{"type":"FeatureCollection","features":${_jsonEncode(features)}}';

String _jsonEncode(Object? value) {
  if (value is Map) {
    return '{${value.entries.map((entry) => '"${entry.key}":${_jsonEncode(entry.value)}').join(',')}}';
  }
  if (value is List) return '[${value.map(_jsonEncode).join(',')}]';
  if (value is String) return '"$value"';
  return value.toString();
}

Map<String, Object?> _featureJson(
  String id,
  int? value, {
  int? year,
  bool holes = false,
}) => {
  'type': 'Feature',
  'id': id,
  'properties': {
    if (value != null) 'value': value,
    if (year != null) 'year': year,
  },
  'geometry': {
    'type': 'Polygon',
    'coordinates': [
      [
        [112.60, -8.43],
        [112.62, -8.43],
        [112.62, -8.41],
        [112.60, -8.41],
        [112.60, -8.43],
      ],
      if (holes)
        [
          [112.605, -8.425],
          [112.615, -8.425],
          [112.615, -8.415],
          [112.605, -8.415],
          [112.605, -8.425],
        ],
    ],
  },
};

MarineAreaFeature _feature(String id, List<List<GeoPoint>> rings) =>
    MarineAreaFeature(id: id, polygons: [rings], properties: const {});

List<GeoPoint> _ring(double west, double south, double east, double north) => [
  GeoPoint(latitude: south, longitude: west),
  GeoPoint(latitude: south, longitude: east),
  GeoPoint(latitude: north, longitude: east),
  GeoPoint(latitude: north, longitude: west),
  GeoPoint(latitude: south, longitude: west),
];

GridCell _gridCell(double west, double south, double east, double north) =>
    GridCell(
      row: 0,
      col: 0,
      id: 'cell',
      code: 'cell',
      polygon: _ring(west, south, east, north).take(4).toList(),
      center: GeoPoint(
        latitude: (south + north) / 2,
        longitude: (west + east) / 2,
      ),
    );
