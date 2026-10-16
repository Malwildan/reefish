import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reefish_mobile/src/map/data/supabase_grid_policy_repository.dart';
import 'package:reefish_mobile/src/map/data/unconfigured_grid_policy_repository.dart';
import 'package:reefish_mobile/src/map/domain/grid_policy_failure.dart';
import 'package:reefish_mobile/src/map/domain/grid_policy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SupabaseGridPolicyRepository', () {
    test('requires a session before making an RPC request', () async {
      var requestCount = 0;
      final client = _client((_) async {
        requestCount++;
        return _response({});
      });
      addTearDown(client.dispose);

      await expectLater(
        SupabaseGridPolicyRepository(client: client).fetchSnapshot(),
        throwsA(
          isA<GridPolicyFailure>().having(
            (failure) => failure.code,
            'code',
            GridPolicyFailureCode.authenticationRequired,
          ),
        ),
      );
      expect(requestCount, 0);
    });

    test('returns a valid policy snapshot', () async {
      late http.Request rpcRequest;
      final client = await _authenticatedClient((request) async {
        rpcRequest = request;
        return _response(_snapshotJson(), request: request);
      });
      addTearDown(client.dispose);

      final snapshot = await SupabaseGridPolicyRepository(
        client: client,
      ).fetchSnapshot();

      expect(snapshot.version, '7');
      expect(snapshot.locks, isEmpty);
      expect(snapshot.isDemo, isFalse);
      expect(rpcRequest.url.path, '/rest/v1/rpc/get_grid_lock_snapshot');
      expect(jsonDecode(rpcRequest.body), {'p_area_id': 'east-java-pilot'});
    });

    test(
      'treats server time as snapshot metadata, not the client clock',
      () async {
        final client = await _authenticatedClient(
          (request) async => _response(
            _snapshotJson(
              fetchedAt: '2099-10-16T04:00:00.000Z',
              expiresAt: '2099-10-16T04:05:00.000Z',
            ),
            request: request,
          ),
        );
        addTearDown(client.dispose);

        final snapshot = await SupabaseGridPolicyRepository(
          client: client,
        ).fetchSnapshot();

        expect(snapshot.fetchedAt, DateTime.utc(2099, 10, 16, 4));
        expect(snapshot.expiresAt, DateTime.utc(2099, 10, 16, 4, 5));
        expect(
          snapshot.accessFor('unlisted-cell', DateTime.now()),
          GridAccess.unlocked,
        );
      },
    );

    test('maps expired JWT responses to sign-in required', () async {
      final client = await _authenticatedClient(
        (request) async => _response(
          {
            'message': 'JWT expired',
            'code': 'PGRST301',
            'details': null,
            'hint': null,
          },
          statusCode: 401,
          request: request,
        ),
      );
      addTearDown(client.dispose);

      await _expectFailure(
        client,
        GridPolicyFailureCode.authenticationRequired,
      );
    });

    test('maps authorization failures to permission denied', () async {
      final client = await _authenticatedClient(
        (request) async => _response(
          {
            'message': 'permission denied',
            'code': '42501',
            'details': null,
            'hint': null,
          },
          statusCode: 403,
          request: request,
        ),
      );
      addTearDown(client.dispose);

      await _expectFailure(client, GridPolicyFailureCode.permissionDenied);
    });

    test('maps other backend errors to unavailable', () async {
      final client = await _authenticatedClient(
        (request) async => _response(
          {'message': 'database unavailable', 'code': '08006'},
          statusCode: 503,
          request: request,
        ),
      );
      addTearDown(client.dispose);

      await _expectFailure(client, GridPolicyFailureCode.unavailable);
    });

    test('maps malformed policy payloads to invalid response', () async {
      final client = await _authenticatedClient(
        (request) async => _response({'version': '7'}, request: request),
      );
      addTearDown(client.dispose);

      await _expectFailure(client, GridPolicyFailureCode.invalidResponse);
    });

    test('maps transport failures to unavailable', () async {
      final client = await _authenticatedClient((_) async {
        throw http.ClientException('offline');
      });
      addTearDown(client.dispose);

      await _expectFailure(client, GridPolicyFailureCode.unavailable);
    });
  });

  test(
    'unconfigured repository reports a typed configuration failure',
    () async {
      await expectLater(
        const UnconfiguredGridPolicyRepository().fetchSnapshot(),
        throwsA(
          isA<GridPolicyFailure>().having(
            (failure) => failure.code,
            'code',
            GridPolicyFailureCode.notConfigured,
          ),
        ),
      );
    },
  );
}

Future<void> _expectFailure(
  SupabaseClient client,
  GridPolicyFailureCode code,
) async {
  await expectLater(
    SupabaseGridPolicyRepository(client: client).fetchSnapshot(),
    throwsA(
      isA<GridPolicyFailure>()
          .having((failure) => failure.code, 'code', code)
          .having((failure) => failure.userMessage, 'userMessage', isNotEmpty),
    ),
  );
}

SupabaseClient _client(Future<http.Response> Function(http.Request) handler) =>
    SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test-key',
      httpClient: MockClient(handler),
    );

Future<SupabaseClient> _authenticatedClient(
  Future<http.Response> Function(http.Request) handler,
) async {
  final client = _client((request) async {
    if (request.url.path == '/auth/v1/token') {
      return _response(_authResponse(), request: request);
    }
    return handler(request);
  });
  await client.auth.signInWithPassword(
    phone: '+6281234567890',
    password: 'private-test-password',
  );
  return client;
}

http.Response _response(
  Object body, {
  int statusCode = 200,
  http.Request? request,
}) => http.Response(
  jsonEncode(body),
  statusCode,
  request: request,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _snapshotJson({
  String fetchedAt = '2026-10-16T04:00:00.000Z',
  String expiresAt = '2026-10-16T04:05:00.000Z',
}) => {
  'version': '7',
  'fetched_at': fetchedAt,
  'expires_at': expiresAt,
  'is_demo': false,
  'locks': <Object>[],
};

Map<String, dynamic> _authResponse() => {
  'user': {
    'id': 'd07d99e0-2b0a-4b34-9012-4d6f2820e3a0',
    'aud': 'authenticated',
    'role': 'authenticated',
    'phone': '+6281234567890',
    'app_metadata': {
      'provider': 'phone',
      'providers': ['phone'],
    },
    'user_metadata': {},
    'created_at': '2026-10-16T00:00:00.000Z',
    'updated_at': '2026-10-16T00:00:00.000Z',
  },
  'access_token': 'mock-access-token',
  'token_type': 'bearer',
  'expires_in': 3600,
  'refresh_token': 'mock-refresh-token',
};
