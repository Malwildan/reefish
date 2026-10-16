import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/journey_models.dart';
import '../domain/journey_repository.dart';

class SupabaseJourneyRepository implements JourneyRepository {
  const SupabaseJourneyRepository({required this.client, this.now});

  final SupabaseClient client;
  final DateTime Function()? now;

  @override
  Future<JourneyProfile> getMe() async {
    final result = await _rpc('api_me', const {});
    return JourneyProfile.fromJson(_object(result, 'api_me'));
  }

  @override
  Future<JourneyBoat> createBoat(JourneyBoatInput input) async {
    input.validate();
    final result = await _rpc('api_create_boat', {'p': input.toJson()});
    return JourneyBoat.fromJson(_object(result, 'api_create_boat'));
  }

  @override
  Future<JourneyTripSubmission> submitTrip(JourneyTripInput input) async {
    final payload = input.toJson(now: now?.call());
    final result = await _rpc('api_post_trip', {'p': payload});
    return JourneyTripSubmission.fromJson(_object(result, 'api_post_trip'));
  }

  @override
  Future<JourneyTripHistory> listTrips({
    int page = 1,
    int limit = 20,
    String? from,
    String? to,
    JourneyTripSource? source,
    String sort = '-departed_at',
  }) async {
    if (page < 1 || limit < 1 || limit > 100) {
      throw const JourneyFailure(
        code: JourneyFailureCode.validation,
        message: 'Page must be positive and limit must be between 1 and 100.',
      );
    }
    const allowedSorts = {
      '-departed_at',
      'departed_at',
      '-catch_kg',
      '-fuel_efficiency_pct',
    };
    if (!allowedSorts.contains(sort)) {
      throw const JourneyFailure(
        code: JourneyFailureCode.validation,
        message: 'Unsupported trip sort order.',
      );
    }
    if (from != null) _validateDate(from, 'from');
    if (to != null) _validateDate(to, 'to');
    final params = <String, dynamic>{
      'p_page': page,
      'p_limit': limit,
      'p_sort': sort,
    };
    if (from != null) params['p_from'] = from;
    if (to != null) params['p_to'] = to;
    if (source != null) params['p_source'] = source.wireValue;
    final result = await _rpc('api_list_trips', params);
    return JourneyTripHistory.fromJson(_object(result, 'api_list_trips'));
  }

  @override
  Future<JourneyTripDetail> getTripDetail(
    String id, {
    String track = 'simplified',
  }) async {
    if (id.trim().isEmpty ||
        !const {'simplified', 'full', 'none'}.contains(track)) {
      throw const JourneyFailure(
        code: JourneyFailureCode.validation,
        message: 'A trip ID and supported track mode are required.',
      );
    }
    final result = await _rpc('api_trip_detail', {
      'p_id': id,
      'p_track': track,
    });
    return JourneyTripDetail.fromJson(_object(result, 'api_trip_detail'));
  }

  @override
  Future<JourneyDashboard> loadDashboard({int tripLimit = 5}) async {
    if (tripLimit < 1 || tripLimit > 100) {
      throw const JourneyFailure(
        code: JourneyFailureCode.validation,
        message: 'Dashboard trip limit must be between 1 and 100.',
      );
    }
    final values = await Future.wait([getMe(), listTrips(limit: tripLimit)]);
    return JourneyDashboard(
      profile: values[0] as JourneyProfile,
      history: values[1] as JourneyTripHistory,
    );
  }

  Future<Object?> _rpc(String function, Map<String, dynamic> params) async {
    if (client.auth.currentSession == null) {
      throw const JourneyFailure(
        code: JourneyFailureCode.authenticationRequired,
        message: 'Sign in before loading journey data.',
      );
    }
    try {
      return await client.rpc(function, params: params);
    } on PostgrestException catch (error) {
      final code = error.message.toUpperCase();
      final authFailure =
          error.code == 'PGRST301' ||
          error.code == 'PGRST303' ||
          code == 'UNAUTHORIZED' ||
          code == 'AUTHENTICATION_REQUIRED';
      if (error.code == 'PGRST202' ||
          code.contains('FUNCTION') && code.contains('NOT FOUND')) {
        throw JourneyFailure(
          code: JourneyFailureCode.apiNotAvailable,
          message:
              'Journey API is not installed in the configured Supabase project.',
          details: error,
        );
      }
      const validationCodes = {
        'VALIDATION_ERROR',
        'OUT_OF_PILOT',
        'INVALID_TIME_RANGE',
      };
      final backendCode = error.message.toUpperCase();
      throw JourneyFailure(
        code: authFailure
            ? JourneyFailureCode.authenticationRequired
            : validationCodes.contains(backendCode)
            ? JourneyFailureCode.validation
            : JourneyFailureCode.backend,
        message: error.hint?.isNotEmpty == true ? error.hint! : error.message,
        details: {
          'code': error.code,
          'backendCode': backendCode,
          'details': error.details,
        },
      );
    }
  }
}

Map<String, dynamic> _object(Object? value, String function) {
  if (value is Map) return Map<String, dynamic>.from(value);
  throw JourneyFailure(
    code: JourneyFailureCode.backend,
    message: 'Supabase returned an invalid response for $function.',
  );
}

void _validateDate(String value, String field) {
  final date = DateTime.tryParse(value);
  if (date == null ||
      value.length != 10 ||
      date.toIso8601String().substring(0, 10) != value) {
    throw JourneyFailure(
      code: JourneyFailureCode.validation,
      message: '$field must use YYYY-MM-DD.',
    );
  }
}
