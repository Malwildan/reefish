import 'dart:math' as math;

import 'geo_point.dart';
import 'grid_cell.dart';
import 'marine_data.dart';

/// Returns area features whose actual polygon footprint intersects [cell].
///
/// The bounding-box check is only a prefilter. Ring boundaries count as an
/// intersection, including hole boundaries; an entire cell inside a hole does
/// not. Coordinates are tested in local longitude/latitude space, which is
/// suitable for the small, bounded map area represented by this dataset.
List<MarineAreaFeature> intersectingMarineFeatures(
  List<MarineAreaFeature> features,
  GridCell cell,
) => MarineFeatureIndex(features).intersecting(cell);

/// Reusable exact-intersection lookup for an immutable set of area features.
///
/// Polygon bounds are prepared once, while exact polygon checks still use the
/// original rings. Create one index per dataset snapshot and reuse it as cells
/// are selected.
class MarineFeatureIndex {
  MarineFeatureIndex(List<MarineAreaFeature> features)
    : _features = List<MarineAreaFeature>.unmodifiable(features),
      _polygons = List<List<_IndexedPolygon>>.unmodifiable([
        for (final feature in features)
          List<_IndexedPolygon>.unmodifiable([
            for (final polygon in feature.polygons)
              _IndexedPolygon(
                rings: polygon,
                bounds: polygon.isEmpty
                    ? null
                    : _Bounds.fromPoints(polygon.expand((ring) => ring)),
              ),
          ]),
      ]);

  final List<MarineAreaFeature> _features;
  final List<List<_IndexedPolygon>> _polygons;

  List<MarineAreaFeature> intersecting(GridCell cell) {
    final cellPoints = cell.polygon;
    if (cellPoints.length < 3) return const [];
    final cellBounds = _Bounds.fromPoints(cellPoints);
    final matches = <MarineAreaFeature>[];
    for (
      var featureIndex = 0;
      featureIndex < _features.length;
      featureIndex++
    ) {
      for (final polygon in _polygons[featureIndex]) {
        final bounds = polygon.bounds;
        if (bounds != null &&
            cellBounds.intersectsInclusive(bounds) &&
            _polygonIntersectsCell(polygon.rings, cellPoints)) {
          matches.add(_features[featureIndex]);
          break;
        }
      }
    }
    return List.unmodifiable(matches);
  }
}

class _IndexedPolygon {
  const _IndexedPolygon({required this.rings, required this.bounds});

  final List<List<GeoPoint>> rings;
  final _Bounds? bounds;
}

bool _polygonIntersectsCell(List<List<GeoPoint>> rings, List<GeoPoint> cell) {
  final shell = rings.first;
  if (shell.length < 3) return false;

  // Any feature boundary touching or crossing the cell counts, including a
  // hole boundary. A cell wholly inside a hole has no such boundary crossing.
  for (final ring in rings) {
    if (_ringsTouchOrCross(ring, cell)) return true;
  }

  // A filled feature vertex inside the cell, or a cell vertex in the filled
  // portion of the feature, catches containment without boundary crossings.
  if (shell.any((point) => _pointInRing(point, cell))) return true;
  return cell.any((point) => _pointInFilledPolygon(point, rings));
}

bool _pointInFilledPolygon(GeoPoint point, List<List<GeoPoint>> rings) {
  if (!_pointInRing(point, rings.first)) return false;
  for (final hole in rings.skip(1)) {
    if (_pointInRing(point, hole)) return false;
  }
  return true;
}

bool _ringsTouchOrCross(List<GeoPoint> first, List<GeoPoint> second) {
  if (first.length < 2 || second.length < 2) return false;
  for (var i = 0; i < first.length; i++) {
    final a = first[i];
    final b = first[(i + 1) % first.length];
    for (var j = 0; j < second.length; j++) {
      final c = second[j];
      final d = second[(j + 1) % second.length];
      if (_segmentsIntersect(a, b, c, d)) return true;
    }
  }
  return false;
}

bool _pointInRing(GeoPoint point, List<GeoPoint> ring) {
  if (ring.length < 3) return false;
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final a = ring[j];
    final b = ring[i];
    if (_pointOnSegment(point, a, b)) return true;
    final crosses =
        (a.latitude > point.latitude) != (b.latitude > point.latitude);
    if (crosses &&
        point.longitude <
            (b.longitude - a.longitude) *
                    (point.latitude - a.latitude) /
                    (b.latitude - a.latitude) +
                a.longitude) {
      inside = !inside;
    }
  }
  return inside;
}

bool _segmentsIntersect(GeoPoint a, GeoPoint b, GeoPoint c, GeoPoint d) {
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

double _orientation(GeoPoint a, GeoPoint b, GeoPoint c) =>
    (b.longitude - a.longitude) * (c.latitude - a.latitude) -
    (b.latitude - a.latitude) * (c.longitude - a.longitude);

bool _pointOnSegment(GeoPoint point, GeoPoint a, GeoPoint b) {
  const epsilon = 1e-12;
  return _orientation(a, b, point).abs() <= epsilon &&
      point.longitude >= math.min(a.longitude, b.longitude) - epsilon &&
      point.longitude <= math.max(a.longitude, b.longitude) + epsilon &&
      point.latitude >= math.min(a.latitude, b.latitude) - epsilon &&
      point.latitude <= math.max(a.latitude, b.latitude) + epsilon;
}

class _Bounds {
  const _Bounds(
    this.minLongitude,
    this.minLatitude,
    this.maxLongitude,
    this.maxLatitude,
  );

  factory _Bounds.fromPoints(Iterable<GeoPoint> points) {
    final list = points.toList(growable: false);
    if (list.isEmpty) return const _Bounds(0, 0, 0, 0);
    return _Bounds(
      list.map((point) => point.longitude).reduce(math.min),
      list.map((point) => point.latitude).reduce(math.min),
      list.map((point) => point.longitude).reduce(math.max),
      list.map((point) => point.latitude).reduce(math.max),
    );
  }

  final double minLongitude;
  final double minLatitude;
  final double maxLongitude;
  final double maxLatitude;

  bool intersectsInclusive(_Bounds other) =>
      minLongitude <= other.maxLongitude &&
      maxLongitude >= other.minLongitude &&
      minLatitude <= other.maxLatitude &&
      maxLatitude >= other.minLatitude;
}
