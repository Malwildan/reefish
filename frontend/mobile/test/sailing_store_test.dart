import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reefish_mobile/src/sailing/data/shared_preferences_sailing_session_store.dart';
import 'package:reefish_mobile/src/sailing/domain/sailing_session.dart';
import 'package:reefish_mobile/src/sailing/domain/sailing_session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('session survives reload under the owning account key only', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesSailingSessionStore(
      preferences: preferences,
      ownerId: 'owner-1',
    );
    final session = SailingSession(
      ownerId: 'owner-1',
      clientTripId: '10000000-0000-4000-8000-000000000001',
      phase: SailingPhase.atDeparture,
      departure: const SailingPoint(lat: -8.4, lng: 112.6),
      startedAt: DateTime.utc(2026, 10, 16),
      track: const [],
      locationStatus: SailingLocationStatus.paused,
    );
    await store.save(session);

    final reloaded = await SharedPreferencesSailingSessionStore(
      preferences: preferences,
      ownerId: 'owner-1',
    ).read();
    expect(reloaded!.clientTripId, session.clientTripId);
    expect(
      await SharedPreferencesSailingSessionStore(
        preferences: preferences,
        ownerId: 'owner-2',
      ).read(),
      isNull,
    );
  });

  test('clear requires the matching acknowledged trip id', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesSailingSessionStore(
      preferences: preferences,
      ownerId: 'owner-1',
    );
    const id = '10000000-0000-4000-8000-000000000001';
    await store.save(
      SailingSession(
        ownerId: 'owner-1',
        clientTripId: id,
        phase: SailingPhase.atDeparture,
        departure: const SailingPoint(lat: -8.4, lng: 112.6),
        startedAt: DateTime.utc(2026, 10, 16),
        track: const [],
        locationStatus: SailingLocationStatus.paused,
      ),
    );
    await expectLater(
      store.clear(clientTripId: '20000000-0000-4000-8000-000000000002'),
      throwsA(isA<SailingStoreFailure>()),
    );
    expect(await store.read(), isNotNull);
    await store.clear(clientTripId: id);
    expect(await store.read(), isNull);
  });
}
