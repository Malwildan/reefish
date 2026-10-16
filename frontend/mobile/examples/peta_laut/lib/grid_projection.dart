import 'package:latlong2/latlong.dart';
import 'package:proj4dart/proj4dart.dart' as proj;
import 'geodata.dart';

class GridProjection {
  static const originE = 637500.0, originN = 8988000.0, step = 500.0;
  final proj.Projection wgs = proj.Projection.get('EPSG:4326')!;
  final proj.Projection utm = proj.Projection.parse(
      '+proj=utm +zone=49 +south +datum=WGS84 +units=m +no_defs');
  final Map<(int, int), LatLng> _vertices = {};

  LatLng vertex(int ix, int iy) => _vertices.putIfAbsent((ix, iy), () {
    final p = utm.transform(wgs, proj.Point(
        x: originE + ix * step, y: originN + iy * step));
    return LatLng(p.y, p.x);
  });

  List<LatLng> ring(GridId id) {
    final x = id.$1 - 1, y = id.$2 - 1;
    return [vertex(x, y), vertex(x + 1, y),
      vertex(x + 1, y + 1), vertex(x, y + 1)];
  }

  GridId idAt(LatLng position) {
    final p = wgs.transform(utm,
        proj.Point(x: position.longitude, y: position.latitude));
    return (((p.x - originE) / step).floor() + 1,
        ((p.y - originN) / step).floor() + 1);
  }

  void validateCenter(Cell cell) {
    final p = wgs.transform(utm, proj.Point(x: cell.lon, y: cell.lat));
    final e = originE + (cell.id.$1 - 0.5) * step;
    final n = originN + (cell.id.$2 - 0.5) * step;
    if ((p.x - e).abs() > 0.05 || (p.y - n).abs() > 0.05) {
      throw FormatException('Origin grid tidak cocok pada ${cell.id}');
    }
  }
}
