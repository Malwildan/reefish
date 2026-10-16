import 'dart:async';
import 'dart:collection';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/marine_data.dart';
import '../domain/marine_repository.dart';

class MarineMapState {
  const MarineMapState({
    this.dataset,
    this.loading = false,
    this.error,
    this.scalarLayer = MarineScalarLayer.fish,
    this.showCoral = true,
    this.showMangrove = true,
    this.showGrid = true,
    this.opacity = 0.55,
    this.chlorophyllEntry = 1,
    this.chlorophyllValues = const {},
    this.chlorophyllLoading = false,
    this.chlorophyllError,
  });

  final MarineDataset? dataset;
  final bool loading;
  final String? error;
  final MarineScalarLayer scalarLayer;
  final bool showCoral;
  final bool showMangrove;
  final bool showGrid;
  final double opacity;
  final int chlorophyllEntry;
  final Map<String, double> chlorophyllValues;
  final bool chlorophyllLoading;
  final String? chlorophyllError;

  MarineMapState copyWith({
    MarineDataset? dataset,
    bool? loading,
    String? error,
    bool clearError = false,
    MarineScalarLayer? scalarLayer,
    bool? showCoral,
    bool? showMangrove,
    bool? showGrid,
    double? opacity,
    int? chlorophyllEntry,
    Map<String, double>? chlorophyllValues,
    bool? chlorophyllLoading,
    String? chlorophyllError,
    bool clearChlorophyllError = false,
  }) => MarineMapState(
    dataset: dataset ?? this.dataset,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    scalarLayer: scalarLayer ?? this.scalarLayer,
    showCoral: showCoral ?? this.showCoral,
    showMangrove: showMangrove ?? this.showMangrove,
    showGrid: showGrid ?? this.showGrid,
    opacity: opacity ?? this.opacity,
    chlorophyllEntry: chlorophyllEntry ?? this.chlorophyllEntry,
    chlorophyllValues: chlorophyllValues ?? this.chlorophyllValues,
    chlorophyllLoading: chlorophyllLoading ?? this.chlorophyllLoading,
    chlorophyllError: clearChlorophyllError
        ? null
        : (chlorophyllError ?? this.chlorophyllError),
  );
}

class MarineMapCubit extends Cubit<MarineMapState> {
  MarineMapCubit({required MarineRepository repository})
    : _repository = repository,
      super(const MarineMapState());

  static const _detailCacheCapacity = 5;
  static const _chlorophyllConcurrency = 3;

  final MarineRepository _repository;
  int _baseRequest = 0;
  int _chlorophyllRequest = 0;

  // A shared semaphore bounds repository reads even when several cell detail
  // requests and a selected map layer are loading at the same time.
  int _activeChlorophyllReads = 0;
  final Queue<Completer<void>> _chlorophyllReadQueue = Queue();
  final LinkedHashMap<String, Map<int, double?>> _detailCache = LinkedHashMap();
  final Map<String, Future<Map<int, double?>>> _detailInFlight = {};

  Future<void> initialize() => retryBase();

  Future<void> retryBase() async {
    final request = ++_baseRequest;
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final dataset = await _repository.loadBase();
      if (!isClosed && request == _baseRequest) {
        emit(
          state.copyWith(dataset: dataset, loading: false, clearError: true),
        );
      }
    } catch (error) {
      if (!isClosed && request == _baseRequest) {
        emit(state.copyWith(loading: false, error: error.toString()));
      }
    }
  }

  void setScalarLayer(MarineScalarLayer layer) {
    if (layer == state.scalarLayer) return;
    emit(state.copyWith(scalarLayer: layer));
    if (layer == MarineScalarLayer.chlorophyll) {
      _loadSelectedChlorophyll();
    } else {
      ++_chlorophyllRequest;
      emit(
        state.copyWith(
          chlorophyllValues: const {},
          chlorophyllLoading: false,
          clearChlorophyllError: true,
        ),
      );
    }
  }

  void setShowCoral(bool show) => emit(state.copyWith(showCoral: show));

  void setShowMangrove(bool show) => emit(state.copyWith(showMangrove: show));

  void setShowGrid(bool show) => emit(state.copyWith(showGrid: show));

  void setOpacity(double opacity) {
    final value = opacity.isNaN ? 0.0 : opacity.clamp(0.0, 1.0).toDouble();
    emit(state.copyWith(opacity: value));
  }

  void setChlorophyllEntry(int entry) {
    final value = entry.clamp(1, 24);
    if (value == state.chlorophyllEntry) return;
    ++_chlorophyllRequest;
    emit(
      state.copyWith(
        chlorophyllEntry: value,
        chlorophyllValues: const {},
        chlorophyllLoading: false,
        clearChlorophyllError: true,
      ),
    );
    if (state.scalarLayer == MarineScalarLayer.chlorophyll) {
      _loadSelectedChlorophyll();
    }
  }

  Future<void> retryChlorophyll() async {
    if (state.scalarLayer == MarineScalarLayer.chlorophyll) {
      await _loadSelectedChlorophyll();
    }
  }

  Future<void> _loadSelectedChlorophyll() async {
    final request = ++_chlorophyllRequest;
    final entry = state.chlorophyllEntry;
    emit(
      state.copyWith(
        chlorophyllValues: const {},
        chlorophyllLoading: true,
        clearChlorophyllError: true,
      ),
    );
    try {
      final values = await _withChlorophyllRead(
        () => _repository.loadChlorophyll(entry),
      );
      if (!isClosed &&
          request == _chlorophyllRequest &&
          state.scalarLayer == MarineScalarLayer.chlorophyll &&
          state.chlorophyllEntry == entry) {
        emit(
          state.copyWith(
            chlorophyllValues: Map.unmodifiable(values),
            chlorophyllLoading: false,
            clearChlorophyllError: true,
          ),
        );
      }
    } catch (error) {
      if (!isClosed &&
          request == _chlorophyllRequest &&
          state.scalarLayer == MarineScalarLayer.chlorophyll &&
          state.chlorophyllEntry == entry) {
        emit(
          state.copyWith(
            chlorophyllLoading: false,
            chlorophyllError: error.toString(),
          ),
        );
      }
    }
  }

  /// Loads every source-order entry for one cell for the detail panel.
  ///
  /// This is independent of the selected map layer and never changes the
  /// visible chlorophyll selection. Repository failures propagate so callers
  /// can show an unavailable state instead of a misleading partial timeline.
  Future<Map<int, double?>> loadCellChlorophyll(String cellId) {
    final cached = _detailCache.remove(cellId);
    if (cached != null) {
      _detailCache[cellId] = cached;
      return Future.value(cached);
    }
    final inFlight = _detailInFlight[cellId];
    if (inFlight != null) return inFlight;

    final future = _loadCellChlorophyll(cellId);
    _detailInFlight[cellId] = future;
    return future.whenComplete(() {
      _detailInFlight.remove(cellId);
    });
  }

  Future<Map<int, double?>> _loadCellChlorophyll(String cellId) async {
    final entries = await Future.wait(
      List<Future<MapEntry<int, double?>>>.generate(24, (index) async {
        final entry = index + 1;
        final values = await _withChlorophyllRead(
          () => _repository.loadChlorophyll(entry),
        );
        return MapEntry(entry, values[cellId]);
      }),
    );
    final result = Map<int, double?>.unmodifiable({
      for (final entry in entries) entry.key: entry.value,
    });
    _detailCache.remove(cellId);
    _detailCache[cellId] = result;
    while (_detailCache.length > _detailCacheCapacity) {
      _detailCache.remove(_detailCache.keys.first);
    }
    return result;
  }

  Future<T> _withChlorophyllRead<T>(Future<T> Function() operation) async {
    if (_activeChlorophyllReads >= _chlorophyllConcurrency) {
      final ready = Completer<void>();
      _chlorophyllReadQueue.addLast(ready);
      await ready.future;
    } else {
      _activeChlorophyllReads++;
    }
    try {
      return await operation();
    } finally {
      if (_chlorophyllReadQueue.isNotEmpty) {
        _chlorophyllReadQueue.removeFirst().complete();
      } else {
        _activeChlorophyllReads--;
      }
    }
  }
}
