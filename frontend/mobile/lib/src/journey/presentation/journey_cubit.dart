import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/journey_models.dart';
import '../domain/journey_repository.dart';

enum JourneyPhase {
  initial,
  loading,
  boat,
  firstTrip,
  submittingTrip,
  dashboard,
  error,
}

class JourneyState {
  const JourneyState({
    this.phase = JourneyPhase.initial,
    this.profile,
    this.dashboard,
    this.pendingDraft,
    this.failure,
    this.tripSubmitted = false,
  });

  final JourneyPhase phase;
  final JourneyProfile? profile;
  final JourneyDashboard? dashboard;
  final JourneyDraft? pendingDraft;
  final JourneyFailure? failure;

  /// True after the trip RPC has acknowledged the pending payload. A dashboard
  /// refresh can then be retried without ever resubmitting that payload.
  final bool tripSubmitted;

  JourneyState copyWith({
    JourneyPhase? phase,
    JourneyProfile? profile,
    JourneyDashboard? dashboard,
    JourneyDraft? pendingDraft,
    bool clearPendingDraft = false,
    JourneyFailure? failure,
    bool clearFailure = false,
    bool? tripSubmitted,
  }) => JourneyState(
    phase: phase ?? this.phase,
    profile: profile ?? this.profile,
    dashboard: dashboard ?? this.dashboard,
    pendingDraft: clearPendingDraft ? null : pendingDraft ?? this.pendingDraft,
    failure: clearFailure ? null : failure ?? this.failure,
    tripSubmitted: tripSubmitted ?? this.tripSubmitted,
  );
}

/// Coordinates the signed-in boat -> first trip -> dashboard journey.
///
/// The draft is durable before the trip RPC starts. Any uncertain RPC failure
/// leaves that exact payload and client_trip_id available for a retry.
class JourneyCubit extends Cubit<JourneyState> {
  JourneyCubit({
    required JourneyRepository repository,
    required JourneyDraftStore draftStore,
  }) : _repository = repository,
       _draftStore = draftStore,
       super(const JourneyState());

  final JourneyRepository _repository;
  final JourneyDraftStore _draftStore;
  Future<void> _serialTail = Future<void>.value();
  String? _ownerId;
  bool _tripSubmissionInFlight = false;

  Future<void> initialize() => _serialize(_initialize);

  Future<void> refresh() => _serialize(() async {
    if (state.profile?.nextStep == JourneyStep.done || state.tripSubmitted) {
      await _loadDashboard();
    } else {
      await _loadProfile();
    }
  });

  Future<void> saveBoat(JourneyBoatInput input) => _serialize(() async {
    if (isClosed) return;
    emit(state.copyWith(phase: JourneyPhase.loading, clearFailure: true));
    try {
      if (state.profile?.role == 'konservatif') {
        throw const JourneyFailure(
          code: JourneyFailureCode.validation,
          message: 'Boat setup is only available to nelayan accounts.',
        );
      }
      input.validate();
      await _repository.createBoat(input);
      await _loadProfile();
    } catch (error) {
      _emitError(error);
    }
  });

  /// Opens the manual trip form for an onboarded nelayan. A pending draft is
  /// deliberately retained so an uncertain submission can still be replayed.
  Future<void> beginTrip() => _serialize(() async {
    if (isClosed) return;
    if (state.profile?.role == 'konservatif') {
      _emitError(
        const JourneyFailure(
          code: JourneyFailureCode.validation,
          message: 'Trip entry is only available to nelayan accounts.',
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        phase: JourneyPhase.firstTrip,
        tripSubmitted: false,
        clearFailure: true,
      ),
    );
  });

  /// Clears a server-rejected draft only after the user chooses to edit it.
  /// Network or API failures do not qualify and keep the exact payload intact.
  Future<void> editRejectedTrip() => _serialize(() async {
    final draft = state.pendingDraft;
    if (isClosed ||
        draft == null ||
        state.failure?.code != JourneyFailureCode.validation) {
      return;
    }
    try {
      await _draftStore.delete();
      if (isClosed) return;
      emit(
        state.copyWith(
          phase: JourneyPhase.firstTrip,
          clearPendingDraft: true,
          tripSubmitted: false,
          clearFailure: true,
        ),
      );
    } catch (error) {
      _emitError(error);
    }
  });

  /// First call persists and submits [input]. Following calls while a draft is
  /// pending retry that stored payload, ignoring newly edited form values.
  Future<void> submitTrip(JourneyTripInput input) {
    if (_tripSubmissionInFlight || isClosed) return Future<void>.value();
    _tripSubmissionInFlight = true;
    final submitted = _serialize(() async {
      if (isClosed) return;
      if (state.tripSubmitted) {
        await _loadDashboard();
        return;
      }
      var draft = state.pendingDraft;
      if (draft == null) {
        final ownerId = _ownerId ?? state.profile?.id;
        if (ownerId == null || ownerId.isEmpty) {
          _emitError(
            const JourneyFailure(
              code: JourneyFailureCode.authenticationRequired,
              message: 'Load the signed-in journey before submitting a trip.',
            ),
          );
          return;
        }
        try {
          input.validate();
          draft = JourneyDraft(
            ownerId: ownerId,
            // Round-trip through the wire shape so the object sent to the RPC is
            // the same validated immutable payload that the store persisted.
            trip: JourneyTripInput.fromJson(input.toJson()),
          );
          await _draftStore.save(draft);
          if (isClosed) return;
          _ownerId = ownerId;
          emit(
            state.copyWith(
              phase: JourneyPhase.firstTrip,
              pendingDraft: draft,
              clearFailure: true,
              tripSubmitted: false,
            ),
          );
        } catch (error) {
          _emitError(error);
          return;
        }
      }

      if (draft.ownerId != _ownerId && _ownerId != null) {
        _emitError(
          const JourneyFailure(
            code: JourneyFailureCode.storage,
            message: 'The pending journey belongs to another account.',
          ),
        );
        return;
      }
      emit(
        state.copyWith(phase: JourneyPhase.submittingTrip, clearFailure: true),
      );
      try {
        await _repository.submitTrip(draft.trip);
        if (isClosed) return;
        // Mark acknowledged before local cleanup or dashboard fetch. Neither
        // failure is permission to call api_post_trip again.
        emit(state.copyWith(phase: JourneyPhase.loading, tripSubmitted: true));
        try {
          await _draftStore.delete();
          if (!isClosed) emit(state.copyWith(clearPendingDraft: true));
        } catch (error) {
          _emitError(error, tripSubmitted: true);
          return;
        }
        await _loadDashboard();
      } catch (error) {
        if (_backendCode(error) == 'BOAT_REQUIRED') {
          await _loadProfile();
        } else {
          _emitError(error);
        }
      }
    });
    return submitted.whenComplete(() => _tripSubmissionInFlight = false);
  }

  Future<void> _initialize() async {
    if (isClosed) return;
    emit(state.copyWith(phase: JourneyPhase.loading, clearFailure: true));
    try {
      final profile = await _repository.getMe();
      if (isClosed) return;
      _ownerId = profile.id;
      JourneyDraft? draft;
      try {
        draft = await _draftStore.read();
      } catch (error) {
        emit(state.copyWith(profile: profile));
        _emitError(error);
        return;
      }
      if (draft != null && draft.ownerId != profile.id) {
        emit(state.copyWith(profile: profile));
        _emitError(
          const JourneyFailure(
            code: JourneyFailureCode.storage,
            message: 'The pending journey belongs to another account.',
          ),
        );
        return;
      }
      if (draft != null) {
        emit(
          state.copyWith(
            phase: JourneyPhase.firstTrip,
            profile: profile,
            pendingDraft: draft,
            tripSubmitted: false,
            clearFailure: true,
          ),
        );
        return;
      }
      emit(state.copyWith(profile: profile));
      await _routeFor(profile);
    } catch (error) {
      _emitError(error);
    }
  }

  Future<void> _loadProfile() async {
    if (isClosed) return;
    emit(state.copyWith(phase: JourneyPhase.loading, clearFailure: true));
    try {
      final profile = await _repository.getMe();
      if (isClosed) return;
      _ownerId = profile.id;
      emit(state.copyWith(profile: profile));
      await _routeFor(profile);
    } catch (error) {
      _emitError(error);
    }
  }

  Future<void> _routeFor(JourneyProfile profile) async {
    switch (profile.nextStep) {
      case JourneyStep.boat:
        emit(state.copyWith(phase: JourneyPhase.boat, clearFailure: true));
      case JourneyStep.firstTrip:
        emit(state.copyWith(phase: JourneyPhase.firstTrip, clearFailure: true));
      case JourneyStep.done:
        await _loadDashboard();
      case JourneyStep.unknown:
        _emitError(
          const JourneyFailure(
            code: JourneyFailureCode.backend,
            message: 'The journey step returned by the service is unsupported.',
          ),
        );
    }
  }

  Future<void> _loadDashboard() async {
    if (isClosed) return;
    emit(state.copyWith(phase: JourneyPhase.loading, clearFailure: true));
    try {
      final dashboard = await _repository.loadDashboard();
      if (isClosed) return;
      emit(
        state.copyWith(
          phase: JourneyPhase.dashboard,
          dashboard: dashboard,
          profile: dashboard.profile,
          clearFailure: true,
        ),
      );
    } catch (error) {
      _emitError(error, tripSubmitted: state.tripSubmitted);
    }
  }

  void _emitError(Object error, {bool? tripSubmitted}) {
    if (isClosed) return;
    final failure = error is JourneyFailure
        ? error
        : JourneyFailure(
            code: error is ArgumentError
                ? JourneyFailureCode.validation
                : JourneyFailureCode.backend,
            message: error.toString(),
            details: error,
          );
    emit(
      state.copyWith(
        phase: JourneyPhase.error,
        failure: failure,
        tripSubmitted: tripSubmitted,
      ),
    );
  }

  String? _backendCode(Object error) {
    if (error is! JourneyFailure || error.details is! Map) return null;
    final details = error.details! as Map;
    final value = details['backendCode'];
    return value is String ? value : null;
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final next = _serialTail.then((_) async {
      if (!isClosed) await operation();
    });
    _serialTail = next.catchError((Object _) {});
    return next;
  }
}
