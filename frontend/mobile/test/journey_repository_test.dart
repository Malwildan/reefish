import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reefish_mobile/src/journey/data/shared_preferences_journey_draft_store.dart';
import 'package:reefish_mobile/src/journey/data/supabase_journey_repository.dart';
import 'package:reefish_mobile/src/journey/domain/journey_models.dart';
import 'package:reefish_mobile/src/journey/domain/journey_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('SupabaseJourneyRepository', () {
    test(
      'loads profile and paginated history as typed dashboard readmodels',
      () async {
        final client = await _authenticatedClient((request) async {
          if (request.url.path.endsWith('/api_me')) {
            return _json({
              'id': 'owner-1',
              'name': 'Nelayan',
              'role': 'nelayan',
              'onboarded': true,
              'next_step': 'done',
              'boat': {
                'id': 'boat-1',
                'engine_hp': 15,
                'boat_length_m': 7,
                'home_port': {'lat': -8.4, 'lng': 112.7},
              },
              'stats': {
                'trip_count': 2,
                'baseline_fuel_liters': 'unavailable',
                'baseline_catch_kg': null,
              },
            });
          }
          if (request.url.path.endsWith('/api_list_trips')) {
            return _json({
              'data': [
                {
                  'id': 'trip-1',
                  'source': 'manual',
                  'fuel_liters': 14.2,
                  'catch_kg': 22.0,
                  'fuel_efficiency_pct': null,
                  'total_distance_km': 'unknown',
                },
              ],
              'meta': {'page': 1, 'limit': 5, 'total': 2},
              'summary': {
                'trip_count': 2,
                'total_catch_kg': 41.0,
                'total_fuel_liters': 28.0,
                'avg_catch_per_liter': 1.46,
              },
            });
          }
          fail('Unexpected RPC ${request.url.path}');
        });

        final dashboard = await SupabaseJourneyRepository(
          client: client,
        ).loadDashboard(tripLimit: 5);

        expect(dashboard.profile.id, 'owner-1');
        expect(dashboard.profile.nextStep, JourneyStep.done);
        expect(dashboard.profile.boat?.engineHp, 15);
        expect(dashboard.profile.stats?.baselineFuelLiters, isNull);
        expect(dashboard.history.trips.single.fuelLiters, 14.2);
        expect(dashboard.history.trips.single.fuelEfficiencyPct, isNull);
        expect(dashboard.history.trips.single.totalDistanceKm, isNull);
        expect(dashboard.history.averageCatchPerLiter, 1.46);
        await client.dispose();
      },
    );

    test(
      'wraps create boat and trip inputs in p and retries with same client id',
      () async {
        final trip = _trip();
        final requests = <http.Request>[];
        var attempts = 0;
        final client = await _authenticatedClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/api_create_boat')) {
            return _json({
              'id': 'boat-1',
              'engine_hp': 20,
              'boat_length_m': 8,
              'fuel_type': 'solar',
              'home_port': {'lat': -8.4, 'lng': 112.7},
              'is_default': true,
            });
          }
          if (request.url.path.endsWith('/api_post_trip')) {
            attempts++;
            final sent = jsonDecode(request.body) as Map<String, dynamic>;
            final payload = sent['p'] as Map<String, dynamic>;
            expect(payload['client_trip_id'], trip.clientTripId);
            expect(payload['source'], 'manual');
            expect(payload['fishing_points'][0]['lat'], -8.5);
            expect(payload['fishing_points'][0]['lng'], 112.8);
            expect(payload.containsKey('grid_id'), isFalse);
            expect(
              payload['fishing_points'][0].containsKey('grid_id'),
              isFalse,
            );
            return _json({
              'trip': {'id': 'trip-1', 'source': 'manual'},
              'user': {'onboarded': true},
              'recommendations': null,
              'replay': attempts > 1,
            });
          }
          fail('Unexpected RPC ${request.url.path}');
        });
        final repository = SupabaseJourneyRepository(
          client: client,
          now: DateTime.now,
        );
        final boat = await repository.createBoat(
          const JourneyBoatInput(
            engineHp: 20,
            boatLengthM: 8,
            homePort: JourneyLatLng(lat: -8.4, lng: 112.7),
          ),
        );
        final first = await repository.submitTrip(trip);
        final retry = await repository.submitTrip(trip);

        expect(boat.id, 'boat-1');
        expect(first.replay, isFalse);
        expect(retry.replay, isTrue);
        expect(requests.map((request) => request.url.path), [
          '/rest/v1/rpc/api_create_boat',
          '/rest/v1/rpc/api_post_trip',
          '/rest/v1/rpc/api_post_trip',
        ]);
        expect(requests[0].headers['authorization'], startsWith('Bearer '));
        expect(jsonDecode(requests[0].body), {
          'p': {
            'name': null,
            'engine_hp': 20.0,
            'boat_length_m': 8.0,
            'fuel_type': 'solar',
            'home_port': {'lat': -8.4, 'lng': 112.7},
          },
        });
        await client.dispose();
      },
    );

    test(
      'maps missing hosted RPC to API unavailable and no session to auth required',
      () async {
        final client = await _authenticatedClient(
          (request) async => _json({
            'code': 'PGRST202',
            'message': 'Could not find the function public.api_me',
            'details': null,
            'hint': 'Perhaps you meant another function',
          }, statusCode: 404),
        );
        final repository = SupabaseJourneyRepository(client: client);

        await expectLater(
          repository.getMe(),
          throwsA(
            isA<JourneyFailure>().having(
              (failure) => failure.code,
              'code',
              JourneyFailureCode.apiNotAvailable,
            ),
          ),
        );
        await client.dispose();

        final signedOut = _client((_) async => fail('Should not call network'));
        await expectLater(
          SupabaseJourneyRepository(client: signedOut).getMe(),
          throwsA(
            isA<JourneyFailure>().having(
              (failure) => failure.code,
              'code',
              JourneyFailureCode.authenticationRequired,
            ),
          ),
        );
        await signedOut.dispose();
      },
    );

    test(
      'maps known trip validation RPC codes to editable validation failures',
      () async {
        final client = await _authenticatedClient(
          (request) async => _json({
            'code': 'P0001',
            'message': 'OUT_OF_PILOT',
            'details': '{"points":[0]}',
            'hint': 'Pilih titik di area uji coba.',
          }, statusCode: 400),
        );
        final repository = SupabaseJourneyRepository(client: client);

        await expectLater(
          repository.submitTrip(_trip()),
          throwsA(
            isA<JourneyFailure>()
                .having(
                  (failure) => failure.code,
                  'code',
                  JourneyFailureCode.validation,
                )
                .having(
                  (failure) => (failure.details as Map)['backendCode'],
                  'backendCode',
                  'OUT_OF_PILOT',
                ),
          ),
        );
        await client.dispose();
      },
    );

    test('validates boat and trip limits before any RPC request', () async {
      var requests = 0;
      final client = await _authenticatedClient((_) async {
        requests++;
        return _json({});
      });
      final repository = SupabaseJourneyRepository(
        client: client,
        now: () => DateTime.utc(2026, 10, 16, 12),
      );

      await expectLater(
        repository.createBoat(
          const JourneyBoatInput(
            engineHp: 501,
            boatLengthM: 7,
            homePort: JourneyLatLng(lat: -8.4, lng: 112.7),
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.submitTrip(_trip(fuelLiters: 0)),
        throwsArgumentError,
      );
      await expectLater(
        repository.submitTrip(_trip(catchKg: 5001)),
        throwsArgumentError,
      );
      await expectLater(
        repository.submitTrip(
          _trip(returnedAt: DateTime.utc(2026, 10, 19, 12, 11)),
        ),
        throwsArgumentError,
      );
      expect(requests, 0);
      await client.dispose();
    });
  });

  test(
    'pending draft is account scoped and keeps its id across restore',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPreferencesJourneyDraftStore(
        preferences: prefs,
        ownerId: 'owner-a',
      );
      final trip = _trip();
      await store.save(JourneyDraft(ownerId: 'owner-a', trip: trip));

      final restored = await store.read();
      expect(restored?.ownerId, 'owner-a');
      expect(restored?.trip.clientTripId, trip.clientTripId);
      expect(
        restored?.trip.toJson(now: trip.returnedAt)['grid_id'],
        isNull,
      );
      await expectLater(
        store.save(JourneyDraft(ownerId: 'owner-b', trip: trip)),
        throwsArgumentError,
      );
      await store.delete();
      expect(await store.read(), isNull);
    },
  );

  test(
    'malformed pending payload with an empty client id is preserved as storage failure',
    () async {
      SharedPreferences.setMockInitialValues({
        'reefish.journey-draft.v1.owner-a': jsonEncode({
          'owner_id': 'owner-a',
          'trip': {
            'client_trip_id': '',
            'source': 'manual',
            'departed_at': '2026-10-16T10:00:00Z',
            'returned_at': '2026-10-16T12:00:00Z',
            'fuel_liters': 12,
            'catch_kg': 20,
            'fishing_points': [
              {'lat': -8.5, 'lng': 112.8},
            ],
          },
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPreferencesJourneyDraftStore(
        preferences: prefs,
        ownerId: 'owner-a',
      );

      await expectLater(
        store.read(),
        throwsA(
          isA<JourneyFailure>().having(
            (failure) => failure.code,
            'code',
            JourneyFailureCode.storage,
          ),
        ),
      );
      expect(prefs.getString('reefish.journey-draft.v1.owner-a'), isNotNull);
    },
  );
}

JourneyTripInput _trip({
  double fuelLiters = 12,
  double catchKg = 20,
  DateTime? returnedAt,
}) {
  final endedAt =
      returnedAt ?? DateTime.now().toUtc().subtract(const Duration(minutes: 2));
  return JourneyTripInput(
    clientTripId: 'c0ffee00-0000-4000-8000-000000000001',
    source: JourneyTripSource.manual,
    departedAt: endedAt.subtract(const Duration(hours: 2)),
    returnedAt: endedAt,
    fuelLiters: fuelLiters,
    catchKg: catchKg,
    fishingPoints: const [
      JourneyFishingPointInput(point: JourneyLatLng(lat: -8.5, lng: 112.8)),
    ],
  );
}

SupabaseClient _client(Future<http.Response> Function(http.Request) handler) =>
    SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test-key',
      httpClient: MockClient((request) async {
        final response = await handler(request);
        return http.Response(
          response.body,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );

Future<SupabaseClient> _authenticatedClient(
  Future<http.Response> Function(http.Request) handler,
) async {
  final client = _client((request) async {
    if (request.url.path == '/auth/v1/token') {
      return _json({
        'access_token': 'test-access-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'refresh_token': 'test-refresh-token',
        'user': {
          'id': 'owner-1',
          'aud': 'authenticated',
          'role': 'authenticated',
          'phone': '+6281234567890',
          'app_metadata': {
            'provider': 'phone',
            'providers': ['phone'],
          },
          'user_metadata': {},
          'created_at': '2026-10-16T00:00:00Z',
        },
      });
    }
    return handler(request);
  });
  await client.auth.signInWithPassword(
    phone: '+6281234567890',
    password: 'test-password',
  );
  return client;
}

http.Response _json(Object body, {int statusCode = 200}) => http.Response(
  jsonEncode(body),
  statusCode,
  headers: {'content-type': 'application/json'},
);
