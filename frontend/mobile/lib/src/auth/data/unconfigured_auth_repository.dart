import '../domain/auth_failure.dart';
import '../domain/auth_repository.dart';

class UnconfiguredAuthRepository implements AuthRepository {
  const UnconfiguredAuthRepository();

  @override
  AuthSessionStatus get currentSessionStatus => AuthSessionStatus.signedOut;

  @override
  Stream<AuthSessionStatus> get sessionChanges =>
      Stream<AuthSessionStatus>.value(currentSessionStatus);

  @override
  Future<AuthResult> createAccount({
    required String phoneE164,
    required String password,
  }) => _notConfigured();

  @override
  Future<AuthResult> login({
    required String phoneE164,
    required String password,
  }) => _notConfigured();

  @override
  Future<void> verifyPhone({required String phoneE164, required String otp}) =>
      _notConfigured();

  @override
  Future<void> resendPhoneOtp({required String phoneE164}) => _notConfigured();

  @override
  Future<void> signOut() => _notConfigured();

  Future<T> _notConfigured<T>() async {
    throw const AuthFailure(AuthFailureCode.notConfigured);
  }
}
