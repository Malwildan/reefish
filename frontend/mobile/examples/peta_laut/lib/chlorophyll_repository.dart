import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'geodata.dart';

// Memuat satu entri per sel, mempertahankan 24 entri dalam asset terpisah.
// Nomor adalah urutan ekspor; tidak menyatakan waktu atau kualitas data.
class ChlorophyllRepository {
  final Map<int, Map<GridId, double>> _cache = {};

  Future<Map<GridId, double>> loadEntry(int entry, MarineData reference) async {
    if (entry < 1 || entry > 24) throw RangeError.range(entry, 1, 24);
    if (_cache.containsKey(entry)) {
      final values = _cache.remove(entry)!;
      _cache[entry] = values;
      return values;
    }
    final name = entry.toString().padLeft(2, '0');
    final text = await rootBundle.loadString(
        'assets/geodata/klorofil_a/blok_$name.csv');
    final samples = await compute(parseSamples, text);
    if (samples.length != reference.cells.length) {
      throw const FormatException('Jumlah sel klorofil berbeda dari referensi');
    }
    final values = <GridId, double>{};
    for (final row in samples.entries) {
      final cell = reference.cells[row.key];
      if (cell == null || (cell.lat - row.value.lat).abs() > 1e-7 ||
          (cell.lon - row.value.lon).abs() > 1e-7) {
        throw FormatException('Klorofil tidak selaras pada ${row.key}');
      }
      values[row.key] = row.value.value;
    }
    _cache[entry] = values;
    while (_cache.length > 2) {
      _cache.remove(_cache.keys.first);
    }
    return values;
  }
}
