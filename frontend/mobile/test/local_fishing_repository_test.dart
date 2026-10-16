import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reefish_mobile/src/map/data/local_departure_repository.dart';
import 'package:reefish_mobile/src/map/data/local_fishing_point_repository.dart';
import 'package:reefish_mobile/src/map/domain/departure_repository.dart';
import 'package:reefish_mobile/src/map/domain/fishing_point_repository.dart';
import 'package:reefish_mobile/src/map/domain/geo_point.dart';
import 'package:reefish_mobile/src/map/domain/metric_grid_500.dart';

void main() {
  test(
    'fishing choice preserves a separate departure and owner storage',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final grid = MetricGrid500();
      const departurePoint = GeoPoint(latitude: -8.433, longitude: 112.683);
      const fishingPoint = GeoPoint(latitude: -8.443, longitude: 112.69);
      final departure = DeparturePoint(
        point: departurePoint,
        cellId: grid.resolve(departurePoint).id,
        savedAt: DateTime.utc(2026, 10, 16),
      );
      final departureRepo = LocalDepartureRepository(
        preferences: preferences,
        ownerId: 'owner-a',
      );
      await departureRepo.save(departure);
      final repo = LocalFishingPointRepository(
        preferences: preferences,
        ownerId: 'owner-a',
      );
      await repo.save(
        FishingPointSelection(
          point: fishingPoint,
          cellId: grid.resolve(fishingPoint).id,
          departure: departure,
          savedAt: DateTime.utc(2026, 10, 16, 1),
        ),
      );
      final result = await repo.read();
      expect(result?.point, fishingPoint);
      expect(result?.departure.point, departurePoint);
      expect((await departureRepo.read())?.point, departurePoint);
      expect(
        await LocalFishingPointRepository(
          preferences: preferences,
          ownerId: 'owner-b',
        ).read(),
        isNull,
      );
    },
  );

  test(
    'rejects mismatched persisted fishing cell and preserves invalid data',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      const point = GeoPoint(latitude: -8.433, longitude: 112.683);
      final cell = MetricGrid500().resolve(point);
      final data = {
        'latitude': point.latitude,
        'longitude': point.longitude,
        'cell_id': '${cell.id}-invalid',
        'saved_at': '2026-10-16T00:00:00Z',
        'departure': {
          'latitude': point.latitude,
          'longitude': point.longitude,
          'cell_id': cell.id,
          'saved_at': '2026-10-16T00:00:00Z',
        },
      };
      final raw = jsonEncode(data);
      await preferences.setString('reefish.fishing-point.v1.owner-a', raw);
      final repo = LocalFishingPointRepository(
        preferences: preferences,
        ownerId: 'owner-a',
      );
      await expectLater(repo.read(), throwsFormatException);
      expect(preferences.getString('reefish.fishing-point.v1.owner-a'), raw);
    },
  );
}
