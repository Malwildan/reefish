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
  int _activeChlorophyllCalls = 0;
  int maxConcurrentChlorophyllCalls = 0;
  int? failEntry;
  Duration chlorophyllDelay = Duration.zero;

  @override
  Future<MarineDataset> loadBase() => baseResponses.isEmpty
      ? Future.value(_dataset())
      : baseResponses.removeAt(0);

  @override
  Future<Map<String, double>> loadChlorophyll(int entry) async {
    chlorophyllCalls++;
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
