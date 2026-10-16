import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/map/data/asset_marine_repository.dart';
import 'package:reefish_mobile/src/map/domain/geo_point.dart';
import 'package:reefish_mobile/src/map/domain/marine_cell_lookup.dart';
import 'package:reefish_mobile/src/map/domain/metric_grid_500.dart';
import 'package:reefish_mobile/src/map/presentation/marine_map_cubit.dart';

/// Real-file benchmark. Timings are diagnostic; file-read counts are stable.
///
/// Current-path run: `flutter test test/marine_selection_benchmark_test.dart --reporter=expanded`
/// Optional legacy comparison: `flutter test test/marine_selection_benchmark_test.dart --dart-define=SELECTION_BENCHMARK_PHASE=baseline`
/// The default phase is `after` so ordinary test runs exercise the one-entry
/// summary-selection path instead of reading all 24 entries per cell.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const phase = String.fromEnvironment(
    'SELECTION_BENCHMARK_PHASE',
    defaultValue: 'after',
  );

  test(
    'records the real bundled marine selection benchmark ($phase)',
    () async {
      expect(phase, anyOf('after', 'baseline'));
      final reads = <String, int>{};
      var bytesRead = 0;
      final repository = AssetMarineRepository(
        assetLoader: (path) async {
          final bytes = await File(path).readAsBytes();
          reads.update(path, (count) => count + 1, ifAbsent: () => 1);
          bytesRead += bytes.length;
          return utf8.decode(bytes);
        },
      );
      final cubit = MarineMapCubit(repository: repository);

      final initializeWatch = Stopwatch()..start();
      await cubit.initialize();
      initializeWatch.stop();
      final dataset = cubit.state.dataset!;

      final grid = MetricGrid500();
      final viewportWatch = Stopwatch()..start();
      var enumeratedCells = 0;
      for (var i = 0; i < 20; i++) {
        final viewport = grid.enumerateViewport(
          const GeoBounds(
            west: 112.65,
            east: 112.70,
            south: -8.45,
            north: -8.42,
          ),
          maxCells: 600,
        );
        expect(viewport.exceeded, isFalse);
        enumeratedCells = viewport.cells.length;
      }
      viewportWatch.stop();

      String nearestCell(double latitude, double longitude) =>
          dataset.cells.values.reduce((best, next) {
            final bestDistance =
                math.pow(best.point.latitude - latitude, 2) +
                math.pow(best.point.longitude - longitude, 2);
            final nextDistance =
                math.pow(next.point.latitude - latitude, 2) +
                math.pow(next.point.longitude - longitude, 2);
            return nextDistance < bestDistance ? next : best;
          }).cellId;
      final sampleCells = <String>[
        nearestCell(-8.433, 112.683),
        nearestCell(-8.438, 112.690),
        nearestCell(-8.443, 112.690),
        nearestCell(-8.433, 112.690),
        nearestCell(-8.438, 112.683),
      ];
      expect(sampleCells.toSet(), hasLength(5));
      expect(sampleCells.every(dataset.cells.containsKey), isTrue);

      // Exercise the same reusable geometry lookup used by the selected-cell
      // summary. Its warm-cache timings are not directly comparable to the
      // original free-function baseline.
      final geometryLookupPrepareWatch = Stopwatch()..start();
      final lookup = MarineCellLookup(dataset);
      geometryLookupPrepareWatch.stop();
      final geometryWatch = Stopwatch()..start();
      var coralHits = 0;
      var mangroveHits = 0;
      for (var i = 0; i < 20; i++) {
        for (final id in sampleCells.take(2)) {
          final sample = dataset.cells[id]!;
          final cell = grid.cellFromIndexes(
            sample.gridY + 17975,
            sample.gridX + 1274,
          );
          final features = lookup.featuresFor(cell);
          coralHits += features.coral.length;
          mangroveHits += features.mangrove.length;
        }
      }
      geometryWatch.stop();

      final selectionTimesMs = <int>[];
      var firstSelectionCsvReads = 0;
      var beforeRepeatCsvReads = 0;
      if (phase == 'baseline') {
        for (final id in sampleCells.take(2)) {
          final watch = Stopwatch()..start();
          await cubit.loadCellChlorophyll(id);
          watch.stop();
          selectionTimesMs.add(watch.elapsedMilliseconds);
          if (selectionTimesMs.length == 1) {
            firstSelectionCsvReads = _chlorophyllCsvReadCalls(reads);
          }
        }
        beforeRepeatCsvReads = _chlorophyllCsvReadCalls(reads);
        final repeatWatch = Stopwatch()..start();
        await cubit.loadCellChlorophyll(sampleCells.first);
        repeatWatch.stop();
        selectionTimesMs.add(repeatWatch.elapsedMilliseconds);
      } else {
        // initialize() returns after the base dataset and starts entry-1
        // preloading in the background. Requests share that in-flight load.
        for (var index = 0; index < sampleCells.length; index++) {
          final id = sampleCells[index];
          final watch = Stopwatch()..start();
          final result = await cubit.loadCellChlorophyllEntry(id, 1);
          watch.stop();
          selectionTimesMs.add(watch.elapsedMilliseconds);
          expect(result.keys, {1});
          expect(result[1], isNotNull);
          if (index == 0) {
            firstSelectionCsvReads = _chlorophyllCsvReadCalls(reads);
          }
        }
        beforeRepeatCsvReads = firstSelectionCsvReads;
        final repeatWatch = Stopwatch()..start();
        final repeated = await cubit.loadCellChlorophyllEntry(
          sampleCells.first,
          1,
        );
        repeatWatch.stop();
        selectionTimesMs.add(repeatWatch.elapsedMilliseconds);
        expect(repeated.keys, {1});
        expect(repeated[1], isNotNull);
      }
      await cubit.close();

      final csvReads = reads.entries
          .where((entry) => entry.key.endsWith('.csv'))
          .fold<int>(0, (total, entry) => total + entry.value);
      final chlorophyllCsvReadCalls = _chlorophyllCsvReadCalls(reads);
      final distinctChlorophyllCsvFiles = reads.entries
          .where(
            (entry) =>
                entry.key.contains('klorofil_a') && entry.key.endsWith('.csv'),
          )
          .length;
      final geometryVertices = [dataset.coral, dataset.mangrove]
          .expand((features) => features)
          .expand((feature) => feature.polygons)
          .expand((polygon) => polygon)
          .fold<int>(0, (total, ring) => total + ring.length);

      final benchmark = <String, Object>{
        'phase': phase,
        'environment': 'flutter test VM; native file reads; not device UI',
        'initialize_base_and_return_ms': initializeWatch.elapsedMilliseconds,
        'initialize_plus_first_selection_ms':
            initializeWatch.elapsedMilliseconds + selectionTimesMs.first,
        'base_cells': dataset.cells.length,
        'coral_features': dataset.coral.length,
        'mangrove_features': dataset.mangrove.length,
        'geometry_vertex_count': geometryVertices,
        'viewport_iterations': 20,
        'cells_per_viewport': enumeratedCells,
        'viewport_total_ms': viewportWatch.elapsedMilliseconds,
        'lookup_geometry_iterations_per_cell': 20,
        'lookup_geometry_cells': 2,
        'coral_intersection_hits': coralHits,
        'mangrove_intersection_hits': mangroveHits,
        'geometry_lookup_prepare_ms':
            geometryLookupPrepareWatch.elapsedMilliseconds,
        'lookup_geometry_total_ms': geometryWatch.elapsedMilliseconds,
        'selection_cells': sampleCells,
        'selection_elapsed_ms': selectionTimesMs,
        'chlorophyll_csv_read_calls': chlorophyllCsvReadCalls,
        'chlorophyll_csv_distinct_files_read': distinctChlorophyllCsvFiles,
        'chlorophyll_reads_after_first_selection': firstSelectionCsvReads,
        'chlorophyll_reads_before_repeat_selection': beforeRepeatCsvReads,
        'csv_read_count_total': csvReads,
        'bytes_read_total': bytesRead,
        'csv_asset_bytes': _csvAssetBytes(),
        'chlorophyll_entries_loaded_for_summary': phase == 'after' ? 1 : 24,
      };
      // Output is intentionally not written over baseline.json. Copy the JSON
      // from this line to qa/selection-performance/after.json after reviewing.
      // ignore: avoid_print
      print('SELECTION_BENCHMARK_JSON ${jsonEncode(benchmark)}');

      if (phase == 'after') {
        // The selected period should be read once, then reused by every cell.
        expect(chlorophyllCsvReadCalls, 1);
        expect(distinctChlorophyllCsvFiles, 1);
        expect(chlorophyllCsvReadCalls, beforeRepeatCsvReads);
      }
    },
  );
}

int _chlorophyllCsvReadCalls(Map<String, int> reads) => reads.entries
    .where(
      (entry) => entry.key.contains('klorofil_a') && entry.key.endsWith('.csv'),
    )
    .fold<int>(0, (total, entry) => total + entry.value);

int _csvAssetBytes() {
  final directory = Directory('assets/geodata');
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.toLowerCase().endsWith('.csv'))
      .fold<int>(0, (total, file) => total + file.lengthSync());
}
