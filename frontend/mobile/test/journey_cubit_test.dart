import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/journey/domain/journey_models.dart';
import 'package:reefish_mobile/src/journey/domain/journey_repository.dart';
import 'package:reefish_mobile/src/journey/presentation/journey_cubit.dart';

void main() {
  var duplicateCompleted = false;
  final departed = DateTime.utc(2026, 10, 15, 6);
  final returned = DateTime.utc(2026, 10, 15, 10);

  JourneyTripInput trip({String? id}) => JourneyTripInput(
    clientTripId: id,
    source: JourneyTripSource.onboarding,
    departure: const JourneyLatLng(lat: -8.4, lng: 112.6),
    returnPoint: const JourneyLatLng(lat: -8.4, lng: 112.6),
    departedAt: departed,
    returnedAt: returned,
    fuelLiters: 12,
    catchKg: 8,
    fishingPoints: const [
      JourneyFishingPointInput(point: JourneyLatLng(lat: -8.42, lng: 112.65)),
    ],
  );

  test('duplicate submit calls serialize and submit once', () async {
    final repository = _FakeJourneyRepository()
      ..submitGate = Completer<JourneyTripSubmission>();
    final store = _MemoryDraftStore();
    final cubit = JourneyCubit(repository: repository, draftStore: store);
    await cubit.initialize();

    final first = cubit.submitTrip(
      trip(id: '10000000-0000-4000-8000-000000000001'),
    );
    final duplicate = cubit
        .submitTrip(trip(id: '20000000-0000-4000-8000-000000000002'))
        .then((_) => duplicateCompleted = true);
    await Future<void>.delayed(Duration.zero);
    expect(duplicateCompleted, isTrue);
    expect(repository.submitCalls, 1);
    expect(
      repository.submitted.single.clientTripId,
      '10000000-0000-4000-8000-000000000001',
    );

    repository.submitGate!.complete(_submission());
    await Future.wait([first, duplicate]);
    expect(repository.submitCalls, 1);
    expect(cubit.state.phase, JourneyPhase.dashboard);
    expect(store.draft, isNull);
    await cubit.close();
  });

  test(
    'restored draft retries with its original client trip id and payload',
    () async {
      final restored = trip(id: '30000000-0000-4000-8000-000000000003');
      final store = _MemoryDraftStore()
        ..draft = JourneyDraft(ownerId: 'owner-1', trip: restored);
      final repository = _FakeJourneyRepository();
      final cubit = JourneyCubit(repository: repository, draftStore: store);
      await cubit.initialize();
      expect(cubit.state.phase, JourneyPhase.firstTrip);
      expect(
        cubit.state.pendingDraft?.trip.clientTripId,
        '30000000-0000-4000-8000-000000000003',
      );

      await cubit.submitTrip(trip(id: '40000000-0000-4000-8000-000000000004'));
      expect(repository.submitCalls, 1);
      expect(
        repository.submitted.single.clientTripId,
        '30000000-0000-4000-8000-000000000003',
      );
      expect(repository.submitted.single.catchKg, restored.catchKg);
      expect(store.draft, isNull);
      await cubit.close();
    },
  );

  test(
    'acknowledged trip survives dashboard failure without resubmission',
    () async {
      final repository = _FakeJourneyRepository()..dashboardFailures = 1;
      final store = _MemoryDraftStore();
      final cubit = JourneyCubit(repository: repository, draftStore: store);
      await cubit.initialize();
      await cubit.submitTrip(trip(id: '50000000-0000-4000-8000-000000000005'));

      expect(cubit.state.phase, JourneyPhase.error);
      expect(cubit.state.tripSubmitted, isTrue);
      expect(cubit.state.failure?.code, JourneyFailureCode.apiNotAvailable);
      expect(repository.submitCalls, 1);
      expect(store.draft, isNull);

      await cubit.refresh();
      expect(repository.submitCalls, 1);
      expect(repository.dashboardCalls, 2);
      expect(cubit.state.phase, JourneyPhase.dashboard);
      await cubit.close();
    },
  );

  test('only explicit edit action clears a rejected trip draft', () async {
    final repository = _FakeJourneyRepository()
      ..submitFailure = const JourneyFailure(
        code: JourneyFailureCode.validation,
        message: 'Trip is outside the pilot area.',
        details: {'backendCode': 'OUT_OF_PILOT'},
      );
    final store = _MemoryDraftStore();
    final cubit = JourneyCubit(repository: repository, draftStore: store);
    await cubit.initialize();
    await cubit.submitTrip(trip(id: '70000000-0000-4000-8000-000000000007'));

    expect(cubit.state.failure?.code, JourneyFailureCode.validation);
    expect(cubit.state.pendingDraft, isNotNull);
    expect(store.draft, isNotNull);

    await cubit.editRejectedTrip();
    expect(cubit.state.phase, JourneyPhase.firstTrip);
    expect(cubit.state.pendingDraft, isNull);
    expect(store.draft, isNull);
    expect(cubit.state.failure, isNull);
    await cubit.close();
  });

  test(
    'BOAT_REQUIRED refreshes the profile and preserves the pending draft',
    () async {
      final repository = _FakeJourneyRepository()
        ..profileStepAfterFirstRead = JourneyStep.boat
        ..submitFailure = const JourneyFailure(
          code: JourneyFailureCode.backend,
          message: 'Add a boat before recording a trip.',
          details: {'backendCode': 'BOAT_REQUIRED'},
        );
      final store = _MemoryDraftStore();
      final cubit = JourneyCubit(repository: repository, draftStore: store);
      await cubit.initialize();
      await cubit.submitTrip(trip(id: '80000000-0000-4000-8000-000000000008'));

      expect(repository.getMeCalls, 2);
      expect(cubit.state.phase, JourneyPhase.boat);
      expect(cubit.state.pendingDraft, isNotNull);
      expect(store.draft, isNotNull);
      await cubit.close();
    },
  );

  test('getMe API_NOT_AVAILABLE is exposed as a typed journey error', () async {
    final repository = _FakeJourneyRepository()
      ..getMeFailure = const JourneyFailure(
        code: JourneyFailureCode.apiNotAvailable,
        message: 'Journey API is not available.',
      );
    final cubit = JourneyCubit(
      repository: repository,
      draftStore: _MemoryDraftStore(),
    );
    await cubit.initialize();

    expect(cubit.state.phase, JourneyPhase.error);
    expect(cubit.state.failure?.code, JourneyFailureCode.apiNotAvailable);
    await cubit.close();
  });

  test(
    'beginTrip preserves a pending draft and blocks konservatif role',
    () async {
      final restored = trip(id: '60000000-0000-4000-8000-000000000006');
      final store = _MemoryDraftStore()
        ..draft = JourneyDraft(ownerId: 'owner-1', trip: restored);
      final cubit = JourneyCubit(
        repository: _FakeJourneyRepository(),
        draftStore: store,
      );
      await cubit.initialize();
      await cubit.beginTrip();

      expect(cubit.state.phase, JourneyPhase.firstTrip);
      expect(cubit.state.tripSubmitted, isFalse);
      expect(
        cubit.state.pendingDraft?.trip.clientTripId,
        restored.clientTripId,
      );

      final conservative = _FakeJourneyRepository()
        ..role = 'konservatif'
        ..profileStep = JourneyStep.done;
      final conservativeCubit = JourneyCubit(
        repository: conservative,
        draftStore: _MemoryDraftStore(),
      );
      await conservativeCubit.initialize();
      await conservativeCubit.beginTrip();
      expect(conservativeCubit.state.phase, JourneyPhase.error);
      expect(
        conservativeCubit.state.failure?.code,
        JourneyFailureCode.validation,
      );
      await cubit.close();
      await conservativeCubit.close();
    },
  );
}

JourneyTripSubmission _submission() => const JourneyTripSubmission(
  trip: JourneyTripDetail(id: 'server-trip'),
  onboarded: true,
  replay: false,
);

class _MemoryDraftStore implements JourneyDraftStore {
  JourneyDraft? draft;
  @override
  Future<void> save(JourneyDraft value) async => draft = value;
  @override
  Future<JourneyDraft?> read() async => draft;
  @override
  Future<void> delete() async => draft = null;
}

class _FakeJourneyRepository implements JourneyRepository {
  String? role;
  JourneyStep profileStep = JourneyStep.firstTrip;
  JourneyStep? profileStepAfterFirstRead;
  JourneyFailure? getMeFailure;
  int dashboardFailures = 0;
  int getMeCalls = 0;
  int dashboardCalls = 0;
  int submitCalls = 0;
  Completer<JourneyTripSubmission>? submitGate;
  JourneyFailure? submitFailure;
  final submitted = <JourneyTripInput>[];

  @override
  Future<JourneyProfile> getMe() async {
    getMeCalls++;
    if (getMeFailure case final failure?) throw failure;
    final step = getMeCalls > 1
        ? profileStepAfterFirstRead ?? profileStep
        : profileStep;
    return _profile(step, role: role);
  }

  @override
  Future<JourneyBoat> createBoat(JourneyBoatInput input) async =>
      const JourneyBoat(
        id: 'boat-1',
        engineHp: 15,
        boatLengthM: 7,
        fuelType: 'solar',
        homePort: JourneyLatLng(lat: -8.4, lng: 112.7),
        isDefault: true,
      );

  @override
  Future<JourneyTripSubmission> submitTrip(JourneyTripInput input) {
    submitCalls++;
    submitted.add(input);
    if (submitFailure case final failure?) return Future.error(failure);
    return submitGate?.future ?? Future.value(_submission());
  }

  @override
  Future<JourneyDashboard> loadDashboard({int tripLimit = 5}) async {
    dashboardCalls++;
    if (dashboardFailures > 0) {
      dashboardFailures--;
      throw const JourneyFailure(
        code: JourneyFailureCode.apiNotAvailable,
        message: 'Dashboard endpoint unavailable.',
      );
    }
    return JourneyDashboard(
      profile: _profile(JourneyStep.done, role: role),
      history: const JourneyTripHistory(trips: []),
    );
  }

  @override
  Future<JourneyTripHistory> listTrips({
    int page = 1,
    int limit = 20,
    String? from,
    String? to,
    JourneyTripSource? source,
    String sort = '-departed_at',
  }) async => const JourneyTripHistory(trips: []);

  @override
  Future<JourneyTripDetail> getTripDetail(
    String id, {
    String track = 'simplified',
  }) async => const JourneyTripDetail(id: 'trip');
}

JourneyProfile _profile(JourneyStep step, {String? role}) =>
    JourneyProfile(id: 'owner-1', role: role, nextStep: step);
