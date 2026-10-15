enum AuthFailureCode {
  invalidCredentials,
  phoneAlreadyRegistered,
  phoneVerificationRequired,
  invalidOtp,
  tooManyRequests,
  phoneProviderDisabled,
  notConfigured,
  unknown,
}

class AuthFailure implements Exception {
  const AuthFailure(this.code);

  final AuthFailureCode code;
}
