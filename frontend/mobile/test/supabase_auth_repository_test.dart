import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reefish_mobile/src/auth/data/supabase_auth_repository.dart';
import 'package:reefish_mobile/src/auth/domain/auth_failure.dart';
import 'package:reefish_mobile/src/auth/domain/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'signup sends phone and password and reports verification without session',
    () async {
      late http.Request capturedRequest;
      final client = _client((request) async {
        capturedRequest = request;
        return _jsonResponse(_user());
      });
      addTearDown(client.dispose);
      final repository = SupabaseAuthRepository(client);

      final result = await repository.createAccount(
        phoneE164: '+6281234567890',
        password: 'private-test-password',
      );

      expect(result, AuthResult.verificationRequired);
      expect(repository.currentSessionStatus, AuthSessionStatus.signedOut);
      expect(capturedRequest.url.path, '/auth/v1/signup');
      expect(capturedRequest.headers['apikey'], 'sb_publishable_test-key');
      expect(jsonDecode(capturedRequest.body), {
        'phone': '+6281234567890',
        'password': 'private-test-password',
        'data': null,
        'gotrue_meta_security': {'captcha_token': null},
        'channel': 'sms',
      });
    },
  );

  test(
    'signup with no user and no session is not treated as pending success',
    () async {
      final client = _client((_) async => _jsonResponse({}));
      addTearDown(client.dispose);
      final repository = SupabaseAuthRepository(client);

      await expectLater(
        repository.createAccount(
          phoneE164: '+6281234567890',
          password: 'private-test-password',
        ),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.code,
            'code',
            AuthFailureCode.unknown,
          ),
        ),
      );
    },
  );

  test('unconfirmed password login becomes an OTP step', () async {
    final client = _client(
      (_) async => _jsonResponse({
        'code': 'phone_not_confirmed',
        'msg': 'Phone not confirmed',
      }, statusCode: 400),
    );
    addTearDown(client.dispose);
    final repository = SupabaseAuthRepository(client);

    await expectLater(
      repository.login(
        phoneE164: '+6281234567890',
        password: 'private-test-password',
      ),
      throwsA(
        isA<AuthFailure>().having(
          (failure) => failure.code,
          'code',
          AuthFailureCode.phoneVerificationRequired,
        ),
      ),
    );
  });

  test(
    'hosted phone_provider_disabled is separate from missing app config',
    () async {
      final client = _client(
        (_) async => _jsonResponse({
          'message': 'Phone provider is disabled',
          'error_code': 'phone_provider_disabled',
        }, statusCode: 422),
      );
      addTearDown(client.dispose);
      final repository = SupabaseAuthRepository(client);

      await expectLater(
        repository.login(
          phoneE164: '+6281234567890',
          password: 'private-test-password',
        ),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.code,
            'code',
            AuthFailureCode.phoneProviderDisabled,
          ),
        ),
      );
    },
  );

  test('OTP response without a session cannot confirm sign in', () async {
    final client = _client((_) async => _jsonResponse({}));
    addTearDown(client.dispose);
    final repository = SupabaseAuthRepository(client);

    await expectLater(
      repository.verifyPhone(phoneE164: '+6281234567890', otp: '123456'),
      throwsA(
        isA<AuthFailure>().having(
          (failure) => failure.code,
          'code',
          AuthFailureCode.unknown,
        ),
      ),
    );
  });

  test(
    'sign in requires a session and sign out clears the local session',
    () async {
      var requestNumber = 0;
      late http.Request logoutRequest;
      final client = _client((request) async {
        requestNumber++;
        if (requestNumber == 1) return _jsonResponse(_authResponse());
        logoutRequest = request;
        return http.Response('', 204);
      });
      addTearDown(client.dispose);
      final repository = SupabaseAuthRepository(client);

      final result = await repository.login(
        phoneE164: '+6281234567890',
        password: 'private-test-password',
      );
      expect(result, AuthResult.authenticated);
      expect(repository.currentSessionStatus, AuthSessionStatus.signedIn);

      await repository.signOut();
      expect(logoutRequest.method, 'POST');
      expect(logoutRequest.url.path, '/auth/v1/logout');
      expect(logoutRequest.url.queryParameters['scope'], 'local');
      expect(repository.currentSessionStatus, AuthSessionStatus.signedOut);
    },
  );

  test(
    'resend uses SMS and turns provider rate limits into a safe failure',
    () async {
      late http.Request capturedRequest;
      final client = _client((request) async {
        capturedRequest = request;
        return _jsonResponse({
          'code': 'over_sms_send_rate_limit',
          'error_code': 'over_sms_send_rate_limit',
          'message': 'rate limit exceeded',
          'msg': 'rate limit exceeded',
        }, statusCode: 429);
      });
      addTearDown(client.dispose);
      final repository = SupabaseAuthRepository(client);

      await expectLater(
        repository.resendPhoneOtp(phoneE164: '+6281234567890'),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.code,
            'code',
            AuthFailureCode.tooManyRequests,
          ),
        ),
      );
      expect(capturedRequest.url.path, '/auth/v1/resend');
      expect(jsonDecode(capturedRequest.body), {
        'phone': '+6281234567890',
        'type': 'sms',
        'gotrue_meta_security': {'captcha_token': null},
      });
    },
  );
}

SupabaseClient _client(Future<http.Response> Function(http.Request) handler) =>
    SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test-key',
      httpClient: MockClient(handler),
    );

http.Response _jsonResponse(Object body, {int statusCode = 200}) =>
    http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _user() => {
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
};

Map<String, dynamic> _authResponse() => {
  'user': _user(),
  'access_token': 'mock-access-token',
  'token_type': 'bearer',
  'expires_in': 3600,
  'refresh_token': 'mock-refresh-token',
};
