import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/journey/domain/journey_models.dart';

void main() {
  test('parses GeoJSON longitude-latitude order and point source fields', () {
    final detail = JourneyTripDetail.fromJson({
      'id': 'trip-1',
      'track': {
        'type': 'LineString',
        'coordinates': [
          [112.7, -8.5],
          [112.8, -8.6],
        ],
      },
      'fishing_points': [
        {
          'id': 'point-1',
          'lat': -8.55,
          'lng': 112.75,
          'grid_id': 'X001_Y002',
          'started_at': '2026-10-16T01:00:00Z',
          'ended_at': '2026-10-16T02:00:00Z',
          'allocated_catch_kg': 4,
        },
      ],
    });

    expect(detail.track, hasLength(2));
    expect(detail.track.first.lat, -8.5);
    expect(detail.track.first.lng, 112.7);
    expect(detail.fishingPoints, hasLength(1));
    expect(detail.fishingPoints.single.point.lat, -8.55);
    expect(detail.fishingPoints.single.point.lng, 112.75);
    expect(detail.fishingPoints.single.id, 'point-1');
    expect(detail.fishingPoints.single.gridId, 'X001_Y002');
    expect(
      detail.fishingPoints.single.startedAt,
      DateTime.utc(2026, 10, 16, 1),
    );
    expect(detail.fishingPoints.single.endedAt, DateTime.utc(2026, 10, 16, 2));
  });

  test('missing or malformed geometry yields no track points', () {
    for (final geometry in <Object?>[
      null,
      {
        'type': 'Point',
        'coordinates': [112.7, -8.5],
      },
      {'type': 'LineString', 'coordinates': []},
      {
        'type': 'LineString',
        'coordinates': [
          [112.7, -8.5],
        ],
      },
      {
        'type': 'LineString',
        'coordinates': [
          [112.7, -8.5],
          [112.8],
        ],
      },
      {
        'type': 'LineString',
        'coordinates': [
          [112.7, -8.5],
          [double.nan, -8.6],
        ],
      },
      {
        'type': 'LineString',
        'coordinates': [
          [181, -8.5],
          [112.8, -8.6],
        ],
      },
    ]) {
      final detail = JourneyTripDetail.fromJson({
        'id': 'trip-1',
        'track': geometry,
      });
      expect(detail.track, isEmpty, reason: '$geometry');
    }
  });

  test('invalid fishing rows are skipped and missing geometry stays empty', () {
    final detail = JourneyTripDetail.fromJson({
      'id': 'trip-1',
      'track': {'type': 'MultiLineString', 'coordinates': []},
      'fishing_points': [
        {'id': 'valid', 'lat': -8.5, 'lng': 112.7},
        {'id': 'nan', 'lat': double.infinity, 'lng': 112.7},
        {'id': 'range', 'lat': -91, 'lng': 112.7},
        {'id': 'missing', 'lat': -8.5},
        null,
      ],
    });

    expect(detail.track, isEmpty);
    expect(detail.fishingPoints, hasLength(1));
    expect(detail.fishingPoints.single.id, 'valid');
    expect(detail.fishingPoints.single.gridId, isNull);
    expect(detail.fishingPoints.single.startedAt, isNull);
    expect(detail.fishingPoints.single.endedAt, isNull);
  });
}
