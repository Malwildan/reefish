import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/map/domain/geo_point.dart';
import 'package:reefish_mobile/src/map/domain/marine_data.dart';
import 'package:reefish_mobile/src/map/domain/marine_repository.dart';
import 'package:reefish_mobile/src/map/presentation/marine_map_cubit.dart';

void main() {
  group('MarineMapCubit', () {
    late _MarineRepository repository;
    late MarineMapCubit cubit;

    setUp(() {
      repository = _MarineRepository();
      cubit = MarineMapCubit(repository: repository);
    });

    tearDown(() => cubit.close());

    test(
      'only the latest selected chlorophyll entry updates the map',
      () async {
        final first = Completer<Map<String, double>>();
        final second = Completer<Map<String, double>>();
        repository.chlorophyllResponses[1] = first;
        repository.chlorophyllResponses[2] = second;

        cubit.setScalarLayer(MarineScalarLayer.chlorophyll);
        cubit.setChlorophyllEntry(2);
        second.complete({'cell-a': 2.0});
        await Future<void>.delayed(Duration.zero);
        first.complete({'cell-a': 1.0});
        await Future<void>.delayed(Duration.zero);

        expect(cubit.state.chlorophyllEntry, 2);
        expect(cubit.state.chlorophyllValues, {'cell-a': 2.0});
        expect(cubit.state.chlorophyllLoading, isFalse);
      },
    );

    test(
      'turning chlorophyll off invalidates an outstanding request',
      () async {
        final pending = Completer<Map<String, double>>();
        repository.chlorophyllResponses[1] = pending;

        cubit.setScalarLayer(MarineScalarLayer.chlorophyll);
        cubit.setScalarLayer(MarineScalarLayer.fish);
        pending.complete({'cell-a': 3.0});
        await Future<void>.delayed(Duration.zero);

        expect(cubit.state.scalarLayer, MarineScalarLayer.fish);
        expect(cubit.state.chlorophyllValues, isEmpty);
        expect(cubit.state.chlorophyllLoading, isFalse);
        expect(cubit.state.chlorophyllError, isNull);
      },
    );

    test('base load can be retried after an error', () async {
      repository.baseResponses.add(
        Future<MarineDataset>.error(StateError('offline')),
      );
      final expected = _dataset();
      repository.baseResponses.add(Future.value(expected));

      await cubit.initialize();
      expect(cubit.state.dataset, isNull);
      expect(cubit.state.error, contains('offline'));
      expect(cubit.state.loading, isFalse);

      await cubit.retryBase();
      expect(cubit.state.dataset, same(expected));
      expect(cubit.state.error, isNull);
      expect(cubit.state.loading, isFalse);
    });

    test('cell detail loads all 24 entries with bounded concurrency', () async {
      repository.chlorophyllDelay = const Duration(milliseconds: 1);

      final values = await cubit.loadCellChlorophyll('cell-a');

      expect(values.length, 24);
      expect(values[1], 1.0);
      expect(values[24], 24.0);
      expect(repository.chlorophyllCalls, 24);
      expect(repository.maxConcurrentChlorophyllCalls, lessThanOrEqualTo(3));
      expect(cubit.state.scalarLayer, MarineScalarLayer.fish);
      expect(cubit.state.chlorophyllValues, isEmpty);

      final cached = await cubit.loadCellChlorophyll('cell-a');
      expect(cached, values);
      expect(repository.chlorophyllCalls, 24);
    });

    test('base readiness does not wait for selected-entry preload', () async {
      final pending = Completer<Map<String, double>>();
      repository.chlorophyllResponses[1] = pending;

      await cubit.initialize();

      expect(cubit.state.dataset, isNotNull);
      expect(cubit.state.loading, isFalse);
      expect(cubit.state.scalarLayer, MarineScalarLayer.fish);
      expect(cubit.state.chlorophyllLoading, isFalse);
      expect(repository.chlorophyllCalls, 1);

      pending.complete({'cell-a': 11.0});
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.chlorophyllValues, isEmpty);
      expect(cubit.state.chlorophyllLoading, isFalse);
    });

    test('summary cell requests reuse selected entry map across cells', () async {
      await cubit.initialize();

      for (final cell in ['cell-a', 'cell-b', 'cell-c', 'cell-d', 'cell-e']) {
        final values = await cubit.loadCellChlorophyllEntry(cell, 1);
        expect(values.keys, {1});
        expect(values[1], cell == 'cell-a' ? 1.0 : isNull);
      }

      expect(repository.chlorophyllCallsFor(1), 1);
      expect(cubit.state.scalarLayer, MarineScalarLayer.fish);
      expect(cubit.state.chlorophyllLoading, isFalse);
    });

    test('summary requests for the same entry share an in-flight read', () async {
      final pending = Completer<Map<String, double>>();
      repository.chlorophyllResponses[4] = pending;
      final first = cubit.loadCellChlorophyllEntry('cell-a', 4);
      final second = cubit.loadCellChlorophyllEntry('cell-b', 4);
      await Future<void>.delayed(Duration.zero);
      expect(repository.chlorophyllCallsFor(4), 1);

      pending.complete({'cell-a': 4.0, 'cell-b': 8.0});
      expect(await first, {4: 4.0});
      expect(await second, {4: 8.0});
      expect(repository.chlorophyllCallsFor(4), 1);
    });

    test('selected entry changes and full detail share entry reads', () async {
      await cubit.initialize();
      cubit.setChlorophyllEntry(2);
      final summary = cubit.loadCellChlorophyllEntry('cell-a', 2);
      final detail = cubit.loadCellChlorophyll('cell-a');

      expect(await summary, {2: 2.0});
      final timeline = await detail;
      expect(timeline[1], 1.0);
      expect(timeline[2], 2.0);
      expect(repository.chlorophyllCallsFor(1), 1);
      expect(repository.chlorophyllCallsFor(2), 1);
      expect(repository.maxConcurrentChlorophyllCalls, lessThanOrEqualTo(3));
    });

    test('failed preload is retryable and requested failures propagate', () async {
      repository.failEntry = 1;
      await cubit.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(repository.chlorophyllCallsFor(1), 1);

      await expectLater(
        cubit.loadCellChlorophyllEntry('cell-a', 1),
        throwsA(isA<StateError>()),
      );
      repository.failEntry = null;
      expect(await cubit.loadCellChlorophyllEntry('cell-a', 1), {1: 1.0});
      expect(repository.chlorophyllCallsFor(1), 3);
    });

    test('summary entry validation rejects values outside source range', () {
      expect(
        cubit.loadCellChlorophyllEntry('cell-a', 0),
        throwsArgumentError,
      );
      expect(
        cubit.loadCellChlorophyllEntry('cell-a', 25),
        throwsArgumentError,
      );
    });

    test(
      'chlorophyll errors propagate for cell detail without partial results',
      () async {
        repository.failEntry = 7;

        await expectLater(
          cubit.loadCellChlorophyll('cell-a'),
          throwsA(isA<StateError>()),
        );
        expect(cubit.state.chlorophyllValues, isEmpty);
        expect(cubit.state.scalarLayer, MarineScalarLayer.fish);
      },
    );

    test('presentation options and opacity stay within their bounds', () {
      cubit.setShowCoral(false);
      cubit.setShowMangrove(false);
      cubit.setShowGrid(false);
      cubit.setOpacity(2.0);

      expect(cubit.state.showCoral, isFalse);
      expect(cubit.state.showMangrove, isFalse);
      expect(cubit.state.showGrid, isFalse);
      expect(cubit.state.opacity, 1.0);

      cubit.setOpacity(-1.0);
      expect(cubit.state.opacity, 0.0);
    });
  });
}

MarineDataset _dataset() => const MarineDataset(
  cells: {
    'cell-a': MarineCell(
      gridX: 1,
      gridY: 1,
      point: GeoPoint(latitude: -8.4, longitude: 112.7),
      fish: 1,
      temperature: 25,
      depth: 10,
      cellId: 'cell-a',
    ),
  },
  coral: [],
  mangrove: [],
);

class _MarineRepository implements MarineRepository {
  final List<Future<MarineDataset>> baseResponses = [];
  final Map<int, Completer<Map<String, double>>> chlorophyllResponses = {};
  int chlorophyllCalls = 0;
  final List<int> chlorophyllEntries = [];
  int _activeChlorophyllCalls = 0;
  int maxConcurrentChlorophyllCalls = 0;
  int? failEntry;
  Duration chlorophyllDelay = Duration.zero;

  int chlorophyllCallsFor(int entry) =>
      chlorophyllEntries.where((value) => value == entry).length;

  @override
  Future<MarineDataset> loadBase() => baseResponses.isEmpty
      ? Future.value(_dataset())
      : baseResponses.removeAt(0);

  @override
  Future<Map<String, double>> loadChlorophyll(int entry) async {
    chlorophyllCalls++;
    chlorophyllEntries.add(entry);
    _activeChlorophyllCalls++;
    if (_activeChlorophyllCalls > maxConcurrentChlorophyllCalls) {
      maxConcurrentChlorophyllCalls = _activeChlorophyllCalls;
    }
    try {
      if (failEntry == entry) throw StateError('entry $entry failed');
      final response = chlorophyllResponses.remove(entry);
      if (response != null) return await response.future;
      if (chlorophyllDelay > Duration.zero) {
        await Future<void>.delayed(chlorophyllDelay);
      }
      return {'cell-a': entry.toDouble()};
    } finally {
      _activeChlorophyllCalls--;
    }
  }
}
