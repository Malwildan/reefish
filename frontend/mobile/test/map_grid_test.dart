import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:proj4dart/proj4dart.dart';
import 'package:reefish_mobile/src/map/domain/geo_point.dart';
import 'package:reefish_mobile/src/map/domain/metric_grid_500.dart';

void main() {
  group('MetricGrid500', () {
    final grid = MetricGrid500();

    test('produces canonical signed IDs independent of viewport', () {
      final cell = grid.cellFromIndexes(-2, -3);

      expect(cell.id, 'tp-id-utm49s-500m:v2:rn2:cn3');
      expect(cell.code, 'TP1-tp-id-utm49s-500m-v2-n2-n3');
      expect(grid.cellFromIndexes(-2, -3).id, cell.id);
    });

    test(
      'round-trips a cell center and preserves its four-corner footprint',
      () {
        final cell = grid.resolve(
          const GeoPoint(latitude: -8.433, longitude: 112.683),
        );

        expect(cell.polygon, hasLength(4));
        expect(grid.resolve(cell.center).id, cell.id);
        expect(cell.polygon.first.latitude, isNot(cell.polygon.last.latitude));
        expect(cell.polygon.first.longitude, isNot(cell.polygon[1].longitude));
        // The square is not clipped at the initial map bounds or by a coastline.
        expect(cell.polygon.toSet(), hasLength(4));
      },
    );

    test(
      'cell edges remain 500 m after projecting the full WGS84 footprint',
      () {
        final cell = grid.resolve(
          const GeoPoint(latitude: -8.433, longitude: 112.683),
        );
        final utm = Projection.add(
          'TEST_UTM49S',
          MetricGrid500.metricDefinition,
        );
        final metric = cell.polygon
            .map(
              (point) => Projection.WGS84.transform(
                utm,
                Point(x: point.longitude, y: point.latitude),
              ),
            )
            .toList();

        for (var i = 0; i < metric.length; i++) {
          final start = metric[i];
          final end = metric[(i + 1) % metric.length];
          final edgeLength = math.sqrt(
            math.pow(end.x - start.x, 2) + math.pow(end.y - start.y, 2),
          );
          expect(edgeLength, closeTo(500, 0.001));
        }
      },
    );

    test('resolve rejects coordinates outside the configured bounds', () {
      expect(
        () => grid.resolve(const GeoPoint(latitude: -9.2, longitude: 112.683)),
        throwsRangeError,
      );
    });

    test('matches the existing JavaScript grid resolver fixture', () {
      final cell = grid.resolve(
        const GeoPoint(latitude: -8.433, longitude: 112.683),
      );
      expect(cell.id, 'tp-id-utm49s-500m:v2:rp18134:cp1370');
      expect(cell.row, 18134);
      expect(cell.col, 1370);
    });

    test('uses lower-inclusive and upper-exclusive cell edges', () {
      final cell = grid.resolve(
        const GeoPoint(latitude: -8.433, longitude: 112.683),
      );

      expect(grid.resolve(cell.polygon[0]).id, cell.id); // southwest
      final northEast = grid.resolve(cell.polygon[2]);
      expect(northEast.col, cell.col + 1);
      expect(northEast.row, cell.row + 1);
    });

    test(
      'enumeration rejects oversized candidate ranges without partial output',
      () {
        final viewport = grid.enumerateViewport(
          const GeoBounds(
            west: 112.25,
            south: -9.15,
            east: 113.10,
            north: -8.35,
          ),
          maxCells: 1,
        );

        expect(viewport.exceeded, isTrue);
        expect(viewport.cells, isEmpty);
      },
    );

    test('a compact viewport only returns canonical intersecting cells', () {
      final viewport = grid.enumerateViewport(
        const GeoBounds(
          west: 112.682,
          south: -8.434,
          east: 112.684,
          north: -8.432,
        ),
        maxCells: 600,
      );

      expect(viewport.exceeded, isFalse);
      expect(viewport.cells, isNotEmpty);
      expect(
        viewport.cells.map((cell) => cell.id).toSet(),
        hasLength(viewport.cells.length),
      );
      expect(viewport.cells.every((cell) => cell.polygon.length == 4), isTrue);
    });

    test('viewport wholly inside one cell still returns that cell', () {
      final cell = grid.resolve(
        const GeoPoint(latitude: -8.433, longitude: 112.683),
      );
      final center = cell.center;
      const delta = 0.00001;
      final viewport = grid.enumerateViewport(
        GeoBounds(
          west: center.longitude - delta,
          south: center.latitude - delta,
          east: center.longitude + delta,
          north: center.latitude + delta,
        ),
      );

      expect(viewport.exceeded, isFalse);
      expect(viewport.cells.map((item) => item.id), contains(cell.id));
    });

    test(
      'viewport crossing a cell edge finds it without containing a vertex',
      () {
        final cell = grid.resolve(
          const GeoPoint(latitude: -8.433, longitude: 112.683),
        );
        final start = cell.polygon[0];
        final end = cell.polygon[3];
        final middleLongitude = (start.longitude + end.longitude) / 2;
        final middleLatitude = (start.latitude + end.latitude) / 2;
        final viewportBounds = GeoBounds(
          west: middleLongitude - 0.00005,
          south: middleLatitude - 0.00005,
          east: middleLongitude + 0.00005,
          north: middleLatitude + 0.00005,
        );

        expect(cell.polygon.any(viewportBounds.contains), isFalse);
        final viewport = grid.enumerateViewport(viewportBounds);

        expect(viewport.exceeded, isFalse);
        expect(viewport.cells.map((item) => item.id), contains(cell.id));
      },
    );
  });
}
