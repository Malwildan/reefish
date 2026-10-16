import 'sailing_session.dart';

abstract interface class SailingSessionStore {
  Future<SailingSession?> read();

  Future<void> save(SailingSession session);

  Future<void> clear({required String clientTripId});
}

class SailingStoreFailure implements Exception {
  const SailingStoreFailure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'SailingStoreFailure: $message';
}
