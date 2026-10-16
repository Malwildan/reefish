import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../map/domain/geo_point.dart';
import '../../../map/domain/metric_grid_500.dart';
import '../../domain/journey_models.dart';

/// OSM context plus the app's canonical UTM 49S 500 m grid. The map never
/// paints an estimated hotspot or a recommendation prediction.
class JourneyDashboardMap extends StatefulWidget {
  const JourneyDashboardMap({
    this.homePort,
    this.center,
    this.departure,
    this.plannedPoint,
    this.currentPosition,
    this.fishingPoint,
    this.track = const [],
    this.rounded = true,
    this.followPosition = false,
    this.onExpand,
    this.onGridTap,
    super.key,
  });

  final JourneyLatLng? homePort;

  /// Optional viewport center for a read-only/full-screen map.
  final JourneyLatLng? center;
  final JourneyLatLng? departure;
  final JourneyLatLng? plannedPoint;
  final JourneyLatLng? currentPosition;
  final JourneyLatLng? fishingPoint;
  final List<JourneyLatLng> track;
  final bool rounded;
  final bool followPosition;
  final VoidCallback? onExpand;

  /// Enables read-only inspection of a canonical cell when supplied.
  final ValueChanged<GeoPoint>? onGridTap;

  @override
  State<JourneyDashboardMap> createState() => _JourneyDashboardMapState();
}

class _JourneyDashboardMapState extends State<JourneyDashboardMap> {
  static const _fallbackCenter = LatLng(-8.447, 112.683);
  final _grid = MetricGrid500();
  late final MapController _mapController = MapController();
  List<Polygon> _gridPolygons = const [];
  String? _selectedCellId;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    final point = widget.center ?? widget.homePort;
    _updateGrid(
      point == null
          ? const GeoBounds(
              west: 112.653,
              south: -8.477,
              east: 112.713,
              north: -8.417,
            )
          : _boundsAround(point),
    );
  }

  @override
  void didUpdateWidget(covariant JourneyDashboardMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = widget.currentPosition;
    if (_mapReady &&
        widget.followPosition &&
        current != null &&
        (current.lat != oldWidget.currentPosition?.lat ||
            current.lng != oldWidget.currentPosition?.lng)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_mapReady) return;
        _mapController.move(
          LatLng(current.lat, current.lng),
          _mapController.camera.zoom,
        );
      });
    }
    if (oldWidget.homePort?.lat != widget.homePort?.lat ||
        oldWidget.homePort?.lng != widget.homePort?.lng ||
        oldWidget.center?.lat != widget.center?.lat ||
        oldWidget.center?.lng != widget.center?.lng ||
        oldWidget.departure?.lat != widget.departure?.lat ||
        oldWidget.departure?.lng != widget.departure?.lng ||
        oldWidget.plannedPoint?.lat != widget.plannedPoint?.lat ||
        oldWidget.plannedPoint?.lng != widget.plannedPoint?.lng ||
        oldWidget.currentPosition?.lat != widget.currentPosition?.lat ||
        oldWidget.currentPosition?.lng != widget.currentPosition?.lng ||
        oldWidget.fishingPoint?.lat != widget.fishingPoint?.lat ||
        oldWidget.fishingPoint?.lng != widget.fishingPoint?.lng ||
        oldWidget.track.length != widget.track.length) {
      final point = widget.center ?? widget.homePort;
      _updateGrid(
        point == null
            ? const GeoBounds(
                west: 112.653,
                south: -8.477,
                east: 112.713,
                north: -8.417,
              )
            : _boundsAround(point),
      );
    }
  }

  GeoBounds _boundsAround(JourneyLatLng point) => GeoBounds(
    west: point.lng - 0.03,
    east: point.lng + 0.03,
    south: point.lat - 0.03,
    north: point.lat + 0.03,
  );

  void _updateGrid(GeoBounds bounds) {
    try {
      final viewport = _grid.enumerateViewport(bounds, maxCells: 600);
      _gridPolygons = viewport.cells
          .map(
            (cell) => Polygon(
              points: cell.polygon
                  .map((point) => LatLng(point.latitude, point.longitude))
                  .toList(),
              color: cell.id == _selectedCellId
                  ? const Color(0x3318C7C0)
                  : Colors.transparent,
              borderColor: cell.id == _selectedCellId
                  ? const Color(0xFF087F78)
                  : const Color(0xDD18C7C0),
              borderStrokeWidth: cell.id == _selectedCellId ? 2.5 : 1,
            ),
          )
          .toList(growable: false);
    } on RangeError {
      _gridPolygons = const [];
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final home = widget.homePort;
    final focus = widget.center ?? home;
    final center = focus == null
        ? _fallbackCenter
        : LatLng(focus.lat, focus.lng);
    final map = Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            onMapReady: () => _mapReady = true,
            initialCenter: center,
            initialZoom: 14,
            minZoom: 9,
            maxZoom: 17,
            cameraConstraint: CameraConstraint.containCenter(
              bounds: LatLngBounds(
                const LatLng(-9.15, 112.25),
                const LatLng(-8.35, 113.10),
              ),
            ),
            onMapEvent: (event) {
              final bounds = _mapController.camera.visibleBounds;
              _updateGrid(
                GeoBounds(
                  west: math.max(-180.0, bounds.west),
                  east: math.min(180.0, bounds.east),
                  south: math.max(-90.0, bounds.south),
                  north: math.min(90.0, bounds.north),
                ),
              );
            },
            onTap: widget.onGridTap == null
                ? null
                : (_, point) {
                    final geoPoint = GeoPoint(
                      latitude: point.latitude,
                      longitude: point.longitude,
                    );
                    try {
                      final cell = _grid.resolve(geoPoint);
                      _selectedCellId = cell.id;
                    } on RangeError {
                      _selectedCellId = null;
                    }
                    final bounds = _mapController.camera.visibleBounds;
                    _updateGrid(
                      GeoBounds(
                        west: bounds.west,
                        south: bounds.south,
                        east: bounds.east,
                        north: bounds.north,
                      ),
                    );
                    widget.onGridTap!(geoPoint);
                  },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.reefish.mobile',
              keepBuffer: 0,
            ),
            PolygonLayer(polygons: _gridPolygons),
            if (widget.track.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: widget.track
                        .map((point) => LatLng(point.lat, point.lng))
                        .toList(growable: false),
                    color: const Color(0xDD176A78),
                    strokeWidth: 4,
                  ),
                ],
              ),
            if (home != null ||
                widget.departure != null ||
                widget.plannedPoint != null ||
                widget.fishingPoint != null ||
                widget.currentPosition != null)
              MarkerLayer(
                markers: [
                  if (home != null) _marker(home, const Color(0xFF1E6387), 'H'),
                  if (widget.departure != null)
                    _marker(widget.departure!, const Color(0xFFB97049), 'B'),
                  if (widget.plannedPoint != null)
                    _marker(widget.plannedPoint!, const Color(0xFFC38A36), 'R'),
                  if (widget.fishingPoint != null)
                    _marker(widget.fishingPoint!, const Color(0xFF1C857A), 'T'),
                  if (widget.currentPosition != null)
                    _marker(
                      widget.currentPosition!,
                      const Color(0xFF334FAD),
                      '•',
                    ),
                ],
              ),
          ],
        ),
        Positioned(
          left: 6,
          bottom: 6,
          child: Material(
            color: const Color(0xEFFFFFFF),
            borderRadius: BorderRadius.circular(4),
            child: InkWell(
              onTap: () => launchUrl(
                Uri.parse('https://www.openstreetmap.org/copyright'),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  '© OpenStreetMap contributors',
                  style: TextStyle(fontSize: 10),
                ),
              ),
            ),
          ),
        ),
        if (home == null)
          Positioned(
            left: 10,
            bottom: 38,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xEFFFFFFF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text(
                  'Pelabuhan asal belum dipilih',
                  style: TextStyle(fontSize: 11, color: Color(0xFF102F3A)),
                ),
              ),
            ),
          ),
        if (widget.onExpand != null)
          Positioned(
            right: 12,
            top: 12,
            child: Material(
              color: const Color(0xFF102F3A),
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: widget.onExpand,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: SvgPicture.asset(
                      'assets/journey/expand.svg',
                      width: 24,
                      height: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    return widget.rounded
        ? ClipRRect(borderRadius: BorderRadius.circular(20), child: map)
        : map;
  }

  Marker _marker(JourneyLatLng point, Color color, String label) => Marker(
    point: LatLng(point.lat, point.lng),
    width: 28,
    height: 28,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: const Border.fromBorderSide(
          BorderSide(color: Colors.white, width: 3),
        ),
        boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 5)],
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 10,
          ),
        ),
      ),
    ),
  );
}
