import 'dart:math' as math;

import 'package:proj4dart/proj4dart.dart';

import 'geo_point.dart';
import 'grid_cell.dart';

/// Stable 500 m grid in UTM zone 49S. IDs are independent of map zoom,
/// viewport, and AOI bounds.
class MetricGrid500 {
  MetricGrid500({GeoBounds? initialBounds})
    : initialBounds =
          initialBounds ??
          const GeoBounds(
            west: 112.25,
            east: 113.10,
            south: -9.15,
            north: -8.35,
          ) {
    this.initialBounds.validate();
  }

  static const namespace = 'tp-id-utm49s-500m';
  static const version = 'v2';
  static const resolutionMeters = 500.0;
  static const boundaryToleranceMeters = 0.000001;
  static const metricDefinition =
      '+proj=utm +zone=49 +south +datum=WGS84 +units=m +no_defs';

  final GeoBounds initialBounds;

  static final Projection _utm49s = Projection.add(
    'TP_UTM49S',
    metricDefinition,
  );

  GridCell resolve(GeoPoint point) {
    _validatePoint(point);
    if (!initialBounds.contains(point)) {
      throw RangeError('Point is outside the configured initial map bounds');
    }
    final metric = _toMetric(point);
    final x = _snap(metric.x);
    final y = _snap(metric.y);
    return cellFromIndexes(
      _safeFloor(y / resolutionMeters),
      _safeFloor(x / resolutionMeters),
    );
  }

  GridCell cellFromIndexes(int row, int col) {
    _validateIndex(row, 'row');
    _validateIndex(col, 'col');
    final minX = col * resolutionMeters;
    final minY = row * resolutionMeters;
    final maxX = minX + resolutionMeters;
    final maxY = minY + resolutionMeters;
    if (![minX, minY, maxX, maxY].every((value) => value.isFinite) ||
        maxX - minX != resolutionMeters ||
        maxY - minY != resolutionMeters) {
      throw RangeError('Grid index is outside the exact coordinate domain');
    }

    final polygon = <GeoPoint>[
      _toGeographic(minX, minY),
      _toGeographic(maxX, minY),
      _toGeographic(maxX, maxY),
      _toGeographic(minX, maxY),
    ];
    final center = _toGeographic(
      minX + resolutionMeters / 2,
      minY + resolutionMeters / 2,
    );
    return GridCell(
      row: row,
      col: col,
      id: '$namespace:$version:r${_signed(row)}:c${_signed(col)}',
      code: 'TP1-$namespace-$version-${_signed(row)}-${_signed(col)}',
      polygon: List.unmodifiable(polygon),
      center: center,
    );
  }

  GridViewport enumerateViewport(GeoBounds bounds, {int maxCells = 600}) {
    bounds.validate();
    if (maxCells <= 0) throw ArgumentError.value(maxCells, 'maxCells');
    final clipped = _intersection(bounds, initialBounds);
    if (clipped == null) return const GridViewport(cells: [], exceeded: false);

    // Project samples along the four geographic edges. This bounds the curved
    // projected rectangle without using a zoom-dependent grid or scanning a
    // larger grid than the caller's cap permits.
    final samples = <_MetricPoint>[];
    const steps = 24;
    for (var i = 0; i <= steps; i++) {
      final fraction = i / steps;
      final longitude = clipped.west + (clipped.east - clipped.west) * fraction;
      final latitude =
          clipped.south + (clipped.north - clipped.south) * fraction;
      samples
        ..add(
          _toMetric(GeoPoint(latitude: clipped.south, longitude: longitude)),
        )
        ..add(
          _toMetric(GeoPoint(latitude: clipped.north, longitude: longitude)),
        )
        ..add(_toMetric(GeoPoint(latitude: latitude, longitude: clipped.west)))
        ..add(_toMetric(GeoPoint(latitude: latitude, longitude: clipped.east)));
    }
    final minX = samples.map((point) => point.x).reduce(math.min);
    final maxX = samples.map((point) => point.x).reduce(math.max);
    final minY = samples.map((point) => point.y).reduce(math.min);
    final maxY = samples.map((point) => point.y).reduce(math.max);
    final firstCol = _safeFloor(minX / resolutionMeters);
    final lastCol = _safeFloor(_exclusiveUpper(maxX) / resolutionMeters);
    final firstRow = _safeFloor(minY / resolutionMeters);
    final lastRow = _safeFloor(_exclusiveUpper(maxY) / resolutionMeters);
    final count = (lastCol - firstCol + 1) * (lastRow - firstRow + 1);
    if (count > maxCells) {
      return const GridViewport(cells: [], exceeded: true);
    }

    final cells = <GridCell>[];
    for (var row = firstRow; row <= lastRow; row++) {
      for (var col = firstCol; col <= lastCol; col++) {
        final cell = cellFromIndexes(row, col);
        if (_polygonIntersectsBounds(cell.polygon, clipped)) cells.add(cell);
      }
    }
    return GridViewport(cells: List.unmodifiable(cells), exceeded: false);
  }

  _MetricPoint _toMetric(GeoPoint point) {
    final transformed = Projection.WGS84.transform(
      _utm49s,
      Point(x: point.longitude, y: point.latitude),
    );
    return _MetricPoint(transformed.x.toDouble(), transformed.y.toDouble());
  }

  GeoPoint _toGeographic(double x, double y) {
    final transformed = _utm49s.transform(Projection.WGS84, Point(x: x, y: y));
    return GeoPoint(
      latitude: transformed.y.toDouble(),
      longitude: transformed.x.toDouble(),
    );
  }

  static void _validatePoint(GeoPoint point) {
    if (!point.latitude.isFinite ||
        !point.longitude.isFinite ||
        point.latitude < -90 ||
        point.latitude > 90 ||
        point.longitude < -180 ||
        point.longitude > 180) {
      throw ArgumentError('Point must be valid WGS84 latitude/longitude');
    }
  }

  static double _snap(double value) {
    final nearest = (value / resolutionMeters).round() * resolutionMeters;
    return (value - nearest).abs() <= boundaryToleranceMeters ? nearest : value;
  }

  static int _safeFloor(double value) {
    final result = value.floor();
    if (result.abs() > 9007199254740991) {
      throw RangeError('Grid index exceeds the safe integer domain');
    }
    return result;
  }

  static void _validateIndex(int value, String name) {
    if (value.abs() > 9007199254740991) {
      throw RangeError('$name exceeds the safe integer domain');
    }
  }

  static double _exclusiveUpper(double value) =>
      value - boundaryToleranceMeters;

  static String _signed(int index) => index < 0 ? 'n${-index}' : 'p$index';

  static GeoBounds? _intersection(GeoBounds first, GeoBounds second) {
    final west = math.max(first.west, second.west);
    final south = math.max(first.south, second.south);
    final east = math.min(first.east, second.east);
    final north = math.min(first.north, second.north);
    if (west >= east || south >= north) return null;
    return GeoBounds(west: west, south: south, east: east, north: north);
  }

  static bool _polygonIntersectsBounds(
    List<GeoPoint> polygon,
    GeoBounds bounds,
  ) {
    final rectangle = <GeoPoint>[
      GeoPoint(latitude: bounds.south, longitude: bounds.west),
      GeoPoint(latitude: bounds.south, longitude: bounds.east),
      GeoPoint(latitude: bounds.north, longitude: bounds.east),
      GeoPoint(latitude: bounds.north, longitude: bounds.west),
    ];
    if (polygon.any((point) => _pointInBounds(point, bounds))) return true;
    if (rectangle.any((point) => _pointInPolygon(point, polygon))) return true;
    for (var polygonIndex = 0; polygonIndex < polygon.length; polygonIndex++) {
      final polygonStart = polygon[polygonIndex];
      final polygonEnd = polygon[(polygonIndex + 1) % polygon.length];
      for (
        var rectangleIndex = 0;
        rectangleIndex < rectangle.length;
        rectangleIndex++
      ) {
        if (_segmentsIntersect(
          polygonStart,
          polygonEnd,
          rectangle[rectangleIndex],
          rectangle[(rectangleIndex + 1) % rectangle.length],
        )) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _pointInBounds(GeoPoint point, GeoBounds bounds) =>
      point.longitude >= bounds.west &&
      point.longitude <= bounds.east &&
      point.latitude >= bounds.south &&
      point.latitude <= bounds.north;

  static bool _pointInPolygon(GeoPoint point, List<GeoPoint> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final first = polygon[i];
      final second = polygon[j];
      if (_pointOnSegment(point, first, second)) return true;
      final crosses =
          (first.latitude > point.latitude) !=
              (second.latitude > point.latitude) &&
          point.longitude <
              (second.longitude - first.longitude) *
                      (point.latitude - first.latitude) /
                      (second.latitude - first.latitude) +
                  first.longitude;
      if (crosses) inside = !inside;
    }
    return inside;
  }

  static bool _segmentsIntersect(
    GeoPoint a,
    GeoPoint b,
    GeoPoint c,
    GeoPoint d,
  ) {
    final abC = _orientation(a, b, c);
    final abD = _orientation(a, b, d);
    final cdA = _orientation(c, d, a);
    final cdB = _orientation(c, d, b);
    if ((abC == 0 && _pointOnSegment(c, a, b)) ||
        (abD == 0 && _pointOnSegment(d, a, b)) ||
        (cdA == 0 && _pointOnSegment(a, c, d)) ||
        (cdB == 0 && _pointOnSegment(b, c, d))) {
      return true;
    }
    return (abC < 0) != (abD < 0) && (cdA < 0) != (cdB < 0);
  }

  static double _orientation(GeoPoint a, GeoPoint b, GeoPoint c) =>
      (b.longitude - a.longitude) * (c.latitude - a.latitude) -
      (b.latitude - a.latitude) * (c.longitude - a.longitude);

  static bool _pointOnSegment(GeoPoint point, GeoPoint a, GeoPoint b) {
    const epsilon = 1e-12;
    return _orientation(a, b, point).abs() <= epsilon &&
        point.longitude >= math.min(a.longitude, b.longitude) - epsilon &&
        point.longitude <= math.max(a.longitude, b.longitude) + epsilon &&
        point.latitude >= math.min(a.latitude, b.latitude) - epsilon &&
        point.latitude <= math.max(a.latitude, b.latitude) + epsilon;
  }
}

class _MetricPoint {
  const _MetricPoint(this.x, this.y);
  final double x;
  final double y;
}
