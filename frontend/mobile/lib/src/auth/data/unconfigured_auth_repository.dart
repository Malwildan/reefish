import '../domain/auth_failure.dart';
import '../domain/auth_repository.dart';

class UnconfiguredAuthRepository implements AuthRepository {
  const UnconfiguredAuthRepository();

  @override
  Future<void> createAccount({
    required String phoneE164,
    required String password,
  }) =>
      _notConfigured();

  @override
  Future<void> login({required String phoneE164, required String password}) =>
      _notConfigured();

  Future<void> _notConfigured() async {
    throw const AuthFailure(AuthFailureCode.notConfigured);
  }
}
