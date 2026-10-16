import 'journey_models.dart';

abstract interface class JourneyRepository {
  Future<JourneyProfile> getMe();

  Future<JourneyBoat> createBoat(JourneyBoatInput input);

  /// The caller must reuse this exact input (and clientTripId) for retries.
  /// Recommendations are fetched separately from the optional Go service.
  Future<JourneyTripSubmission> submitTrip(JourneyTripInput input);

  Future<JourneyTripHistory> listTrips({
    int page = 1,
    int limit = 20,
    String? from,
    String? to,
    JourneyTripSource? source,
    String sort = '-departed_at',
  });

  Future<JourneyTripDetail> getTripDetail(
    String id, {
    String track = 'simplified',
  });

  Future<JourneyDashboard> loadDashboard({int tripLimit = 5});
}

abstract interface class JourneyDraftStore {
  Future<void> save(JourneyDraft draft);

  Future<JourneyDraft?> read();

  Future<void> delete();
}

enum JourneyFailureCode {
  authenticationRequired,
  apiNotAvailable,
  validation,
  backend,
  storage,
}

class JourneyFailure implements Exception {
  const JourneyFailure({
    required this.code,
    required this.message,
    this.details,
  });

  final JourneyFailureCode code;
  final String message;
  final Object? details;

  @override
  String toString() => 'JourneyFailure(${code.name}): $message';
}
