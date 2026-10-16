import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/sailing_location_source.dart';
import '../domain/sailing_session.dart';
import '../domain/sailing_session_store.dart';

enum SailingPhaseView { idle, atDeparture, transit, fishing, completed }

class SailingState {
  const SailingState({
    this.session,
    this.busy = false,
    this.error,
    this.locationStatus = SailingLocationStatus.permissionRequired,
  });

  final SailingSession? session;
  final bool busy;
  final String? error;
  final SailingLocationStatus locationStatus;

  SailingPhaseView get phase => switch (session?.phase) {
    null => SailingPhaseView.idle,
    SailingPhase.atDeparture => SailingPhaseView.atDeparture,
    SailingPhase.transit => SailingPhaseView.transit,
    SailingPhase.fishing => SailingPhaseView.fishing,
    SailingPhase.completed => SailingPhaseView.completed,
  };

  SailingState copyWith({
    SailingSession? session,
    bool? clearSession,
    bool? busy,
    String? error,
    bool? clearError,
    SailingLocationStatus? locationStatus,
  }) => SailingState(
    session: clearSession == true ? null : session ?? this.session,
    busy: busy ?? this.busy,
    error: clearError == true ? null : error ?? this.error,
    locationStatus: locationStatus ?? this.locationStatus,
  );
}

/// One foreground lifecycle state machine. All writes and location callbacks
/// pass through a single queue; emitted session state is always persisted first.
class SailingBloc extends Cubit<SailingState> {
  SailingBloc({
    required SailingSessionStore store,
    required SailingLocationSource locationSource,
    DateTime Function()? now,
  }) : _store = store,
       _locationSource = locationSource,
       _now = now ?? DateTime.now,
       super(const SailingState());

  final SailingSessionStore _store;
  final SailingLocationSource _locationSource;
  final DateTime Function() _now;
  StreamSubscription<SailingPosition>? _locationSubscription;
  int _streamGeneration = 0;
  Future<void> _queue = Future<void>.value();
  bool _disposed = false;

  Future<void> _serialize(Future<void> Function() action) {
    final completer = Completer<void>();
    _queue = _queue.then((_) async {
      if (_disposed) {
        completer.complete();
        return;
      }
      try {
        await action();
        completer.complete();
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  void _observeLocation(Future<void> Function() action) {
    unawaited(_serialize(action).catchError((Object _) {}));
  }

  Future<void> restoreSession() => _serialize(() async {
    emit(state.copyWith(busy: true, clearError: true));
    try {
      final session = await _store.read();
      if (session == null) {
        emit(state.copyWith(clearSession: true, busy: false));
        return;
      }
      final recoveredSession =
          session.phase != SailingPhase.completed &&
              session.locationStatus == SailingLocationStatus.available
          ? session.copyWith(locationStatus: SailingLocationStatus.paused)
          : session;
      emit(
        state.copyWith(
          session: recoveredSession,
          busy: false,
          locationStatus: recoveredSession.locationStatus,
        ),
      );
      if (!identical(recoveredSession, session)) {
        // Restored sessions never resume GPS implicitly. The foreground UI
        // explicitly calls resumeTracking after showing the recovery state.
        await _save(recoveredSession);
      }
    } catch (error) {
      emit(
        state.copyWith(
          busy: false,
          error: _message(error),
          locationStatus: SailingLocationStatus.lost,
        ),
      );
    }
  });

  Future<void> startSailing({
    required String ownerId,
    required SailingPoint departure,
    SailingPoint? plannedFishingPoint,
  }) => _serialize(() async {
    emit(state.copyWith(busy: true, clearError: true));
    try {
      if (ownerId.trim().isEmpty) throw StateError('no-account');
      if (state.session != null || await _store.read() != null) {
        throw StateError('existing-session');
      }
      departure.validate('departure');
      plannedFishingPoint?.validate('plannedFishingPoint');
      final session = SailingSession(
        ownerId: ownerId,
        clientTripId: newSailingClientTripId(),
        phase: SailingPhase.atDeparture,
        departure: departure,
        plannedFishingPoint: plannedFishingPoint,
        startedAt: _now().toUtc(),
        departedAt: null,
        track: const [],
        locationStatus: SailingLocationStatus.permissionRequired,
      );
      await _save(session);
      emit(state.copyWith(session: session, busy: false));
      await _beginLocationStream();
    } catch (error) {
      emit(state.copyWith(busy: false, error: _message(error)));
    }
  });

  /// This is the explicit user action that changes departure into transit.
  Future<void> markDeparted() => _serialize(() async {
    final session = _requireSession();
    if (session.phase != SailingPhase.atDeparture) {
      throw StateError('invalid-departure-phase');
    }
    final time = _now().toUtc();
    final earliestTrackTime = time.subtract(const Duration(minutes: 10));
    final retained = session.track
        .where((point) => !point.recordedAt.isBefore(earliestTrackTime))
        .map(
          (point) => SailingTrackPoint(
            seq: 0,
            point: point.point,
            recordedAt: point.recordedAt,
            accuracyM: point.accuracyM,
            speedMs: point.speedMs,
          ),
        )
        .toList(growable: false);
    await _commit(
      session.copyWith(
        phase: SailingPhase.transit,
        departedAt: time,
        track: retained,
      ),
    );
  });

  /// Requires a user-confirmed actual location. A planned point is never copied
  /// here automatically and no GPS stop/dwell signal can trigger this action.
  Future<void> markFishing({required SailingPoint actualPoint}) =>
      _serialize(() async {
        final session = _requireSession();
        if (session.phase != SailingPhase.transit) {
          throw StateError('invalid-fishing-phase');
        }
        actualPoint.validate('actualFishingPoint');
        final time = _now().toUtc();
        await _commit(
          session.copyWith(
            phase: SailingPhase.fishing,
            actualFishingPoint: actualPoint,
            fishingStartedAt: time,
          ),
        );
      });

  /// Finishing without a fishing point is allowed for cancelled or empty
  /// sessions, but `toTripInput` remains unavailable until an actual fishing
  /// point exists because the backend requires at least one fishing point.
  Future<void> finishSailing() => _serialize(() async {
    final session = _requireSession();
    if (session.phase == SailingPhase.completed) return;
    final time = _now().toUtc();
    _streamGeneration++;
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    await _commit(
      session.copyWith(
        phase: SailingPhase.completed,
        returnedAt: time,
        returnLocation: session.track.isEmpty
            ? null
            : SailingReturnLocation(
                point: session.track.last.point,
                recordedAt: session.track.last.recordedAt,
              ),
        fishingEndedAt: session.phase == SailingPhase.fishing ? time : null,
        locationStatus: SailingLocationStatus.paused,
      ),
    );
  });

  Future<void> pauseTracking() => _serialize(() async {
    final session = state.session;
    if (session == null || session.phase == SailingPhase.completed) return;
    _streamGeneration++;
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    await _commit(
      session.copyWith(locationStatus: SailingLocationStatus.paused),
    );
  });

  Future<void> resumeTracking() => _serialize(() async {
    final session = _requireSession();
    if (session.phase == SailingPhase.completed) return;
    await _beginLocationStream();
  });

  /// Called by the UI only after the backend confirms submission success.
  Future<void> clearAcknowledgedSession(String clientTripId) =>
      _serialize(() async {
        final session = _requireSession();
        if (session.phase != SailingPhase.completed ||
            session.clientTripId != clientTripId) {
          throw StateError('invalid-acknowledged-session');
        }
        await _locationSubscription?.cancel();
        _locationSubscription = null;
        await _store.clear(clientTripId: clientTripId);
        emit(state.copyWith(clearSession: true, clearError: true));
      });

  Future<void> _beginLocationStream() async {
    final generation = ++_streamGeneration;
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    final permission = await _locationSource.requestForegroundPermission();
    if (permission != SailingPermission.granted) {
      final status =
          permission == SailingPermission.serviceDisabled ||
              permission == SailingPermission.denied ||
              permission == SailingPermission.deniedForever
          ? SailingLocationStatus.lost
          : SailingLocationStatus.permissionRequired;
      await _commit(_requireSession().copyWith(locationStatus: status));
      emit(state.copyWith(error: _permissionMessage(permission)));
      return;
    }
    await _commit(
      _requireSession().copyWith(
        locationStatus: SailingLocationStatus.available,
      ),
    );
    _locationSubscription = _locationSource.positions.listen(
      (position) =>
          _observeLocation(() => _recordPosition(position, generation)),
      onError: (Object error) => _observeLocation(() async {
        if (generation != _streamGeneration) return;
        _streamGeneration++;
        await _locationSubscription?.cancel();
        _locationSubscription = null;
        final session = state.session;
        if (session != null && session.phase != SailingPhase.completed) {
          await _commit(
            session.copyWith(locationStatus: SailingLocationStatus.lost),
          );
        }
        emit(
          state.copyWith(
            error: 'Sinyal GPS terputus. Aktifkan kembali untuk melanjutkan.',
          ),
        );
      }),
      onDone: () => _observeLocation(() async {
        if (generation != _streamGeneration) return;
        _streamGeneration++;
        _locationSubscription = null;
        final session = state.session;
        if (session != null &&
            session.phase != SailingPhase.completed &&
            session.locationStatus == SailingLocationStatus.available) {
          await _commit(
            session.copyWith(locationStatus: SailingLocationStatus.lost),
          );
          emit(
            state.copyWith(
              error: 'Sinyal GPS terputus. Aktifkan kembali untuk melanjutkan.',
            ),
          );
        }
      }),
      cancelOnError: true,
    );
  }

  Future<void> _recordPosition(SailingPosition position, int generation) async {
    final session = state.session;
    if (generation != _streamGeneration ||
        session == null ||
        session.phase == SailingPhase.completed ||
        session.locationStatus != SailingLocationStatus.available ||
        state.locationStatus != SailingLocationStatus.available) {
      return;
    }
    final now = _now().toUtc();
    final recordedAt = position.recordedAt.toUtc();
    try {
      position.point.validate('location');
    } on ArgumentError {
      return;
    }
    if (!position.accuracyM.isFinite ||
        position.accuracyM <= 0 ||
        position.accuracyM > 100 ||
        recordedAt.isBefore(now.subtract(const Duration(minutes: 5))) ||
        recordedAt.isAfter(now.add(const Duration(seconds: 30))) ||
        (session.track.isNotEmpty &&
            !recordedAt.isAfter(session.track.last.recordedAt))) {
      return;
    }
    if (session.track.length >= maxTrackPoints) {
      await _locationSubscription?.cancel();
      _locationSubscription = null;
      await _commit(
        session.copyWith(locationStatus: SailingLocationStatus.paused),
      );
      emit(state.copyWith(error: 'Batas panjang rekaman GPS tercapai.'));
      return;
    }
    final speed = position.speedMs;
    if (speed != null && (!speed.isFinite || speed > 100)) return;
    final newTrackPoint = SailingTrackPoint(
      seq: session.track.length,
      point: position.point,
      recordedAt: recordedAt,
      accuracyM: position.accuracyM,
      speedMs: speed != null && speed < 0 ? null : speed,
    );
    final unsequenced = session.phase == SailingPhase.atDeparture
        ? [newTrackPoint]
        : [...session.track, newTrackPoint];
    final next = session.copyWith(
      track: unsequenced
          .asMap()
          .entries
          .map(
            (entry) => SailingTrackPoint(
              seq: entry.key,
              point: entry.value.point,
              recordedAt: entry.value.recordedAt,
              accuracyM: entry.value.accuracyM,
              speedMs: entry.value.speedMs,
            ),
          )
          .toList(growable: false),
    );
    await _commit(next);
  }

  Future<void> _commit(SailingSession session) async {
    try {
      await _save(session);
      emit(
        state.copyWith(
          session: session,
          locationStatus: session.locationStatus,
          clearError: true,
        ),
      );
    } catch (error) {
      _streamGeneration++;
      await _locationSubscription?.cancel();
      _locationSubscription = null;
      emit(
        state.copyWith(
          error: _message(error),
          locationStatus: SailingLocationStatus.lost,
        ),
      );
      rethrow;
    }
  }

  Future<void> _save(SailingSession session) => _store.save(session);

  SailingSession _requireSession() =>
      state.session ?? (throw StateError('no-session'));

  String _permissionMessage(SailingPermission permission) =>
      switch (permission) {
        SailingPermission.granted => '',
        SailingPermission.denied => 'Izin lokasi belum diberikan.',
        SailingPermission.deniedForever =>
          'Aktifkan izin lokasi melalui pengaturan perangkat.',
        SailingPermission.serviceDisabled =>
          'Aktifkan layanan lokasi untuk merekam perjalanan.',
      };

  String _message(Object error) {
    if (error is SailingStoreFailure) {
      return error.message;
    }
    if (error is ArgumentError) {
      return 'Periksa kembali titik koordinat yang dipilih.';
    }
    if (error is StateError) {
      return switch (error.message) {
        'existing-session' =>
          'Selesaikan atau hapus sesi berlayar sebelumnya sebelum memulai sesi baru.',
        'no-account' => 'Akun belum tersedia. Masuk kembali untuk melanjutkan.',
        'no-session' => 'Tidak ada sesi berlayar yang tersimpan.',
        'invalid-departure-phase' =>
          'Keberangkatan hanya dapat ditandai saat berada di titik awal.',
        'invalid-fishing-phase' =>
          'Titik menangkap ikan hanya dapat ditandai selama perjalanan.',
        'invalid-acknowledged-session' =>
          'Sesi hanya dapat dihapus setelah pengiriman berhasil dikonfirmasi.',
        _ => 'Tahap perjalanan tidak sesuai untuk tindakan ini.',
      };
    }
    return 'Terjadi masalah saat menyimpan perjalanan. Coba lagi.';
  }

  @override
  Future<void> close() async {
    _disposed = true;
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    await _queue;
    await super.close();
  }
}
