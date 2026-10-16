import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/journey_insights.dart';
import '../domain/journey_models.dart';

/// Read-only adapter for the optional Go recommendations and weather APIs.
/// [baseUrl] is the configured service base, normally ending in `/api/v1`.
class GoJourneyInsightsRepository {
  GoJourneyInsightsRepository(
    SupabaseClient client,
    Uri baseUrl, {
    http.Client? httpClient,
  }) : _client = client,
       _baseUrl = baseUrl,
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  final SupabaseClient _client;
  final Uri _baseUrl;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  Future<JourneyInsights> load(JourneyLatLng point) async {
    point.validate('homePort');
    if (_baseUrl.scheme != 'https' && !_isLoopback(_baseUrl.host)) {
      return const JourneyInsights(
        recommendationMessage: 'URL layanan harus menggunakan HTTPS.',
        weatherMessage: 'URL layanan harus menggunakan HTTPS.',
      );
    }
    final session = _client.auth.currentSession;
    if (session == null || session.accessToken.isEmpty) {
      return const JourneyInsights(
        recommendationMessage: 'Masuk kembali untuk memuat rekomendasi.',
        weatherMessage: 'Masuk kembali untuk memuat cuaca.',
      );
    }

    final recommendationsUri = _endpoint('recommendations');
    final weatherUri = _endpoint('weather').replace(
      queryParameters: {
        'lat': point.lat.toString(),
        'lng': point.lng.toString(),
      },
    );
    final headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer ${session.accessToken}',
    };
    final results = await Future.wait([
      _get(recommendationsUri, headers),
      _get(weatherUri, headers),
    ]);

    final recommendationResult = results[0];
    final weatherResult = results[1];
    final recBody = recommendationResult.value;
    final weatherBody = weatherResult.value;
    final recData = _object(recBody?['data']) ?? recBody;
    final weatherData = _object(weatherBody?['data']) ?? weatherBody;

    final rows = recData?['items'];
    final items = rows is List
        ? rows
              .whereType<Map>()
              .map(
                (row) => JourneyRecommendation.fromJson(
                  Map<String, dynamic>.from(row),
                ),
              )
              .toList(growable: false)
        : const <JourneyRecommendation>[];
    final current = _object(weatherData?['current']);

    return JourneyInsights(
      weather: current == null ? null : JourneyWeather.fromJson(current),
      recommendations: items,
      generatedAt: _date(recData?['generated_at']),
      validUntil: _date(recData?['valid_until']),
      weatherFetchedAt: _date(weatherData?['fetched_at']),
      isFallback: recData?['is_fallback'] == true,
      recommendationMessage:
          recommendationResult.message ??
          (rows is List ? null : 'Data rekomendasi belum tersedia.'),
      weatherMessage:
          weatherResult.message ??
          (current == null ? 'Data cuaca belum tersedia.' : null),
    );
  }

  Uri _endpoint(String name) {
    final rootPath = _baseUrl.path.replaceFirst(RegExp(r'/+$'), '');
    final path = rootPath.endsWith('/api/v1')
        ? '$rootPath/$name'
        : '$rootPath/api/v1/$name';
    return _baseUrl.replace(path: path, query: null, fragment: null);
  }

  Future<_Response> _get(Uri uri, Map<String, String> headers) async {
    try {
      final response = await _httpClient
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = _tryDecode(response.body);
        final apiMessage =
            _string(body?['message']) ??
            _string(body?['error']) ??
            _string(_object(body?['error'])?['message']);
        return _Response(
          null,
          apiMessage ?? 'Layanan tidak tersedia (HTTP ${response.statusCode}).',
        );
      }
      final body = _tryDecode(response.body);
      if (body == null) {
        return const _Response(null, 'Respons layanan tidak dapat dibaca.');
      }
      return _Response(body, null);
    } catch (_) {
      return const _Response(
        null,
        'Tidak dapat terhubung ke layanan saat ini.',
      );
    }
  }

  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }
}

bool _isLoopback(String host) =>
    host == 'localhost' || host == '127.0.0.1' || host == '::1';

class _Response {
  const _Response(this.value, this.message);
  final Map<String, dynamic>? value;
  final String? message;
}

Map<String, dynamic>? _tryDecode(String body) {
  try {
    final value = jsonDecode(body);
    return _object(value);
  } on FormatException {
    return null;
  }
}

Map<String, dynamic>? _object(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;
String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;
DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
