abstract interface class AuthRepository {
  AuthSessionStatus get currentSessionStatus;

  Stream<AuthSessionStatus> get sessionChanges;

  Future<AuthResult> createAccount({
    required String phoneE164,
    required String password,
  });

  Future<AuthResult> login({
    required String phoneE164,
    required String password,
  });

  Future<void> verifyPhone({required String phoneE164, required String otp});

  Future<void> resendPhoneOtp({required String phoneE164});

  Future<void> signOut();
}

enum AuthResult { authenticated, verificationRequired }

enum AuthSessionStatus { signedOut, signedIn }
