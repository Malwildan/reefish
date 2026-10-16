import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/map/data/asset_marine_repository.dart';
import 'package:reefish_mobile/src/map/domain/geo_point.dart';
import 'package:reefish_mobile/src/map/domain/grid_cell.dart';
import 'package:reefish_mobile/src/map/domain/marine_cell_lookup.dart';
import 'package:reefish_mobile/src/map/domain/marine_data.dart';
import 'package:reefish_mobile/src/map/domain/marine_geometry.dart';
import 'package:reefish_mobile/src/map/domain/metric_grid_500.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses exact polygon intersections, including holes and boundaries', () {
    final cell = _cell(
      'selected',
      west: 0.5,
      south: 0.5,
      east: 1.5,
      north: 1.5,
    );
    final dataset = _dataset(
      coral: [
        _feature('contains', [_ring(-2, -2, 3, 3)]),
        _feature('hole-only', [_ring(-2, -2, 3, 3), _ring(-1, -1, 2, 2)]),
        _feature('touches', [_ring(1.5, 0.75, 2, 1.25)]),
        _feature('concave-miss', [
          [
            const GeoPoint(latitude: -1, longitude: -1),
            const GeoPoint(latitude: -1, longitude: 2),
            const GeoPoint(latitude: 0, longitude: 2),
            const GeoPoint(latitude: 0, longitude: 0),
            const GeoPoint(latitude: 2, longitude: 0),
            const GeoPoint(latitude: 2, longitude: -1),
            const GeoPoint(latitude: -1, longitude: -1),
          ],
        ]),
      ],
      mangrove: [
        _feature('mangrove', [_ring(0.8, 0.8, 1, 1)]),
      ],
    );

    final result = MarineCellLookup(dataset).featuresFor(cell);

    expect(result.coral.map((feature) => feature.id), ['contains', 'touches']);
    expect(result.mangrove.map((feature) => feature.id), ['mangrove']);
    expect(
      () => result.coral.add(_feature('extra', [])),
      throwsUnsupportedError,
    );
    expect(() => result.mangrove.clear(), throwsUnsupportedError);
  });

  test('bundled cell results match the existing exact geometry API', () async {
    final dataset = await AssetMarineRepository().loadBase();
    final cell = MetricGrid500().resolve(
      const GeoPoint(latitude: -8.4213856, longitude: 112.6144838),
    );

    final result = MarineCellLookup(dataset).featuresFor(cell);

    expect(
      result.coral.map((feature) => feature.id),
      intersectingMarineFeatures(
        dataset.coral,
        cell,
      ).map((feature) => feature.id),
    );
    expect(
      result.mangrove.map((feature) => feature.id),
      intersectingMarineFeatures(
        dataset.mangrove,
        cell,
      ).map((feature) => feature.id),
    );
  });

  test('LRU is bounded, refreshes hits, and recomputes evicted cells', () {
    final grid = MetricGrid500();
    final firstCell = grid.cellFromIndexes(18137, 1355);
    final secondCell = grid.cellFromIndexes(18137, 1356);
    final thirdCell = grid.cellFromIndexes(18137, 1357);
    final lookup = MarineCellLookup(_dataset(), capacity: 2);

    final first = lookup.featuresFor(firstCell);
    final second = lookup.featuresFor(secondCell);
    expect(lookup.featuresFor(firstCell), same(first));
    lookup.featuresFor(thirdCell); // Evicts second after refreshing first.
    expect(lookup.featuresFor(firstCell), same(first));
    expect(lookup.featuresFor(secondCell), isNot(same(second)));
  });

  test('each lookup is scoped to its own dataset snapshot', () {
    final cell = MetricGrid500().cellFromIndexes(18137, 1355);
    final cellRing = [...cell.polygon, cell.polygon.first];
    final firstDataset = _dataset(
      coral: [
        _feature('first', [cellRing]),
      ],
    );
    final secondDataset = _dataset();

    final first = MarineCellLookup(firstDataset).featuresFor(cell);
    final second = MarineCellLookup(secondDataset).featuresFor(cell);

    expect(first.coral.map((feature) => feature.id), ['first']);
    expect(second.coral, isEmpty);
  });

  test('rejects a non-positive cache capacity', () {
    expect(
      () => MarineCellLookup(_dataset(), capacity: 0),
      throwsArgumentError,
    );
  });
}

MarineDataset _dataset({
  List<MarineAreaFeature> coral = const [],
  List<MarineAreaFeature> mangrove = const [],
}) => MarineDataset(cells: const {}, coral: coral, mangrove: mangrove);

MarineAreaFeature _feature(String id, List<List<GeoPoint>> rings) =>
    MarineAreaFeature(id: id, polygons: [rings], properties: const {});

List<GeoPoint> _ring(double west, double south, double east, double north) => [
  GeoPoint(latitude: south, longitude: west),
  GeoPoint(latitude: south, longitude: east),
  GeoPoint(latitude: north, longitude: east),
  GeoPoint(latitude: north, longitude: west),
  GeoPoint(latitude: south, longitude: west),
];

GridCell _cell(
  String id, {
  required double west,
  required double south,
  required double east,
  required double north,
}) => GridCell(
  row: 0,
  col: 0,
  id: id,
  code: id,
  polygon: _ring(west, south, east, north).take(4).toList(growable: false),
  center: GeoPoint(latitude: (south + north) / 2, longitude: (west + east) / 2),
);
