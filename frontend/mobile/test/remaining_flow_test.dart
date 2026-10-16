import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reefish_mobile/src/app/journey_entry.dart';
import 'package:reefish_mobile/src/journey/domain/journey_models.dart';
import 'package:reefish_mobile/src/journey/domain/journey_repository.dart';
import 'package:reefish_mobile/src/sailing/domain/sailing_location_source.dart';
import 'package:reefish_mobile/src/sailing/domain/sailing_session.dart';
import 'package:reefish_mobile/src/sailing/domain/sailing_session_store.dart';

void main() {
  for (final failFirst in [false, true]) {
    testWidgets(
      'restored sailing summary ${failFirst ? 'retries the same payload' : 'clears only after ACK'}',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final now = DateTime.now().toUtc();
        const point = SailingPoint(lat: -8.447, lng: 112.683);
        const id = '30000000-0000-4000-8000-000000000003';
        final session = SailingSession(
          ownerId: 'preview-anonymous',
          clientTripId: id,
          phase: SailingPhase.completed,
          departure: point,
          startedAt: now.subtract(const Duration(hours: 1)),
          departedAt: now.subtract(const Duration(minutes: 59, seconds: 17)),
          actualFishingPoint: point,
          fishingStartedAt: now.subtract(const Duration(minutes: 30)),
          fishingEndedAt: now.subtract(const Duration(minutes: 2)),
          returnedAt: now.subtract(const Duration(minutes: 1, seconds: 11)),
          locationStatus: SailingLocationStatus.paused,
          track: [
            SailingTrackPoint(
              seq: 0,
              point: point,
              recordedAt: now.subtract(const Duration(minutes: 58)),
            ),
            SailingTrackPoint(
              seq: 1,
              point: point,
              recordedAt: now.subtract(const Duration(minutes: 2)),
            ),
          ],
        );
        final store = _SessionStore(session);
        final repository = _Repository(failFirst);
        await tester.pumpWidget(
          MaterialApp(
            home: JourneyEntry(
              repository: repository,
              draftStore: _DraftStore(),
              sailingSessionStore: store,
              sailingLocationSource: _NoGps(),
            ),
          ),
        );
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.text('Catat Perjalanan Melaut'), findsOneWidget);
        for (final entry in {
          'journey-fuel': '4',
          'journey-catch': '12',
        }.entries) {
          await tester.enterText(
            find.descendant(
              of: find.byKey(ValueKey(entry.key)),
              matching: find.byType(TextField),
            ),
            entry.value,
          );
        }
        await tester.tap(find.byKey(const ValueKey('journey-submit')));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        if (failFirst) {
          expect(store.clearedId, isNull);
          expect(find.text('Coba kirim lagi'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('journey-submit')));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(repository.inputs, hasLength(2));
          expect(repository.inputs[0].toJson(), repository.inputs[1].toJson());
        }
        final input = repository.inputs.first;
        expect(input.clientTripId, id);
        expect(input.source, JourneyTripSource.sailing);
        expect(input.departedAt, session.departedAt);
        expect(input.returnedAt, session.returnedAt);
        expect(input.track, hasLength(2));
        expect(store.clearedId, id);
        expect(store.session, isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}

class _SessionStore implements SailingSessionStore {
  _SessionStore(this.session);
  SailingSession? session;
  String? clearedId;
  @override
  Future<SailingSession?> read() async => session;
  @override
  Future<void> save(SailingSession value) async {
    session = value;
  }

  @override
  Future<void> clear({required String clientTripId}) async {
    clearedId = clientTripId;
    session = null;
  }
}

class _DraftStore implements JourneyDraftStore {
  JourneyDraft? value;
  @override
  Future<JourneyDraft?> read() async => value;
  @override
  Future<void> save(JourneyDraft draft) async {
    value = draft;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

class _NoGps implements SailingLocationSource {
  @override
  Future<SailingPermission> requestForegroundPermission() =>
      throw StateError('A completed record must not resume GPS');
  @override
  Stream<SailingPosition> get positions => const Stream.empty();
}

class _Repository implements JourneyRepository {
  _Repository(this.failFirst);
  final bool failFirst;
  final inputs = <JourneyTripInput>[];
  static const profile = JourneyProfile(
    id: 'preview-anonymous',
    nextStep: JourneyStep.done,
    role: 'nelayan',
  );
  static const history = JourneyTripHistory(trips: [], total: 0);
  @override
  Future<JourneyProfile> getMe() async => profile;
  @override
  Future<JourneyDashboard> loadDashboard({int tripLimit = 5}) async =>
      const JourneyDashboard(profile: profile, history: history);
  @override
  Future<JourneyTripSubmission> submitTrip(JourneyTripInput input) async {
    inputs.add(input);
    if (failFirst && inputs.length == 1) {
      throw const JourneyFailure(
        code: JourneyFailureCode.backend,
        message: 'Synthetic network failure',
      );
    }
    return JourneyTripSubmission(
      trip: JourneyTripDetail(
        id: '40000000-0000-4000-8000-000000000004',
        source: 'sailing',
        departedAt: input.departedAt,
        returnedAt: input.returnedAt,
        fuelLiters: input.fuelLiters,
        catchKg: input.catchKg,
      ),
      onboarded: true,
      replay: inputs.length > 1,
    );
  }

  @override
  Future<JourneyBoat> createBoat(JourneyBoatInput input) =>
      throw UnimplementedError();
  @override
  Future<JourneyTripDetail> getTripDetail(
    String id, {
    String track = 'simplified',
  }) => throw UnimplementedError();
  @override
  Future<JourneyTripHistory> listTrips({
    int page = 1,
    int limit = 20,
    String? from,
    String? to,
    JourneyTripSource? source,
    String sort = '-departed_at',
  }) async => history;
}
