import 'geo_point.dart';

/// A canonical 500 m cell. [polygon] is the complete projected square
/// transformed back to WGS84; it is never clipped to land, water, or AOI.
class GridCell {
  const GridCell({
    required this.row,
    required this.col,
    required this.id,
    required this.code,
    required this.polygon,
    required this.center,
  });

  final int row;
  final int col;
  final String id;
  final String code;
  final List<GeoPoint> polygon;
  final GeoPoint center;
}

class GridViewport {
  const GridViewport({required this.cells, required this.exceeded});

  final List<GridCell> cells;

  /// True when the candidate range was larger than [maxCells] and was
  /// rejected. No partial viewport is returned in that case.
  final bool exceeded;
}
