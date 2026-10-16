import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reefish_mobile/src/journey/data/go_journey_insights_repository.dart';
import 'package:reefish_mobile/src/journey/domain/journey_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const homePort = JourneyLatLng(lat: -8.43, lng: 112.68);

  test(
    'weather loads with boat coordinates when recommendations fail',
    () async {
      final requests = <http.Request>[];
      final repository = await _repository((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/recommendations')) {
          return _json({
            'error': {
              'code': 'UPSTREAM_UNAVAILABLE',
              'message': 'Recommendation service unavailable.',
            },
          }, 503);
        }
        return _weatherResponse();
      });
      addTearDown(repository.close);

      final insights = await repository.load(point: homePort);

      final weatherRequest = requests.singleWhere(
        (request) => request.url.path.endsWith('/weather'),
      );
      expect(weatherRequest.url.queryParameters, {
        'lat': '-8.43',
        'lng': '112.68',
      });
      expect(requests, hasLength(2));
      for (final request in requests) {
        expect(request.headers['authorization'], 'Bearer test-access-token');
        expect(request.url.toString(), isNot(contains('test-access-token')));
      }
      expect(insights.recommendations, isEmpty);
      expect(
        insights.recommendationMessage,
        contains('Recommendation service'),
      );
      expect(insights.weather?.tempC, 27.4);
      expect(insights.weather?.windSpeedMs, 4.2);
      expect(insights.weather?.windDirectionDeg, 120);
      expect(insights.weather?.windDirectionLabel, 'TG');
      expect(insights.weather?.weatherCode, 2);
      expect(insights.weather?.waveHeightM, 0.8);
      expect(insights.weatherFetchedAt, DateTime.parse('2026-10-16T05:00:00Z'));
    },
  );

  test('recommendations remain available when weather fails', () async {
    final repository = await _repository((request) async {
      if (request.url.path.endsWith('/recommendations')) {
        return _json({
          'data': {
            'items': [
              {'type': 'fuel_saving', 'predicted_fuel_liters': 12.5},
            ],
            'generated_at': '2026-10-16T05:00:00Z',
            'valid_until': '2026-10-16T11:00:00Z',
            'is_fallback': true,
          },
        });
      }
      return _json({
        'error': {
          'code': 'WEATHER_UNAVAILABLE',
          'message': 'Weather service unavailable.',
        },
      }, 503);
    });
    addTearDown(repository.close);

    final insights = await repository.load(point: homePort);

    expect(insights.recommendations, hasLength(1));
    expect(insights.recommendations.single.predictedFuelLiters, 12.5);
    expect(insights.isFallback, isTrue);
    expect(insights.weather, isNull);
    expect(insights.weatherMessage, contains('Weather service'));
  });

  test(
    'nullable upstream weather fields do not become calm or zero values',
    () async {
      final repository = await _repository((request) async {
        if (request.url.path.endsWith('/recommendations')) {
          return _json({
            'data': {'items': []},
          });
        }
        return _json({
          'data': {
            'fetched_at': '2026-10-16T05:00:00Z',
            'current': {
              'time': '2026-10-16T05:00:00Z',
              'temp_c': null,
              'wind_speed_ms': null,
              'wave_height_m': null,
              'weather_label': null,
              'risk': 'unknown',
            },
          },
        });
      });
      addTearDown(repository.close);

      final insights = await repository.load(point: homePort);

      expect(insights.weather?.tempC, isNull);
      expect(insights.weather?.windSpeedMs, isNull);
      expect(insights.weather?.waveHeightM, isNull);
      expect(insights.weather?.risk, 'unknown');
    },
  );

  test(
    'nullable Open-Meteo fields stay missing and no port skips weather call',
    () async {
      final paths = <String>[];
      final repository = await _repository((request) async {
        paths.add(request.url.path);
        return _json({
          'data': {'items': []},
        });
      });
      addTearDown(repository.close);

      final insights = await repository.load();

      expect(paths, ['/api/v1/recommendations']);
      expect(insights.weather, isNull);
      expect(
        insights.weatherMessage,
        'Tambahkan lokasi pelabuhan untuk memuat cuaca.',
      );
    },
  );

  test('refuses non-loopback HTTP before sending the access token', () async {
    final repository = await _repository(
      (_) async => fail('must not make an HTTP request'),
      baseUrl: Uri.parse('http://weather.example.test'),
    );
    addTearDown(repository.close);

    final insights = await repository.load(point: homePort);

    expect(insights.weather, isNull);
    expect(insights.weatherMessage, 'URL layanan harus menggunakan HTTPS.');
  });
}

Future<GoJourneyInsightsRepository> _repository(
  Future<http.Response> Function(http.Request) handler, {
  Uri? baseUrl,
}) async {
  final supabase = SupabaseClient(
    'https://example.supabase.co',
    'sb_publishable_test-key',
    httpClient: MockClient((request) async {
      if (request.url.path == '/auth/v1/token') {
        return _json({
          'access_token': 'test-access-token',
          'token_type': 'bearer',
          'expires_in': 3600,
          'refresh_token': 'test-refresh-token',
          'user': {
            'id': 'owner-1',
            'aud': 'authenticated',
            'role': 'authenticated',
            'phone': '+6281234567890',
            'app_metadata': {
              'provider': 'phone',
              'providers': ['phone'],
            },
            'user_metadata': {},
            'created_at': '2026-10-16T00:00:00Z',
          },
        });
      }
      return _json({'error': 'unexpected Supabase request'}, 404);
    }),
  );
  await supabase.auth.signInWithPassword(
    phone: '+6281234567890',
    password: 'test-password',
  );
  return GoJourneyInsightsRepository(
    supabase,
    baseUrl ?? Uri.parse('https://api.example.test/api/v1'),
    httpClient: MockClient(handler),
  );
}

http.Response _weatherResponse() => _json({
  'data': {
    'fetched_at': '2026-10-16T05:00:00Z',
    'current': {
      'time': '2026-10-16T05:00:00Z',
      'weather_code': 2,
      'weather_label': 'Berawan sebagian',
      'temp_c': 27.4,
      'wind_speed_ms': 4.2,
      'wind_dir_deg': 120,
      'wind_dir_label': 'TG',
      'wave_height_m': 0.8,
      'risk': 'low',
    },
  },
});

http.Response _json(Object body, [int statusCode = 200]) => http.Response(
  jsonEncode(body),
  statusCode,
  headers: {'content-type': 'application/json'},
);
