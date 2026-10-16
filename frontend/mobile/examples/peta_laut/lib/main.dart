import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'geodata.dart';
import 'grid_projection.dart';
import 'map_layers.dart';
import 'chlorophyll_repository.dart';

void main() => runApp(const MaterialApp(home: MarineMapPage()));

final aoi = LatLngBounds(const LatLng(-9.15, 112.25),
    const LatLng(-8.35, 113.10));

class MarineMapPage extends StatefulWidget {
  const MarineMapPage({super.key});
  @override
  State<MarineMapPage> createState() => _MarineMapPageState();
}

class _MarineMapPageState extends State<MarineMapPage> {
  final _controller = MapController();
  final _projection = GridProjection();
  final _chlorophyllRepository = ChlorophyllRepository();
  Map<GridId, double> _chlorophyllValues = {};
  int _chlorophyllEntry = 1;
  int _chlorophyllRequest = 0;
  bool _chlorophyllLoading = false;
  Object? _chlorophyllError;
  final _enabled = {LayerId.coral, LayerId.fish, LayerId.mangrove, LayerId.grid};
  final _opacity = {for (final id in LayerId.values) id: 0.55};
  final _layers = <LayerId, Widget>{};
  MarineData? _data;
  Object? _error;
  Timer? _timer;
  LatLngBounds? _view;
  double _zoom = 9;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      const paths = {
        'fish': 'potensi_ikan.csv', 'temperature': 'suhu_laut.csv',
        'depth': 'kedalaman_laut.csv', 'coral': 'coral.geojson',
        'mangrove': 'mangrove.geojson',
      };
      final entries = await Future.wait(paths.entries.map((e) async =>
          MapEntry(e.key, await rootBundle.loadString('assets/geodata/${e.value}'))));
      final data = await compute(decodeMarineData, Map<String, String>.fromEntries(entries));
      // QA penuh pusat grid dilakukan offline; cek kontrol saat startup.
      _projection.validateCenter(data.cells[(149, 1)]!);
      if (!mounted) return;
      _data = data;
      _refreshLayers();
      if (_enabled.contains(LayerId.chlorophyll)) {
        _loadChlorophyll(_chlorophyllEntry);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadChlorophyll(int entry) async {
    final request = ++_chlorophyllRequest;
    _chlorophyllEntry = entry;
    _chlorophyllValues = {};
    _chlorophyllError = null;
    _chlorophyllLoading = _data != null;
    _refreshLayers();
    if (_data == null) return;
    try {
      final values = await _chlorophyllRepository.loadEntry(entry, _data!);
      if (!mounted || request != _chlorophyllRequest) return;
      _chlorophyllValues = values;
    } catch (e) {
      if (!mounted || request != _chlorophyllRequest) return;
      _chlorophyllError = e;
    }
    if (!mounted || request != _chlorophyllRequest) return;
    _chlorophyllLoading = false;
    _refreshLayers();
  }

  void _refreshLayers() {
    final data = _data;
    if (!mounted) return;
    if (data == null) {
      setState(() {});
      return;
    }
    final view = _view ?? aoi;
    // Filter bbox, bukan hanya titik pusat, agar sel di tepi layar tidak hilang.
    // Margin 0.006° > setengah diagonal sel 500 m pada AOI ini.
    final visible = data.cells.values.where((c) =>
        c.lat >= view.south - 0.006 && c.lat <= view.north + 0.006 &&
        c.lon >= view.west - 0.006 && c.lon <= view.east + 0.006).toList();
    _layers.clear();
    for (final id in _enabled) {
      if (id == LayerId.coral || id == LayerId.mangrove) {
        final coral = id == LayerId.coral;
        final color = (coral ? const Color(0xFFF28E2B) : const Color(0xFF238443))
            .withValues(alpha: _opacity[id]!);
        _layers[id] = PolygonLayer<String>(
          polygons: areaPolygons(coral ? data.coral : data.mangrove,
            color, onlyCoralCodeOne: coral),
          polygonCulling: true, drawInSingleWorld: true,
        );
      } else if (id == LayerId.grid) {
        if (_zoom >= 12) {
          _layers[id] = IgnorePointer(child: PolylineLayer<String>(
              polylines: gridLines(visible, _projection),
              simplificationTolerance: 0, drawInSingleWorld: true));
        }
      } else {
        _layers[id] = PolygonLayer<String>(
            polygons: cellPolygons(visible, _projection, id, _opacity[id]!,
                chlorophyll: _chlorophyllValues),
            polygonCulling: true, simplificationTolerance: 0,
            drawInSingleWorld: true);
      }
    }
    setState(() {});
  }

  void _showCell(LatLng point) {
    if (!aoi.contains(point)) return;
    final id = _projection.idAt(point);
    final cell = _data?.cells[id];
    showModalBottomSheet<void>(context: context, builder: (context) =>
      SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Text(
        cell == null ? 'Tidak ada data pada sel $id' :
        'Sel ${id.$1}:${id.$2}\n'
        'Pusat: ${cell.lat}, ${cell.lon}\n'
        'Potensi ikan: ${cell.fish}\nSuhu: ${cell.temperature}\n'
        'Kedalaman: ${cell.depth}\n'
        'Klorofil-a, entri $_chlorophyllEntry: '
        '${_chlorophyllValues[id] ?? "belum dimuat"}\n'
        'Nomor entri hanya urutan ekspor, tanpa informasi waktu.\n'
        'Satuan dan waktu observasi CSV belum dikonfirmasi.',
      ))));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Peta laut — contoh handoff'), actions: [
      IconButton(icon: const Icon(Icons.fit_screen), tooltip: 'Kembali ke area',
        onPressed: () {
          if (_ready) _controller.fitCamera(CameraFit.bounds(
              bounds: aoi, padding: const EdgeInsets.all(24)));
        }),
    ]),
    drawer: Drawer(child: SafeArea(child: ListView(children: [
      const ListTile(title: Text('Layer dari bawah ke atas')),
      for (final id in LayerId.values) ...[
        SwitchListTile(title: Text(layerLabels[id]!), value: _enabled.contains(id),
          onChanged: (value) {
            if (value) { _enabled.add(id); } else { _enabled.remove(id); }
            _refreshLayers();
            if (id == LayerId.chlorophyll && value) {
              _loadChlorophyll(_chlorophyllEntry);
            }
          }),
        if (id == LayerId.chlorophyll && _enabled.contains(id)) ...[
          ListTile(title: const Text('Entri per sel (urutan ekspor)'),
            subtitle: const Text('Pratinjau; bukan periode atau nilai tunggal final.'),
            trailing: DropdownButton<int>(value: _chlorophyllEntry,
              items: [for (var i = 1; i <= 24; i++)
                DropdownMenuItem(value: i, child: Text('$i / 24'))],
              onChanged: (v) { if (v != null) _loadChlorophyll(v); })),
          if (_chlorophyllLoading) const LinearProgressIndicator(),
          if (_chlorophyllError != null)
            ListTile(title: Text('Gagal memuat klorofil: $_chlorophyllError'),
              trailing: IconButton(icon: const Icon(Icons.refresh),
                onPressed: () => _loadChlorophyll(_chlorophyllEntry))),
        ],
        if (id != LayerId.grid && _enabled.contains(id))
          Slider(value: _opacity[id]!, min: 0, max: 1, divisions: 20,
            label: '${(_opacity[id]! * 100).round()}%',
            onChanged: (v) { _opacity[id] = v; _refreshLayers(); }),
      ],
      const ListTile(title: Text('Legenda nilai snapshot'), subtitle: Text(
        'Ikan: kuning 1 → hijau 100\n'
        'Suhu: biru 27.964 → merah 30.391\n'
        'Kedalaman: biru muda 18 → biru tua 5000\n'
        'Klorofil-a: kuning muda 0.0998 → hijau tua 5.1405\n'
        'Rentang visual; satuan belum dikonfirmasi.\n'
        'Kode coral 1 ditampilkan sebagai asumsi sementara.')),
    ]))),
    body: Stack(children: [
      FlutterMap(mapController: _controller, options: MapOptions(
        initialCameraFit: CameraFit.bounds(bounds: aoi,
            padding: const EdgeInsets.all(24)),
        cameraConstraint: CameraConstraint.containCenter(bounds: aoi),
        minZoom: 7, maxZoom: 18,
        onMapReady: () { _ready = true; },
        onTap: (_, point) => _showCell(point),
        onPositionChanged: (camera, hasGesture) {
          _view = camera.visibleBounds; _zoom = camera.zoom;
          _timer?.cancel();
          _timer = Timer(const Duration(milliseconds: 150), _refreshLayers);
        },
      ), children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'id.example.marine_map_handoff',
          maxNativeZoom: 19),
        // Klorofil adalah layer tambahan setelah ikan; urutan lama tetap relatif.
        for (final id in LayerId.values)
          if (_layers.containsKey(id)) _layers[id]!,
        const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
      ]),
      if (_data == null && _error == null)
        const Center(child: CircularProgressIndicator()),
      if (_error != null)
        Center(child: Card(child: Padding(padding: const EdgeInsets.all(16),
          child: Text('Gagal memuat data: $_error')))),
    ]),
  );
}
