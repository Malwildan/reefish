import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/map/data/asset_marine_repository.dart';
import 'package:reefish_mobile/src/map/domain/geo_point.dart';
import 'package:reefish_mobile/src/map/domain/marine_geometry.dart';
import 'package:reefish_mobile/src/map/domain/metric_grid_500.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled snapshot joins real values and geometry to canonical cells', () async {
    final repository = AssetMarineRepository();
    final data = await repository.loadBase();
    expect(data.cells, hasLength(31354));
    expect(data.coral, hasLength(140));
    expect(data.mangrove, hasLength(3));

    final grid = MetricGrid500();
    final cell = grid.resolve(const GeoPoint(
      latitude: -8.4213856,
      longitude: 112.6144838,
    ));
    expect(cell.id, 'tp-id-utm49s-500m:v2:rp18137:cp1355');
    final sample = data.cells[cell.id]!;
    expect((sample.gridX, sample.gridY), (81, 162));
    expect(sample.fish, 53);
    expect(sample.temperature, 29.047);
    expect(sample.depth, 29.3);
    expect(data.cells.containsKey(grid.cellFromIndexes(17976, 1275).id), isFalse);

    final coral = intersectingMarineFeatures(data.coral, cell);
    expect(coral.map((feature) => feature.properties['value']).toSet(), {0, 1});
    expect(intersectingMarineFeatures(data.mangrove, cell), isEmpty);
    final first = await repository.loadChlorophyll(1);
    final last = await repository.loadChlorophyll(24);
    expect(first, hasLength(31354));
    expect(last, hasLength(31354));
    expect(first[cell.id], 1.3917);
    expect(last[cell.id], 1.686);
  });
}
