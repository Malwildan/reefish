abstract interface class AuthRepository {
  Future<void> createAccount({
    required String phoneE164,
    required String password,
  });

  Future<void> login({required String phoneE164, required String password});
}
