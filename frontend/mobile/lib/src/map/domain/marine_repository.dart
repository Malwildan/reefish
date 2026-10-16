import 'marine_data.dart';

abstract interface class MarineRepository {
  Future<MarineDataset> loadBase();

  /// Loads one source-order chlorophyll entry without combining entries.
  Future<Map<String, double>> loadChlorophyll(int entry);
}
