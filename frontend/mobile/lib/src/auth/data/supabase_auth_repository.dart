import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/auth_failure.dart';
import '../domain/auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  AuthSessionStatus get currentSessionStatus =>
      _sessionStatus(_client.auth.currentSession);

  @override
  Stream<AuthSessionStatus> get sessionChanges => _watchSession();

  Stream<AuthSessionStatus> _watchSession() =>
      Stream<AuthSessionStatus>.multi((controller) {
        // Subscribe before emitting the snapshot so no auth event is lost
        // between the initial value and listening for subsequent changes.
        final subscription = _client.auth.onAuthStateChange.listen(
          (state) {
            if (state.event == AuthChangeEvent.signedIn ||
                state.event == AuthChangeEvent.signedOut) {
              controller.add(_sessionStatus(state.session));
            }
          },
          onError: (Object _, StackTrace __) {
            // A transient refresh failure is not a new sign-in or sign-out.
            // Keep the route and in-progress form without exposing diagnostics.
          },
        );
        controller.onCancel = subscription.cancel;
        controller.add(currentSessionStatus);
      });

  @override
  Future<AuthResult> createAccount({
    required String phoneE164,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signUp(
        phone: phoneE164,
        password: password,
      );
      if (response.user == null) {
        throw const AuthFailure(AuthFailureCode.unknown);
      }
      return response.session == null
          ? AuthResult.verificationRequired
          : AuthResult.authenticated;
    } on AuthException catch (error) {
      throw _mapAuthError(error);
    }
  }

  @override
  Future<AuthResult> login({
    required String phoneE164,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        phone: phoneE164,
        password: password,
      );
      if (response.session == null) {
        throw const AuthFailure(AuthFailureCode.phoneVerificationRequired);
      }
      return AuthResult.authenticated;
    } on AuthFailure {
      rethrow;
    } on AuthException catch (error) {
      throw _mapAuthError(error);
    }
  }

  @override
  Future<void> verifyPhone({
    required String phoneE164,
    required String otp,
  }) async {
    try {
      final response = await _client.auth.verifyOTP(
        phone: phoneE164,
        token: otp,
        type: OtpType.sms,
      );
      if (response.session == null) {
        throw const AuthFailure(AuthFailureCode.unknown);
      }
    } on AuthFailure {
      rethrow;
    } on AuthException catch (error) {
      throw _mapAuthError(error);
    }
  }

  @override
  Future<void> resendPhoneOtp({required String phoneE164}) async {
    try {
      await _client.auth.resend(phone: phoneE164, type: OtpType.sms);
    } on AuthException catch (error) {
      throw _mapAuthError(error);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } on AuthException catch (error) {
      throw _mapAuthError(error);
    }
  }

  AuthFailure _mapAuthError(AuthException error) {
    final code = error.code?.toLowerCase();
    final message = error.message.toLowerCase();
    if (code == 'phone_not_confirmed' ||
        message.contains('phone not confirmed')) {
      return const AuthFailure(AuthFailureCode.phoneVerificationRequired);
    }
    if (code == 'phone_provider_disabled' ||
        message.contains('phone provider is disabled')) {
      return const AuthFailure(AuthFailureCode.phoneProviderDisabled);
    }
    if (code == 'phone_exists' ||
        code == 'user_already_exists' ||
        message.contains('already registered') ||
        message.contains('already been registered')) {
      return const AuthFailure(AuthFailureCode.phoneAlreadyRegistered);
    }
    if (code == 'invalid_credentials' ||
        code == 'invalid_grant' ||
        message.contains('invalid login credentials')) {
      return const AuthFailure(AuthFailureCode.invalidCredentials);
    }
    if (code == 'otp_expired' ||
        code == 'otp_disabled' ||
        message.contains('invalid token') ||
        message.contains('token has expired')) {
      return const AuthFailure(AuthFailureCode.invalidOtp);
    }
    if (code == 'over_sms_send_rate_limit' ||
        code == 'over_request_rate_limit' ||
        code == 'too_many_requests' ||
        code == 'over_email_send_rate_limit' ||
        message.contains('rate limit') ||
        message.contains('too many requests')) {
      return const AuthFailure(AuthFailureCode.tooManyRequests);
    }
    return const AuthFailure(AuthFailureCode.unknown);
  }

  AuthSessionStatus _sessionStatus(Session? session) => session == null
      ? AuthSessionStatus.signedOut
      : AuthSessionStatus.signedIn;
}
