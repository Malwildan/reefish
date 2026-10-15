import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/auth/data/unconfigured_auth_repository.dart';
import 'package:reefish_mobile/src/auth/domain/auth_repository.dart';
import 'package:reefish_mobile/src/auth/domain/indonesian_phone_number.dart';
import 'package:reefish_mobile/src/auth/presentation/auth_cubit.dart';

void main() {
  group('IndonesianPhoneNumber.normalize', () {
    test('normalizes supported formats and rejects malformed numbers', () {
      for (final input in [
        '081234567890',
        '6281234567890',
        '+62 812-3456-7890'
      ]) {
        final result = IndonesianPhoneNumber.normalize(input);

        expect(result.isValid, isTrue, reason: input);
        expect(result.e164, '+6281234567890', reason: input);
      }
      for (final input in [
        '',
        '0212345678',
        '+1 202 555 0100',
        '0812345',
        'abc081234567890',
        '++6281234567890',
      ]) {
        final result = IndonesianPhoneNumber.normalize(input);

        expect(result.isValid, isFalse, reason: input);
        expect(result.error, isNotEmpty, reason: input);
      }
    });
  });

  group('AuthCubit', () {
    test('dispatches create-account and login with normalized phone numbers',
        () async {
      final repository = _RecordingAuthRepository();
      final cubit = AuthCubit(repository);

      await cubit.submit(
        operation: AuthOperation.createAccount,
        phone: '0812 3456 7890',
        password: 'secure-pass',
      );

      expect(repository.createAccountCalls, 1);
      expect(repository.loginCalls, 0);
      expect(repository.phoneE164, '+6281234567890');
      expect(repository.password, 'secure-pass');
      expect(cubit.state.status, AuthStatus.succeeded);
      await cubit.close();

      final loginCubit = AuthCubit(repository);
      await loginCubit.submit(
        operation: AuthOperation.login,
        phone: '+62 812 3456 7890',
        password: 'secure-pass',
      );
      expect(repository.loginCalls, 1);
      expect(repository.createAccountCalls, 1);
      expect(repository.phoneE164, '+6281234567890');
      expect(loginCubit.state.status, AuthStatus.succeeded);
      await loginCubit.close();
    });

    test('rejects invalid input without calling the repository', () async {
      final repository = _RecordingAuthRepository();
      final cubit = AuthCubit(repository);

      await cubit.submit(
        operation: AuthOperation.createAccount,
        phone: '0212345678',
        password: 'short',
      );

      expect(repository.createAccountCalls, 0);
      expect(repository.loginCalls, 0);
      expect(cubit.state.status, AuthStatus.failed);
      expect(cubit.state.message, contains('ponsel'));
      expect(cubit.state.message, isNot(contains('short')));
      await cubit.close();
    });

    test('reports a safe truthful failure when auth is unconfigured', () async {
      const password = 'private-password';
      final cubit = AuthCubit(const UnconfiguredAuthRepository());

      await cubit.submit(
        operation: AuthOperation.login,
        phone: '081234567890',
        password: password,
      );

      expect(cubit.state.status, AuthStatus.failed);
      expect(cubit.state.message, contains('belum terhubung'));
      expect(cubit.state.message, isNot(contains(password)));
      await cubit.close();
    });

    test('ignores a duplicate submit while the first request is pending',
        () async {
      final repository = _RecordingAuthRepository()
        ..pending = Completer<void>();
      final cubit = AuthCubit(repository);
      final first = cubit.submit(
        operation: AuthOperation.login,
        phone: '081234567890',
        password: 'secure-pass',
      );

      expect(cubit.state.status, AuthStatus.submitting);
      await cubit.submit(
        operation: AuthOperation.login,
        phone: '081234567890',
        password: 'secure-pass',
      );
      expect(repository.loginCalls, 1);

      repository.pending!.complete();
      await first;
      expect(cubit.state.status, AuthStatus.succeeded);
      await cubit.close();
    });

    test('does not emit after the cubit is closed during a pending request',
        () async {
      final repository = _RecordingAuthRepository()
        ..pending = Completer<void>();
      final cubit = AuthCubit(repository);
      final first = cubit.submit(
        operation: AuthOperation.login,
        phone: '081234567890',
        password: 'secure-pass',
      );

      await cubit.close();
      repository.pending!.complete();

      await expectLater(first, completes);
    });
  });
}

class _RecordingAuthRepository implements AuthRepository {
  int createAccountCalls = 0;
  int loginCalls = 0;
  String? phoneE164;
  String? password;
  Completer<void>? pending;

  @override
  Future<void> createAccount({
    required String phoneE164,
    required String password,
  }) {
    createAccountCalls++;
    this.phoneE164 = phoneE164;
    this.password = password;
    return pending?.future ?? Future<void>.value();
  }

  @override
  Future<void> login({
    required String phoneE164,
    required String password,
  }) {
    loginCalls++;
    this.phoneE164 = phoneE164;
    this.password = password;
    return pending?.future ?? Future<void>.value();
  }
}
