import 'dart:collection';

import 'grid_cell.dart';
import 'marine_data.dart';
import 'marine_geometry.dart';

/// Exact marine area matches for one canonical grid cell.
class MarineCellFeatures {
  const MarineCellFeatures({required this.coral, required this.mangrove});

  final List<MarineAreaFeature> coral;
  final List<MarineAreaFeature> mangrove;
}

/// Bounded, lazy lookup of coral and mangrove features for selected cells.
///
/// The lookup is scoped to one immutable [MarineDataset] snapshot. It prepares
/// feature polygon bounds once, but only computes and retains intersections
/// for cells requested by the caller.
class MarineCellLookup {
  MarineCellLookup(MarineDataset dataset, {this.capacity = 128})
    : _coralIndex = MarineFeatureIndex(dataset.coral),
      _mangroveIndex = MarineFeatureIndex(dataset.mangrove) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must be positive');
    }
  }

  final int capacity;
  final MarineFeatureIndex _coralIndex;
  final MarineFeatureIndex _mangroveIndex;
  final LinkedHashMap<String, MarineCellFeatures> _cache = LinkedHashMap();

  /// Returns exact polygon-footprint matches for [cell], reusing recent work.
  ///
  /// Cell IDs are canonical and identify the immutable cell polygon within a
  /// dataset snapshot. The cache is bounded by [capacity] and uses LRU order.
  MarineCellFeatures featuresFor(GridCell cell) {
    final cached = _cache.remove(cell.id);
    if (cached != null) {
      _cache[cell.id] = cached;
      return cached;
    }

    final result = MarineCellFeatures(
      coral: _coralIndex.intersecting(cell),
      mangrove: _mangroveIndex.intersecting(cell),
    );
    _cache[cell.id] = result;
    if (_cache.length > capacity) _cache.remove(_cache.keys.first);
    return result;
  }
}
