import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reefish_mobile/src/app/reefish_app.dart';
import 'package:reefish_mobile/src/auth/data/supabase_auth_repository.dart';
import 'package:reefish_mobile/src/auth/domain/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('restored SDK session opens the signed-in route at startup', (
    tester,
  ) async {
    final client = _client((_) async => http.Response('', 500));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(client.dispose());
    });
    client.auth.stopAutoRefresh();
    await tester.runAsync(
      () => client.auth.recoverSession(jsonEncode(_session(_user('user-a')))),
    );
    final repository = SupabaseAuthRepository(client);

    await tester.pumpWidget(
      ReefishApp(
        authRepository: repository,
        initialPage: ReefishInitialPage.login,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Akun Reefish terhubung'), findsOneWidget);
    expect(find.text('Masuk'), findsNothing);
  });

  test(
    'SDK sign-in events preserve repeated signed-in status for account switch',
    () async {
      var signInCount = 0;
      final client = _client((request) async {
        if (request.url.path != '/auth/v1/token') {
          return http.Response('', 500);
        }
        signInCount++;
        return _jsonResponse(_session(_user('user-$signInCount')));
      });
      addTearDown(client.dispose);
      client.auth.stopAutoRefresh();
      final repository = SupabaseAuthRepository(client);
      final statuses = <AuthSessionStatus>[];
      final subscription = repository.sessionChanges.listen(statuses.add);
      addTearDown(subscription.cancel);

      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < 2; i++) {
        await client.auth.signInWithPassword(
          phone: '+6281234567890',
          password: 'private-test-password',
        );
      }
      await Future<void>.delayed(Duration.zero);

      expect(
        statuses.where((status) => status == AuthSessionStatus.signedIn),
        hasLength(2),
      );
    },
  );

  test('token refresh does not create a new route session status', () async {
    final client = _client(
      (_) async => _jsonResponse(_session(_user('user-a'))),
    );
    addTearDown(client.dispose);
    client.auth.stopAutoRefresh();
    await client.auth.recoverSession(jsonEncode(_session(_user('user-a'))));
    final repository = SupabaseAuthRepository(client);
    final statuses = <AuthSessionStatus>[];
    final subscription = repository.sessionChanges.listen(statuses.add);
    addTearDown(subscription.cancel);
    await Future<void>.delayed(Duration.zero);

    await client.auth.refreshSession();
    await Future<void>.delayed(Duration.zero);

    expect(statuses, [AuthSessionStatus.signedIn]);
  });

  test('transient auth error does not reset the signed-in route', () async {
    final client = _client((_) async => http.Response('', 500));
    addTearDown(client.dispose);
    client.auth.stopAutoRefresh();
    await client.auth.recoverSession(jsonEncode(_session(_user('user-a'))));
    final statuses = <AuthSessionStatus>[];
    final subscription = SupabaseAuthRepository(
      client,
    ).sessionChanges.listen(statuses.add);
    addTearDown(subscription.cancel);
    await Future<void>.delayed(Duration.zero);

    // Exercise the SDK stream error channel without a production request.
    // ignore: invalid_use_of_internal_member
    client.auth.notifyException(
      const AuthException('Temporary fixture outage'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(statuses, [AuthSessionStatus.signedIn]);
    expect(client.auth.currentUser?.id, 'user-a');
  });
}

SupabaseClient _client(Future<http.Response> Function(http.Request) handler) =>
    SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test-key',
      httpClient: MockClient(handler),
    );

http.Response _jsonResponse(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _session(Map<String, dynamic> user) => {
  'user': user,
  'access_token': 'mock-access-token',
  'token_type': 'bearer',
  'expires_in': 3600,
  'expires_at': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600,
  'refresh_token': 'mock-refresh-token',
};

Map<String, dynamic> _user(String id) => {
  'id': id,
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
};
