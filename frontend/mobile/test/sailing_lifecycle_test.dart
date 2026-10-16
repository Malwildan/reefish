import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/sailing/application/sailing_bloc.dart';
import 'package:reefish_mobile/src/sailing/domain/sailing_location_source.dart';
import 'package:reefish_mobile/src/sailing/domain/sailing_session.dart';
import 'package:reefish_mobile/src/sailing/domain/sailing_session_store.dart';

void main() {
  final departure = DateTime.utc(2026, 10, 16, 1);
  final fishing = departure.add(const Duration(seconds: 30));
  final returned = departure.add(const Duration(minutes: 1));

  test(
    'explicit lifecycle actions build a retry-stable sailing trip input',
    () async {
      final store = _MemorySailingStore();
      final locations = _FakeLocationSource();
      var clock = departure;
      final bloc = SailingBloc(
        store: store,
        locationSource: locations,
        now: () => clock,
      );

      await bloc.startSailing(
        ownerId: 'owner-1',
        departure: const SailingPoint(lat: -8.4, lng: 112.6),
        plannedFishingPoint: const SailingPoint(lat: -8.5, lng: 112.7),
      );
      final id = bloc.state.session!.clientTripId;
      expect(bloc.state.phase, SailingPhaseView.atDeparture);
      expect(bloc.state.session!.actualFishingPoint, isNull);

      locations.add(
        _position(departure.add(const Duration(seconds: 1)), -8.4, 112.6),
      );
      await _flush();
      clock = departure.add(const Duration(seconds: 10));
      await bloc.markDeparted();
      expect(bloc.state.phase, SailingPhaseView.transit);

      locations.add(
        _position(departure.add(const Duration(seconds: 20)), -8.41, 112.61),
      );
      await _flush();
      clock = fishing;
      await bloc.markFishing(
        actualPoint: const SailingPoint(lat: -8.5, lng: 112.7),
      );
      expect(bloc.state.phase, SailingPhaseView.fishing);
      expect(bloc.state.session!.actualFishingPoint!.lat, -8.5);

      locations.add(
        _position(fishing.add(const Duration(seconds: 10)), -8.42, 112.62),
      );
      await _flush();
      clock = returned;
      await bloc.finishSailing();
      expect(bloc.state.phase, SailingPhaseView.completed);
      final input = bloc.state.session!.toTripInput(fuelLiters: 5, catchKg: 0);
      expect(input.clientTripId, id);
      expect(input.toJson(now: returned)['source'], 'sailing');
      expect(input.fishingPoints.single.flagSource, 'user_confirmed');
      expect(input.fishingPoints.single.startedAt, fishing);
      expect(input.departedAt, departure.add(const Duration(seconds: 10)));
      expect(input.track, hasLength(3));
      expect(input.returnPoint, isNull);
      expect(
        bloc.state.session!.returnLocation!.kind,
        SailingReturnLocationKind.lastKnown,
      );
      expect(bloc.state.session!.returnLocation!.point.lat, -8.42);
      await bloc.close();
    },
  );

  test(
    'planned point is not treated as actual; empty trip is preserved',
    () async {
      final store = _MemorySailingStore();
      final bloc = SailingBloc(
        store: store,
        locationSource: _FakeLocationSource(),
        now: () => departure,
      );
      await bloc.startSailing(
        ownerId: 'owner-1',
        departure: const SailingPoint(lat: -8.4, lng: 112.6),
        plannedFishingPoint: const SailingPoint(lat: -8.5, lng: 112.7),
      );
      await bloc.finishSailing();
      expect(bloc.state.phase, SailingPhaseView.completed);
      expect(store.session, isNotNull);
      expect(store.session!.plannedFishingPoint, isNotNull);
      expect(store.session!.actualFishingPoint, isNull);
      expect(
        () => store.session!.toTripInput(fuelLiters: 1, catchKg: 0),
        throwsStateError,
      );
      await bloc.close();
    },
  );

  test(
    'location filter rejects invalid, inaccurate, stale and duplicate fixes',
    () async {
      final store = _MemorySailingStore();
      final source = _FakeLocationSource();
      final bloc = SailingBloc(
        store: store,
        locationSource: source,
        now: () => departure,
      );
      await bloc.startSailing(
        ownerId: 'owner-1',
        departure: const SailingPoint(lat: -8.4, lng: 112.6),
      );
      source.add(_position(departure, -8.4, 112.6, accuracy: 101));
      source.add(_position(departure, 999, 112.6));
      source.add(
        _position(departure.subtract(const Duration(minutes: 6)), -8.4, 112.6),
      );
      source.add(_position(departure, -8.4, 112.6));
      source.add(_position(departure, -8.41, 112.61));
      await _flush();
      expect(bloc.state.session!.track, hasLength(1));
      expect(bloc.state.session!.track.single.point.lat, -8.4);
      await bloc.close();
    },
  );

  test(
    'at-departure GPS is replaced by latest fix and stale wait fixes drop',
    () async {
      final store = _MemorySailingStore();
      final source = _FakeLocationSource();
      var clock = departure;
      final bloc = SailingBloc(
        store: store,
        locationSource: source,
        now: () => clock,
      );
      await bloc.startSailing(
        ownerId: 'owner-1',
        departure: const SailingPoint(lat: -8.4, lng: 112.6),
      );
      source.add(
        _position(departure.add(const Duration(seconds: 1)), -8.4, 112.6),
      );
      await _flush();
      source.add(
        _position(departure.add(const Duration(seconds: 2)), -8.41, 112.61),
      );
      await _flush();
      expect(bloc.state.session!.track, hasLength(1));

      clock = departure.add(const Duration(minutes: 15));
      await bloc.markDeparted();
      expect(bloc.state.session!.track, isEmpty);

      source.add(
        _position(
          clock.add(const Duration(seconds: 1)),
          -8.42,
          112.62,
          speed: -1,
        ),
      );
      await _flush();
      source.add(
        _position(
          clock.add(const Duration(seconds: 2)),
          -8.43,
          112.63,
          speed: 101,
        ),
      );
      await _flush();
      expect(bloc.state.session!.track, hasLength(1));
      expect(bloc.state.session!.track.single.speedMs, isNull);
      await bloc.close();
    },
  );

  test('pause discards fixes delivered after the pause action', () async {
    final store = _MemorySailingStore();
    final source = _FakeLocationSource();
    final bloc = SailingBloc(
      store: store,
      locationSource: source,
      now: () => departure,
    );
    await bloc.startSailing(
      ownerId: 'owner-1',
      departure: const SailingPoint(lat: -8.4, lng: 112.6),
    );
    await bloc.pauseTracking();
    source.add(
      _position(departure.add(const Duration(seconds: 1)), -8.4, 112.6),
    );
    await _flush();
    expect(bloc.state.locationStatus, SailingLocationStatus.paused);
    expect(bloc.state.session!.track, isEmpty);
    await bloc.close();
  });

  test('GPS stream failure marks loss and can explicitly recover', () async {
    final store = _MemorySailingStore();
    final source = _FakeLocationSource();
    final bloc = SailingBloc(
      store: store,
      locationSource: source,
      now: () => departure,
    );
    await bloc.startSailing(
      ownerId: 'owner-1',
      departure: const SailingPoint(lat: -8.4, lng: 112.6),
    );
    source.controller.addError(StateError('GPS lost'));
    await _flush();
    expect(bloc.state.locationStatus, SailingLocationStatus.lost);
    source.permission = SailingPermission.granted;
    await bloc.resumeTracking();
    expect(bloc.state.locationStatus, SailingLocationStatus.available);
    await source.controller.close();
    await _flush();
    expect(bloc.state.locationStatus, SailingLocationStatus.lost);
    await bloc.resumeTracking();
    expect(bloc.state.locationStatus, SailingLocationStatus.available);
    await bloc.close();
  });

  test(
    'account-scoped store failure stops recording and preserves last save',
    () async {
      final store = _MemorySailingStore();
      final source = _FakeLocationSource();
      final bloc = SailingBloc(
        store: store,
        locationSource: source,
        now: () => departure,
      );
      await bloc.startSailing(
        ownerId: 'owner-1',
        departure: const SailingPoint(lat: -8.4, lng: 112.6),
      );
      store.failNextSave = true;
      final before = store.session!.track;
      source.add(
        _position(departure.add(const Duration(seconds: 1)), -8.41, 112.61),
      );
      await _flush();
      expect(bloc.state.error, isNotNull);
      expect(bloc.state.locationStatus, SailingLocationStatus.lost);
      expect(store.session!.track, before);
      await bloc.close();
    },
  );

  test(
    'recovery preserves client id and account isolation blocks overwrite',
    () async {
      final store = _MemorySailingStore();
      final source = _FakeLocationSource();
      final first = SailingBloc(
        store: store,
        locationSource: source,
        now: () => departure,
      );
      await first.startSailing(
        ownerId: 'owner-1',
        departure: const SailingPoint(lat: -8.4, lng: 112.6),
      );
      final id = first.state.session!.clientTripId;
      await first.close();

      final restored = SailingBloc(
        store: store,
        locationSource: source,
        now: () => departure.add(const Duration(minutes: 1)),
      );
      await restored.restoreSession();
      expect(restored.state.session!.clientTripId, id);
      expect(restored.state.locationStatus, SailingLocationStatus.paused);
      await restored.startSailing(
        ownerId: 'owner-2',
        departure: const SailingPoint(lat: -8.4, lng: 112.6),
      );
      expect(restored.state.session!.clientTripId, id);
      expect(restored.state.error, contains('Selesaikan atau hapus'));
      await restored.close();
    },
  );
}

SailingPosition _position(
  DateTime time,
  double lat,
  double lng, {
  double accuracy = 5,
  double speed = 2,
}) => SailingPosition(
  point: SailingPoint(lat: lat, lng: lng),
  recordedAt: time,
  accuracyM: accuracy,
  speedMs: speed,
);

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(const Duration(milliseconds: 5));
}

class _FakeLocationSource implements SailingLocationSource {
  StreamController<SailingPosition>? _controller;
  StreamController<SailingPosition> get controller => _controller!;
  SailingPermission permission = SailingPermission.granted;

  void add(SailingPosition position) => controller.add(position);

  @override
  Future<SailingPermission> requestForegroundPermission() async => permission;

  @override
  Stream<SailingPosition> get positions {
    _controller = StreamController<SailingPosition>.broadcast();
    return controller.stream;
  }
}

class _MemorySailingStore implements SailingSessionStore {
  SailingSession? session;
  bool failNextSave = false;

  @override
  Future<SailingSession?> read() async => session;

  @override
  Future<void> save(SailingSession value) async {
    if (failNextSave) {
      failNextSave = false;
      throw const SailingStoreFailure('disk full');
    }
    if (session != null && session!.ownerId != value.ownerId) {
      throw const SailingStoreFailure('wrong account');
    }
    session = SailingSession.fromJson(value.toJson());
  }

  @override
  Future<void> clear({required String clientTripId}) async {
    if (session?.clientTripId != clientTripId) {
      throw const SailingStoreFailure('wrong session');
    }
    session = null;
  }
}
