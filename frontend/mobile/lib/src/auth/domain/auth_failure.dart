enum AuthFailureCode {
  invalidCredentials,
  phoneAlreadyRegistered,
  notConfigured,
  unknown,
}

class AuthFailure implements Exception {
  const AuthFailure(this.code);

  final AuthFailureCode code;
}
