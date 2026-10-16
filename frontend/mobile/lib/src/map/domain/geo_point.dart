/// A geographic point in WGS84 decimal degrees.
class GeoPoint {
  const GeoPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

/// Geographic bounds in WGS84. East and north edges are exclusive for point
/// membership, matching the grid's lower-inclusive/upper-exclusive rule.
class GeoBounds {
  const GeoBounds({
    required this.west,
    required this.south,
    required this.east,
    required this.north,
  });

  final double west;
  final double south;
  final double east;
  final double north;

  bool contains(GeoPoint point) =>
      point.longitude >= west &&
      point.longitude < east &&
      point.latitude >= south &&
      point.latitude < north;

  bool intersects(GeoBounds other) =>
      west < other.east &&
      east > other.west &&
      south < other.north &&
      north > other.south;

  void validate() {
    if (![west, south, east, north].every((value) => value.isFinite) ||
        west < -180 ||
        east > 180 ||
        south < -90 ||
        north > 90 ||
        west >= east ||
        south >= north) {
      throw ArgumentError('Invalid WGS84 bounds');
    }
  }
}
