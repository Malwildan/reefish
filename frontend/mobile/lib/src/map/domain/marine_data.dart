import 'geo_point.dart';

/// Scalar map selection. [none] leaves every scalar layer hidden.
enum MarineScalarLayer { none, fish, temperature, depth, chlorophyll }

enum MarineDataOrigin { bundledSnapshot, authenticatedBackend }

/// The canonical grid data used by the marine map.
class MarineCell {
  const MarineCell({
    required this.gridX,
    required this.gridY,
    required this.point,
    required this.fish,
    required this.temperature,
    required this.depth,
    required this.cellId,
  });

  /// The one-based local source grid index, retained for provenance.
  final int gridX;
  final int gridY;
  final GeoPoint point;

  /// Null is source NoData. It must not be filled from an older snapshot.
  final double? fish;
  final double? temperature;
  final double? depth;

  /// Stable MetricGrid500 ID, independent of map zoom or viewport.
  final String cellId;
}

/// A GeoJSON area feature, retaining polygon, ring, and point nesting.
///
/// Ring zero in each polygon is its exterior; later rings are holes. Properties
/// are kept as supplied by the source and are not interpreted by this model.
class MarineAreaFeature {
  const MarineAreaFeature({
    required this.id,
    required this.polygons,
    required this.properties,
  });

  final String id;
  final List<List<List<GeoPoint>>> polygons;
  final Map<String, Object?> properties;
}

class MarineDataset {
  const MarineDataset({
    required this.cells,
    required this.coral,
    required this.mangrove,
    this.origin = MarineDataOrigin.bundledSnapshot,
    this.period,
    this.chlorophyllPeriods = const [],
  });

  /// Keyed by the stable MetricGrid500 [MarineCell.cellId].
  final Map<String, MarineCell> cells;
  final List<MarineAreaFeature> coral;
  final List<MarineAreaFeature> mangrove;
  final MarineDataOrigin origin;

  /// Period returned by the backend for its current layer response, if known.
  final String? period;
  final List<String> chlorophyllPeriods;
}
