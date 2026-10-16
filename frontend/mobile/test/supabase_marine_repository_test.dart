import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/map/data/supabase_marine_repository.dart';
import 'package:reefish_mobile/src/map/domain/geo_point.dart';
import 'package:reefish_mobile/src/map/domain/marine_data.dart';
import 'package:reefish_mobile/src/map/domain/marine_repository.dart';
import 'package:reefish_mobile/src/map/presentation/marine_map_cubit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;

  setUp(() => client = SupabaseClient('https://example.supabase.co', 'test'));
  tearDown(() => client.dispose());

  test(
    'uses the bundled snapshot when there is no authenticated session',
    () async {
      var rpcCalls = 0;
      final repository = SupabaseMarineRepository(
        client: client,
        snapshot: _Snapshot(),
        hasSession: () => false,
        rpc: (_, _) async {
          rpcCalls++;
          throw StateError('must not call RPC');
        },
      );

      final dataset = await repository.loadBase();

      expect(dataset.origin, MarineDataOrigin.bundledSnapshot);
      expect(dataset.period, isNull);
      expect(rpcCalls, 0);
    },
  );

  test(
    'maps backend tuples, nulls, period order and GeoJSON [lon, lat]',
    () async {
      final calls = <(String, Map<String, dynamic>)>[];
      final repository = SupabaseMarineRepository(
        client: client,
        snapshot: _Snapshot(),
        hasSession: () => true,
        rpc: (function, params) async {
          calls.add((function, params));
          if (function == 'api_habitat') return _habitat;
          final period = params['p_period'];
          return {
            'period': period ?? '2025-12',
            'periods': ['2024-01', '2025-12'],
            'cells': [
              ['X081_Y162', 1, 2.5, null, 0.75, 40, null, false],
            ],
          };
        },
      );

      final dataset = await repository.loadBase();
      final cell = dataset.cells['tp-id-utm49s-500m:v2:rp18137:cp1355']!;
      expect(dataset.origin, MarineDataOrigin.authenticatedBackend);
      expect(dataset.period, '2025-12');
      expect((cell.fish, cell.temperature, cell.depth), (null, null, 40));
      expect(
        dataset.coral.single.polygons.single.single.first,
        const GeoPoint(latitude: -9.1, longitude: 112.9),
      );
      expect(dataset.coral.single.properties['value'], 1);

      final values = await repository.loadChlorophyll(1);
      expect(calls.last.$1, 'api_layers');
      expect(calls.last.$2['p_period'], '2024-01');
      expect(values, {'tp-id-utm49s-500m:v2:rp18137:cp1355': 0.75});
    },
  );

  test(
    'uses the snapshot if either remote base layer is unavailable',
    () async {
      final repository = SupabaseMarineRepository(
        client: client,
        snapshot: _Snapshot(),
        hasSession: () => true,
        rpc: (function, _) async {
          if (function == 'api_habitat') throw StateError('network down');
          return {'period': null, 'periods': [], 'cells': []};
        },
      );

      final dataset = await repository.loadBase();
      expect(dataset.origin, MarineDataOrigin.bundledSnapshot);
      expect(dataset.cells.values.single.fish, 16.35);
    },
  );

  test(
    'map selection follows the single backend period, not 24 placeholders',
    () async {
      final repository = SupabaseMarineRepository(
        client: client,
        snapshot: _Snapshot(),
        hasSession: () => true,
        rpc: (function, _) async => function == 'api_habitat'
            ? _emptyHabitat
            : {
                'period': '2025-12',
                'periods': ['2025-12'],
                'cells': [],
              },
      );
      final cubit = MarineMapCubit(repository: repository);
      await cubit.initialize();

      expect(cubit.state.chlorophyllEntryCount, 1);
      cubit.setChlorophyllEntry(24);
      expect(cubit.state.chlorophyllEntry, 1);
      await cubit.close();
    },
  );
}

class _Snapshot implements MarineRepository {
  static const _cellId = 'tp-id-utm49s-500m:v2:rp18137:cp1355';

  @override
  Future<MarineDataset> loadBase() async => const MarineDataset(
    cells: {
      _cellId: MarineCell(
        gridX: 81,
        gridY: 162,
        point: GeoPoint(latitude: -8.4213856, longitude: 112.6144838),
        fish: 16.35,
        temperature: 29.136,
        depth: 5000,
        cellId: _cellId,
      ),
    },
    coral: [],
    mangrove: [],
  );

  @override
  Future<Map<String, double>> loadChlorophyll(int entry) async => {
    _cellId: entry.toDouble(),
  };
}

final _habitat = {
  'coral': {
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'id': 10,
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            [
              [112.9, -9.1],
              [113.0, -9.1],
              [113.0, -9.0],
              [112.9, -9.1],
            ],
          ],
        },
        'properties': {'value': 1},
      },
    ],
  },
  'mangrove': {'type': 'FeatureCollection', 'features': []},
};

const _emptyHabitat = {
  'coral': {'type': 'FeatureCollection', 'features': []},
  'mangrove': {'type': 'FeatureCollection', 'features': []},
};
