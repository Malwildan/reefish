import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/journey/presentation/journey_full_map_screen.dart';
import 'package:reefish_mobile/src/map/domain/geo_point.dart';
import 'package:reefish_mobile/src/map/domain/grid_cell.dart';
import 'package:reefish_mobile/src/map/domain/grid_policy.dart';
import 'package:reefish_mobile/src/map/domain/grid_policy_repository.dart';
import 'package:reefish_mobile/src/map/domain/marine_data.dart';
import 'package:reefish_mobile/src/map/domain/marine_repository.dart';
import 'package:reefish_mobile/src/map/domain/metric_grid_500.dart';
import 'package:reefish_mobile/src/map/presentation/widgets/marine_cell_summary_popup.dart';

void main() {
  final grid = MetricGrid500();
  final firstCell = grid.resolve(
    const GeoPoint(latitude: -8.447, longitude: 112.683),
  );
  final secondCell = grid.resolve(
    const GeoPoint(latitude: -8.447, longitude: 112.690),
  );

  testWidgets(
    'tap shows canonical cell data, changes cell, closes and opens details',
    (tester) async {
      final repository = _MarineRepository(
        MarineDataset(
          cells: {
            firstCell.id: _marineCell(firstCell, fish: 67),
            secondCell.id: _marineCell(secondCell, fish: 23),
          },
          coral: const [],
          mangrove: const [],
        ),
      );
      await _showMap(tester, repository: repository);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tap-first-cell')));
      await tester.pumpAndSettle();
      expect(
        find.text('Petak R${firstCell.row} · C${firstCell.col}'),
        findsOneWidget,
      );
      expect(find.text('67.0'), findsOneWidget);
      expect(find.text('Tanpa lock'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tap-second-cell')));
      await tester.pumpAndSettle();
      expect(
        find.text('Petak R${secondCell.row} · C${secondCell.col}'),
        findsOneWidget,
      );
      expect(find.text('23.0'), findsOneWidget);
      expect(find.text('67.0'), findsNothing);

      await tester.tap(find.byKey(const Key('marine-summary-close')));
      await tester.pumpAndSettle();
      expect(find.byType(MarineCellSummaryPopup), findsNothing);

      await tester.tap(find.byKey(const Key('tap-first-cell')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('marine-summary-details')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('marine-cell-details-scroll')),
        findsOneWidget,
      );
      expect(repository.loadBaseCount, 1);
    },
  );

  testWidgets(
    'late base load follows the latest tap and missing policy stays unknown',
    (tester) async {
      final pending = Completer<MarineDataset>();
      final repository = _MarineRepository.pending(pending.future);
      await _showMap(
        tester,
        repository: repository,
        policies: _FailingPolicies(),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('tap-first-cell')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tap-second-cell')));
      await tester.pump();
      pending.complete(
        MarineDataset(
          cells: {secondCell.id: _marineCell(secondCell, fish: null)},
          coral: const [],
          mangrove: const [],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Petak R${secondCell.row} · C${secondCell.col}'),
        findsOneWidget,
      );
      expect(find.text('23.0'), findsNothing);
      expect(find.text('—'), findsWidgets);
      expect(find.text('Belum diverifikasi'), findsOneWidget);
    },
  );
}

Future<void> _showMap(
  WidgetTester tester, {
  required _MarineRepository repository,
  GridPolicyRepository? policies,
}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: JourneyFullMapScreen(
        marineRepository: repository,
        gridPolicyRepository: policies ?? _FreshPolicies(),
        mapBuilder: (onGridTap) => Align(
          alignment: Alignment.center,
          child: Padding(
            // Keep the synthetic map taps in an exposed area below the popup.
            padding: const EdgeInsets.only(top: 340),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  key: const Key('tap-first-cell'),
                  onPressed: () => onGridTap(
                    const GeoPoint(latitude: -8.447, longitude: 112.683),
                  ),
                  child: const Text('First'),
                ),
                TextButton(
                  key: const Key('tap-second-cell'),
                  onPressed: () => onGridTap(
                    const GeoPoint(latitude: -8.447, longitude: 112.690),
                  ),
                  child: const Text('Second'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

MarineCell _marineCell(GridCell cell, {required double? fish}) => MarineCell(
  gridX: 1,
  gridY: 1,
  point: cell.center,
  fish: fish,
  temperature: null,
  depth: null,
  cellId: cell.id,
);

class _MarineRepository implements MarineRepository {
  _MarineRepository(this.dataset) : _baseFuture = null;

  _MarineRepository.pending(Future<MarineDataset> future)
    : dataset = null,
      _baseFuture = future;

  final MarineDataset? dataset;
  final Future<MarineDataset>? _baseFuture;
  int loadBaseCount = 0;

  @override
  Future<MarineDataset> loadBase() {
    loadBaseCount++;
    return _baseFuture ?? Future.value(dataset!);
  }

  @override
  Future<Map<String, double>> loadChlorophyll(int entry) async => const {};
}

class _FreshPolicies implements GridPolicyRepository {
  @override
  Future<GridPolicySnapshot> fetchSnapshot() async {
    final now = DateTime.now();
    return GridPolicySnapshot(
      version: 'test',
      fetchedAt: now,
      expiresAt: now.add(const Duration(minutes: 5)),
      locks: const {},
    );
  }
}

class _FailingPolicies implements GridPolicyRepository {
  @override
  Future<GridPolicySnapshot> fetchSnapshot() async =>
      throw StateError('policy unavailable');
}
