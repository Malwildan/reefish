import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'geodata.dart';
import 'grid_projection.dart';

enum LayerId { coral, fish, chlorophyll, mangrove, temperature, depth, grid }

const layerLabels = {
  LayerId.coral: 'Coral (kode 1, sementara)',
  LayerId.fish: 'Potensi ikan (nilai)',
  LayerId.chlorophyll: 'Klorofil-a (pratinjau entri)',
  LayerId.mangrove: 'Mangrove 2023',
  LayerId.temperature: 'Suhu laut (nilai)',
  LayerId.depth: 'Kedalaman (nilai)',
  LayerId.grid: 'Grid 500 m (zoom ≥12)',
};

// Batas style mengikuti rentang snapshot; bukan ambang ilmiah.
Color thematicColor(LayerId layer, Cell c, double opacity,
    {double? chlorophyll}) {
  final (v, min, max, low, high) = switch (layer) {
    LayerId.fish => (c.fish, 1.0, 100.0,
        const Color(0xFFFFFFCC), const Color(0xFF006837)),
    LayerId.temperature => (c.temperature, 27.964, 30.391,
        const Color(0xFF2166AC), const Color(0xFFB2182B)),
    LayerId.depth => (c.depth, 18.0, 5000.0,
        const Color(0xFFDEEBF7), const Color(0xFF08306B)),
    LayerId.chlorophyll => (chlorophyll!, 0.0998, 5.1405,
        const Color(0xFFFFFFCC), const Color(0xFF004529)),
    _ => throw ArgumentError('Bukan layer tematik'),
  };
  final t = ((v - min) / (max - min)).clamp(0.0, 1.0).toDouble();
  return Color.lerp(low, high, t)!.withValues(alpha: opacity);
}

List<Polygon<String>> areaPolygons(List<AreaPart> parts, Color color,
    {bool onlyCoralCodeOne = false}) {
  return [
    for (final part in parts)
      if (!onlyCoralCodeOne ||
          (part.properties['value'] as num?)?.toDouble() == 1.0)
        Polygon<String>(
          points: [for (final p in part.rings.first) LatLng(p[1], p[0])],
          holePointsList: [for (final ring in part.rings.skip(1))
            [for (final p in ring) LatLng(p[1], p[0])]],
          color: color, borderColor: color, borderStrokeWidth: 0.7,
        ),
  ];
}

List<Polygon<String>> cellPolygons(Iterable<Cell> cells,
    GridProjection projection, LayerId layer, double opacity,
    {Map<GridId, double> chlorophyll = const {}}) => [
  for (final c in cells)
    if (layer != LayerId.chlorophyll || chlorophyll.containsKey(c.id))
      Polygon<String>(points: projection.ring(c.id),
        color: thematicColor(layer, c, opacity,
            chlorophyll: chlorophyll[c.id]), borderStrokeWidth: 0),
];

// Berbagi vertex dan deduplikasi sisi; garis tetangga digambar satu kali.
List<Polyline<String>> gridLines(Iterable<Cell> cells, GridProjection p) {
  final edges = <String, Polyline<String>>{};
  for (final c in cells) {
    final x = c.id.$1 - 1, y = c.id.$2 - 1;
    final specs = [
      ('h:$x:$y', (x, y), (x + 1, y)),
      ('h:$x:${y + 1}', (x, y + 1), (x + 1, y + 1)),
      ('v:$x:$y', (x, y), (x, y + 1)),
      ('v:${x + 1}:$y', (x + 1, y), (x + 1, y + 1)),
    ];
    for (final e in specs) {
      edges.putIfAbsent(e.$1, () => Polyline<String>(
          points: [p.vertex(e.$2.$1, e.$2.$2), p.vertex(e.$3.$1, e.$3.$2)],
          color: const Color(0x77555555), strokeWidth: 0.5));
    }
  }
  return edges.values.toList();
}
