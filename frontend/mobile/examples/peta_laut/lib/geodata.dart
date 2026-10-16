import 'dart:convert';
import 'package:csv/csv.dart';

typedef GridId = (int, int);

class Sample {
  final GridId id;
  final double lat, lon, value;
  const Sample(this.id, this.lat, this.lon, this.value);
}

class Cell {
  final GridId id;
  final double lat, lon, fish, temperature, depth;
  const Cell(this.id, this.lat, this.lon, this.fish,
      this.temperature, this.depth);
}

class AreaPart {
  final String id;
  // Setiap ring berupa pasangan [longitude, latitude]. Ring 0 = exterior.
  final List<List<List<double>>> rings;
  final Map<String, dynamic> properties;
  const AreaPart(this.id, this.rings, this.properties);
}

class MarineData {
  final Map<GridId, Cell> cells;
  final List<AreaPart> coral, mangrove;
  const MarineData(this.cells, this.coral, this.mangrove);
}

Map<GridId, Sample> parseSamples(String text) {
  final table = Csv(fieldDelimiter: ',').decode(text.replaceFirst('\uFEFF', ''));
  if (table.isEmpty) throw const FormatException('CSV kosong');
  final headers = table.first.map((v) => v.toString().trim()).toList();
  const expected = ['grid_x', 'grid_y', 'latitude', 'longitude', 'value'];
  if (headers.length != 5 || headers.toSet().length != 5 ||
      !expected.every(headers.contains)) {
    throw FormatException('Header CSV tidak sesuai: $headers');
  }
  final out = <GridId, Sample>{};
  for (var i = 1; i < table.length; i++) {
    final row = table[i];
    if (row.every((v) => v.toString().trim().isEmpty)) continue;
    if (row.length != headers.length) {
      throw FormatException('Jumlah kolom salah pada baris ${i + 1}');
    }
    double number(String key) {
      final v = double.tryParse(row[headers.indexOf(key)].toString().trim());
      if (v == null || !v.isFinite) {
        throw FormatException('$key tidak valid pada baris ${i + 1}');
      }
      return v;
    }
    final x = number('grid_x'), y = number('grid_y');
    if (x != x.roundToDouble() || y != y.roundToDouble() ||
        x < 1 || x > 187 || y < 1 || y > 177) {
      throw FormatException('Indeks grid tidak valid pada baris ${i + 1}');
    }
    final lat = number('latitude'), lon = number('longitude');
    if (lat < -9.15 || lat > -8.35 || lon < 112.25 || lon > 113.10) {
      throw FormatException('Titik di luar AOI pada baris ${i + 1}');
    }
    final id = (x.toInt(), y.toInt());
    if (out.containsKey(id)) throw FormatException('Grid duplikat: $id');
    out[id] = Sample(id, lat, lon, number('value'));
  }
  return out;
}

List<AreaPart> parseAreas(String text) {
  final root = jsonDecode(text) as Map<String, dynamic>;
  if (root['type'] != 'FeatureCollection') {
    throw const FormatException('Harus FeatureCollection');
  }
  final result = <AreaPart>[];
  final features = root['features'] as List<dynamic>;
  for (var i = 0; i < features.length; i++) {
    final f = features[i] as Map<String, dynamic>;
    final g = f['geometry'] as Map<String, dynamic>;
    final props = Map<String, dynamic>.from(f['properties'] as Map? ?? {});
    final coords = g['coordinates'] as List<dynamic>;
    final List<dynamic> polygons;
    if (g['type'] == 'Polygon') {
      polygons = [coords];
    } else if (g['type'] == 'MultiPolygon') {
      polygons = coords;
    } else {
      throw FormatException('Geometri tidak didukung: ${g['type']}');
    }
    for (var p = 0; p < polygons.length; p++) {
      final rings = <List<List<double>>>[];
      for (final rawRing in polygons[p] as List<dynamic>) {
        final ring = <List<double>>[];
        for (final rawPoint in rawRing as List<dynamic>) {
          final point = rawPoint as List<dynamic>;
          if (point.length < 2) throw const FormatException('Koordinat kurang');
          final lon = (point[0] as num).toDouble();
          final lat = (point[1] as num).toDouble();
          if (!lon.isFinite || !lat.isFinite ||
              lon < 112.25 || lon > 113.10 || lat < -9.15 || lat > -8.35) {
            throw const FormatException('Area belum dinormalisasi ke AOI');
          }
          ring.add([lon, lat]);
        }
        if (ring.length < 4 || ring.first[0] != ring.last[0] ||
            ring.first[1] != ring.last[1]) {
          throw const FormatException('Ring tidak tertutup');
        }
        rings.add(ring);
      }
      if (rings.isEmpty) throw const FormatException('Polygon tanpa ring');
      result.add(AreaPart('${f['id'] ?? i}:$p', rings, props));
    }
  }
  return result;
}

// Fungsi top-level untuk compute(); hanya data biasa, tanpa widget/Color.
MarineData decodeMarineData(Map<String, String> texts) {
  final fish = parseSamples(texts['fish']!);
  final temperature = parseSamples(texts['temperature']!);
  final depth = parseSamples(texts['depth']!);
  if (fish.length != 31354 || temperature.length != fish.length ||
      depth.length != fish.length) {
    throw const FormatException('Jumlah sel berbeda dari snapshot audit');
  }
  final cells = <GridId, Cell>{};
  for (final entry in fish.entries) {
    final f = entry.value, t = temperature[entry.key], d = depth[entry.key];
    if (t == null || d == null || (t.lat - f.lat).abs() > 1e-7 ||
        (t.lon - f.lon).abs() > 1e-7 || (d.lat - f.lat).abs() > 1e-7 ||
        (d.lon - f.lon).abs() > 1e-7) {
      throw FormatException('Join tidak selaras pada ${entry.key}');
    }
    cells[entry.key] = Cell(entry.key, f.lat, f.lon,
        f.value, t.value, d.value);
  }
  return MarineData(cells, parseAreas(texts['coral']!),
      parseAreas(texts['mangrove']!));
}
