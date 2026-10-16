/// A user-safe failure while loading authoritative grid policy.
///
/// The code identifies the recovery path without exposing SDK or backend
/// diagnostics to the UI.
enum GridPolicyFailureCode {
  notConfigured,
  authenticationRequired,
  permissionDenied,
  unavailable,
  invalidResponse,
}

class GridPolicyFailure implements Exception {
  const GridPolicyFailure(this.code);

  final GridPolicyFailureCode code;

  String get userMessage => switch (code) {
    GridPolicyFailureCode.notConfigured =>
      'Layanan status petak belum dikonfigurasi. Hubungkan backend terlebih dahulu.',
    GridPolicyFailureCode.authenticationRequired =>
      'Masuk terlebih dahulu untuk memverifikasi status petak.',
    GridPolicyFailureCode.permissionDenied =>
      'Akun ini belum dapat membaca status petak. Hubungi admin.',
    GridPolicyFailureCode.unavailable =>
      'Layanan status petak belum dapat dihubungi. Periksa koneksi lalu muat ulang.',
    GridPolicyFailureCode.invalidResponse =>
      'Respons status petak belum sesuai. Hubungi admin.',
  };

  @override
  String toString() => 'GridPolicyFailure(${code.name})';
}
