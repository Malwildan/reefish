import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/device_location_service.dart';
import '../domain/departure_repository.dart';
import '../domain/fishing_point_repository.dart';
import '../domain/geo_point.dart';
import '../domain/grid_cell.dart';
import '../domain/grid_policy.dart';
import '../domain/grid_policy_failure.dart';
import '../domain/grid_policy_repository.dart';
import '../domain/metric_grid_500.dart';

enum DepartureSelectionSource { gps, map }

enum DepartureFlowStep { departure, confirmation, fishing }

class DepartureState {
  const DepartureState({
    this.point,
    this.cell,
    this.savedDeparture,
    this.fishingPoint,
    this.fishingCell,
    this.savedFishingPoint,
    this.source,
    this.policy,
    this.policyFailure,
    this.step = DepartureFlowStep.departure,
    this.policyLoading = true,
    this.locating = false,
    this.saving = false,
    this.fishingSaving = false,
    this.saved = false,
    this.fishingSaved = false,
    this.showMap = false,
    this.message,
    this.fishingMessage,
    this.isError = false,
  });

  final GeoPoint? point;
  final GridCell? cell;
  final DeparturePoint? savedDeparture;
  final GeoPoint? fishingPoint;
  final GridCell? fishingCell;
  final FishingPointSelection? savedFishingPoint;
  final DepartureSelectionSource? source;
  final GridPolicySnapshot? policy;
  final GridPolicyFailure? policyFailure;
  final DepartureFlowStep step;
  final bool policyLoading;
  final bool locating;
  final bool saving;
  final bool fishingSaving;
  final bool saved;
  final bool fishingSaved;
  final bool showMap;
  final String? message;
  final String? fishingMessage;
  final bool isError;

  bool get canSave => point != null && cell != null && !saving;

  GridAccess fishingAccessAt(DateTime at) {
    if (fishingCell == null) return GridAccess.unknown;
    final access = policy?.accessFor(fishingCell!.id, at) ?? GridAccess.unknown;
    if (access == GridAccess.locked) return access;
    return policyFailure == null ? access : GridAccess.unknown;
  }

  bool canCompleteFishingAt(DateTime at) =>
      fishingPoint != null &&
      fishingCell != null &&
      !fishingSaving &&
      fishingAccessAt(at) == GridAccess.unlocked;

  DepartureState copyWith({
    GeoPoint? point,
    GridCell? cell,
    DeparturePoint? savedDeparture,
    GeoPoint? fishingPoint,
    GridCell? fishingCell,
    FishingPointSelection? savedFishingPoint,
    DepartureSelectionSource? source,
    GridPolicySnapshot? policy,
    GridPolicyFailure? policyFailure,
    bool clearPolicyFailure = false,
    DepartureFlowStep? step,
    bool? policyLoading,
    bool? locating,
    bool? saving,
    bool? fishingSaving,
    bool? saved,
    bool? fishingSaved,
    bool? showMap,
    String? message,
    String? fishingMessage,
    bool clearMessage = false,
    bool clearFishingMessage = false,
    bool? isError,
    bool clearFishingPoint = false,
    bool clearSavedDeparture = false,
  }) => DepartureState(
    point: point ?? this.point,
    cell: cell ?? this.cell,
    savedDeparture: clearSavedDeparture
        ? null
        : (savedDeparture ?? this.savedDeparture),
    fishingPoint: clearFishingPoint
        ? null
        : (fishingPoint ?? this.fishingPoint),
    fishingCell: clearFishingPoint ? null : (fishingCell ?? this.fishingCell),
    savedFishingPoint: savedFishingPoint ?? this.savedFishingPoint,
    source: source ?? this.source,
    policy: policy ?? this.policy,
    policyFailure: clearPolicyFailure
        ? null
        : policyFailure ?? this.policyFailure,
    step: step ?? this.step,
    policyLoading: policyLoading ?? this.policyLoading,
    locating: locating ?? this.locating,
    saving: saving ?? this.saving,
    fishingSaving: fishingSaving ?? this.fishingSaving,
    saved: saved ?? this.saved,
    fishingSaved: fishingSaved ?? this.fishingSaved,
    showMap: showMap ?? this.showMap,
    message: clearMessage ? null : (message ?? this.message),
    fishingMessage: clearFishingMessage
        ? null
        : (fishingMessage ?? this.fishingMessage),
    isError: isError ?? this.isError,
  );
}

class DepartureCubit extends Cubit<DepartureState> {
  DepartureCubit({
    required GridPolicyRepository gridPolicyRepository,
    required DepartureRepository departureRepository,
    required DeviceLocationService locationService,
    FishingPointRepository? fishingPointRepository,
    MetricGrid500? grid,
  }) : _gridPolicyRepository = gridPolicyRepository,
       _departureRepository = departureRepository,
       _fishingPointRepository = fishingPointRepository,
       _locationService = locationService,
       _grid = grid ?? MetricGrid500(),
       super(const DepartureState());

  final GridPolicyRepository _gridPolicyRepository;
  final DepartureRepository _departureRepository;
  final FishingPointRepository? _fishingPointRepository;
  final DeviceLocationService _locationService;
  final MetricGrid500 _grid;
  int _locationRequest = 0;
  int _policyRefresh = 0;
  Timer? _policyRenewalTimer;

  Future<void> initialize() async {
    await Future.wait([refreshPolicy(), _restoreSavedPoints()]);
  }

  Future<void> _restoreSavedPoints() async {
    try {
      final saved = await _departureRepository.read();
      if (isClosed || saved == null || state.point != null) return;
      final cell = _grid.resolve(saved.point);
      emit(
        state.copyWith(
          point: saved.point,
          cell: cell,
          savedDeparture: saved,
          source: DepartureSelectionSource.map,
          step: DepartureFlowStep.confirmation,
        ),
      );
    } catch (_) {
      // A failed local read does not prevent choosing a new departure point.
    }
  }

  Future<bool> refreshPolicy() async {
    final request = ++_policyRefresh;
    _policyRenewalTimer?.cancel();
    _policyRenewalTimer = null;
    emit(state.copyWith(policyLoading: true, clearMessage: true));
    try {
      final policy = await _gridPolicyRepository.fetchSnapshot();
      if (!isClosed && request == _policyRefresh) {
        _schedulePolicyRenewal(policy);
        final message = state.step == DepartureFlowStep.fishing
            ? _fishingPolicyMessage(state.fishingCell, policy)
            : _selectionMessage(state.cell, policy);
        emit(
          state.copyWith(
            policy: policy,
            clearPolicyFailure: true,
            policyLoading: false,
            message: state.step == DepartureFlowStep.fishing ? null : message,
            clearMessage:
                state.step == DepartureFlowStep.fishing || message == null,
            fishingMessage: state.step == DepartureFlowStep.fishing
                ? message
                : null,
            clearFishingMessage:
                state.step != DepartureFlowStep.fishing || message == null,
            isError: false,
          ),
        );
        return true;
      }
      return false;
    } catch (error) {
      if (!isClosed && request == _policyRefresh) {
        final failure = error is GridPolicyFailure
            ? error
            : const GridPolicyFailure(GridPolicyFailureCode.unavailable);
        emit(
          state.copyWith(
            policyLoading: false,
            policyFailure: failure,
            message: state.step == DepartureFlowStep.fishing
                ? null
                : '${failure.userMessage} Titik keberangkatan tetap bisa dicatat.',
            fishingMessage: state.step == DepartureFlowStep.fishing
                ? failure.userMessage
                : null,
            isError: true,
          ),
        );
      }
      return false;
    }
  }

  void _schedulePolicyRenewal(GridPolicySnapshot policy) {
    _policyRenewalTimer?.cancel();
    final expiresAt = policy.validUntil ?? policy.expiresAt;
    final delay = expiresAt.difference(DateTime.now().toUtc());
    if (delay <= Duration.zero) return;
    _policyRenewalTimer = Timer(delay, () {
      _policyRenewalTimer = null;
      if (!isClosed) unawaited(refreshPolicy());
    });
  }

  @override
  Future<void> close() {
    _policyRenewalTimer?.cancel();
    _policyRenewalTimer = null;
    return super.close();
  }

  bool selectPoint(GeoPoint point, {required DepartureSelectionSource source}) {
    if (state.saving) return false;
    if (source == DepartureSelectionSource.map) _locationRequest++;
    late final GridCell cell;
    try {
      if (!_grid.initialBounds.contains(point)) {
        throw RangeError('Point is outside the configured departure bounds');
      }
      cell = _grid.resolve(point);
    } on ArgumentError {
      emit(
        state.copyWith(
          message: 'Titik ini berada di luar jangkauan peta.',
          isError: true,
        ),
      );
      return false;
    }
    final message = _selectionMessage(
      cell,
      state.policy,
      failure: state.policyFailure,
    );
    emit(
      state.copyWith(
        point: point,
        cell: cell,
        source: source,
        locating: source == DepartureSelectionSource.map
            ? false
            : state.locating,
        saved: false,
        clearSavedDeparture: true,
        step: DepartureFlowStep.departure,
        message: message,
        clearMessage: message == null,
        isError: false,
      ),
    );
    return true;
  }

  String? _selectionMessage(
    GridCell? cell,
    GridPolicySnapshot? policy, {
    GridPolicyFailure? failure,
  }) {
    if (cell == null) return null;
    if (failure != null) {
      return '${failure.userMessage} Titik keberangkatan tetap dapat dicatat.';
    }
    final access =
        policy?.accessFor(cell.id, DateTime.now()) ?? GridAccess.unknown;
    final lockReason = policy?.locks[cell.id]?.reason;
    return switch (access) {
      GridAccess.locked =>
        'Pembatasan tersimpan: ${lockReason ?? 'alasan tidak dicantumkan.'}',
      GridAccess.unknown =>
        'Status petak belum terverifikasi. Titik keberangkatan tetap dapat dicatat.',
      GridAccess.unlocked => null,
    };
  }

  String? _fishingPolicyMessage(
    GridCell? cell,
    GridPolicySnapshot? policy, {
    GridPolicyFailure? failure,
  }) {
    if (failure != null) return failure.userMessage;
    if (cell == null) return null;
    final access =
        policy?.accessFor(cell.id, DateTime.now()) ?? GridAccess.unknown;
    if (access == GridAccess.unlocked) return null;
    final reason = policy?.locks[cell.id]?.reason;
    if (access == GridAccess.locked) {
      return 'Petak ini terkunci${reason == null ? '' : ': $reason'}. Pilih petak lain.';
    }
    return 'Status petak belum terverifikasi. Muat ulang status sebelum memilih lokasi penangkapan.';
  }

  Future<void> selectCurrentLocation() async {
    if (state.locating) return;
    final request = ++_locationRequest;
    emit(state.copyWith(locating: true, clearMessage: true));
    try {
      final point = await _locationService.getCurrentPosition();
      if (isClosed || request != _locationRequest) return;
      selectPoint(point, source: DepartureSelectionSource.gps);
      if (!isClosed && request == _locationRequest) {
        emit(
          state.copyWith(
            locating: false,
            step: state.point == point
                ? DepartureFlowStep.confirmation
                : state.step,
          ),
        );
      }
    } on LocationServiceFailure catch (failure) {
      if (!isClosed && request == _locationRequest) {
        emit(
          state.copyWith(
            locating: false,
            message: failure.message,
            isError: true,
          ),
        );
      }
    } catch (_) {
      if (!isClosed && request == _locationRequest) {
        emit(
          state.copyWith(
            locating: false,
            message:
                'Lokasi perangkat belum tersedia. Kamu tetap bisa memilih titik di peta.',
            isError: true,
          ),
        );
      }
    }
  }

  Future<void> save() async {
    final point = state.point;
    final cell = state.cell;
    if (point == null || cell == null || state.saving) return;
    emit(state.copyWith(saving: true, clearMessage: true));
    final departure = DeparturePoint(
      point: point,
      cellId: cell.id,
      savedAt: DateTime.now().toUtc(),
    );
    try {
      await _departureRepository.save(departure);
      if (!isClosed) {
        emit(
          state.copyWith(
            saving: false,
            saved: true,
            savedDeparture: departure,
            step: DepartureFlowStep.confirmation,
            showMap: false,
            message: 'Titik keberangkatan tersimpan.',
            isError: false,
          ),
        );
      }
    } catch (_) {
      if (!isClosed) {
        emit(
          state.copyWith(
            saving: false,
            message: 'Titik belum tersimpan. Coba lagi.',
            isError: true,
          ),
        );
      }
    }
  }

  Future<void> saveAndOpenFishingStep() async {
    if (state.savedDeparture == null || !state.saved) {
      await save();
    }
    if (isClosed || state.savedDeparture == null || !state.saved) return;
    await openFishingStep();
  }

  void editDeparture() {
    if (state.saving || state.fishingSaving) return;
    emit(
      state.copyWith(
        step: DepartureFlowStep.departure,
        showMap: false,
        clearMessage: true,
      ),
    );
  }

  Future<void> openFishingStep() async {
    if (state.savedDeparture == null || state.saving) return;
    emit(
      state.copyWith(
        step: DepartureFlowStep.fishing,
        showMap: false,
        clearFishingPoint: true,
        fishingSaved: false,
        clearFishingMessage: true,
      ),
    );
    await refreshPolicy();
  }

  void backToConfirmation() {
    if (state.fishingSaving) return;
    emit(
      state.copyWith(
        step: DepartureFlowStep.confirmation,
        showMap: false,
        clearFishingMessage: true,
      ),
    );
  }

  bool selectFishingPoint(GeoPoint point) {
    if (state.fishingSaving) return false;
    late final GridCell cell;
    try {
      if (!_grid.initialBounds.contains(point)) {
        throw RangeError('Point is outside the configured fishing bounds');
      }
      cell = _grid.resolve(point);
    } on ArgumentError {
      emit(
        state.copyWith(
          fishingMessage: 'Titik ini berada di luar jangkauan peta.',
          isError: true,
        ),
      );
      return false;
    }
    final message = _fishingPolicyMessage(
      cell,
      state.policy,
      failure: state.policyFailure,
    );
    emit(
      state.copyWith(
        fishingPoint: point,
        fishingCell: cell,
        clearFishingPoint: false,
        fishingSaved: false,
        fishingMessage: message,
        clearFishingMessage: message == null,
        isError: message != null,
      ),
    );
    return message == null;
  }

  Future<FishingPointSelection?> completeFishingSelection() async {
    final point = state.fishingPoint;
    final cell = state.fishingCell;
    final departure = state.savedDeparture;
    if (point == null ||
        cell == null ||
        departure == null ||
        state.fishingSaving) {
      return null;
    }
    final repository = _fishingPointRepository;
    if (repository == null) {
      emit(
        state.copyWith(
          fishingMessage: 'Penyimpanan titik ikan belum tersedia.',
          isError: true,
        ),
      );
      return null;
    }
    emit(state.copyWith(fishingSaving: true, clearFishingMessage: true));
    final refreshed = await refreshPolicy();
    if (isClosed) return null;
    if (!refreshed ||
        state.fishingPoint != point ||
        state.fishingCell?.id != cell.id ||
        state.savedDeparture?.cellId != departure.cellId ||
        state.savedDeparture?.point != departure.point ||
        state.fishingAccessAt(DateTime.now()) != GridAccess.unlocked) {
      emit(
        state.copyWith(
          fishingSaving: false,
          fishingMessage:
              _fishingPolicyMessage(
                state.fishingCell,
                state.policy,
                failure: state.policyFailure,
              ) ??
              'Status petak belum terverifikasi. Muat ulang status lalu pilih titik lagi.',
          isError: true,
        ),
      );
      return null;
    }
    final selection = FishingPointSelection(
      point: point,
      cellId: cell.id,
      departure: departure,
      savedAt: DateTime.now().toUtc(),
    );
    try {
      await repository.save(selection);
      if (isClosed) return selection;
      emit(
        state.copyWith(
          fishingSaving: false,
          fishingSaved: true,
          savedFishingPoint: selection,
          fishingMessage: 'Titik penangkapan tersimpan.',
          isError: false,
        ),
      );
      return selection;
    } catch (_) {
      if (!isClosed) {
        emit(
          state.copyWith(
            fishingSaving: false,
            fishingMessage: 'Titik ikan belum tersimpan. Coba lagi.',
            isError: true,
          ),
        );
      }
      return null;
    }
  }

  void setMapVisible(bool visible) => emit(
    state.copyWith(
      showMap: visible,
      step: !visible && state.point != null
          ? DepartureFlowStep.confirmation
          : state.step,
      clearMessage: true,
    ),
  );

  void clearMessage() =>
      emit(state.copyWith(clearMessage: true, clearFishingMessage: true));
}
