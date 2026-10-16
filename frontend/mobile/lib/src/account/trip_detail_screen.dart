import 'package:flutter/material.dart';

import '../journey/domain/journey_models.dart';
import '../journey/domain/journey_repository.dart';
import '../journey/presentation/journey_full_map_screen.dart';
import '../journey/presentation/widgets/journey_dashboard_map.dart';
import '../theme/reef_fish_theme.dart';
import '../journey/presentation/widgets/reef_bottom_navigation.dart';

class TripDetailScreen extends StatefulWidget {
  const TripDetailScreen({
    required this.repository,
    required this.tripId,
    this.onStartJourney,
    this.trackMapBuilder,
    super.key,
  });

  final JourneyRepository repository;
  final String tripId;
  final VoidCallback? onStartJourney;
  final Widget Function(JourneyTripDetail trip)? trackMapBuilder;

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  JourneyTripDetail? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.repository.getTripDetail(
        widget.tripId,
        track: 'simplified',
      );
      if (mounted) {
        setState(() {
          _detail = detail;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Detail perjalanan belum dapat dimuat.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: ReefishColors.canvas,
    bottomNavigationBar: ReefBottomNavigation(
      onHome: () => Navigator.of(context).popUntil((route) => route.isFirst),
      onProfile: () => Navigator.of(context).maybePop(),
      onSail: widget.onStartJourney,
    ),
    body: SafeArea(
      bottom: false,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Coba lagi'),
                    ),
                  ],
                ),
              ),
            )
          : _content(_detail!),
    ),
  );

  Widget _content(JourneyTripDetail trip) => Column(
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          children: [
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Kembali',
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFE29579),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Detail perjalanan',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '${_date(trip.departedAt)} · ${_time(trip.departedAt)}–${_time(trip.returnedAt)}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              '${_location(trip.departure)} · ${_sourceLabel(trip.source)}',
              style: const TextStyle(
                color: ReefishColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 30),
            _whiteCard(
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PERKIRAAN HASIL BERSIH',
                    style: TextStyle(
                      color: ReefishColors.textSecondary,
                      fontSize: 11,
                      letterSpacing: .2,
                    ),
                  ),
                  SizedBox(height: 18),
                  Text(
                    '—',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Nilai belum tersedia pada catatan perjalanan.',
                    style: TextStyle(
                      color: ReefishColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _whiteCard(
              minHeight: 224,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Rincian perjalanan',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 24),
                  _metricRow('Hasil tangkapan', _number(trip.catchKg, 'kg')),
                  _metricRow('BBM terpakai', _number(trip.fuelLiters, 'L')),
                  _metricRow('Biaya BBM', '—'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1D5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tersimpan di akun',
                    style: TextStyle(
                      color: Color(0xFF82551A),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Detail perjalanan berhasil dimuat dari akun ini.',
                    style: TextStyle(color: Color(0xFF82551A), fontSize: 11),
                  ),
                ],
              ),
            ),
            if (trip.track.length >= 2) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => JourneyFullMapScreen(
                      center: trip.departure,
                      homePort: trip.departure,
                      map:
                          widget.trackMapBuilder?.call(trip) ??
                          JourneyDashboardMap(
                            track: trip.track,
                            departure: trip.departure,
                            fishingPoint: trip.fishingPoints.firstOrNull?.point,
                            center: trip.departure,
                            rounded: false,
                          ),
                    ),
                  ),
                ),
                icon: const Icon(Icons.route),
                label: const Text('Lihat rekaman perjalanan'),
              ),
            ],
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 33),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Kembali ke riwayat'),
          ),
        ),
      ),
    ],
  );

  Widget _whiteCard({required Widget child, double minHeight = 0}) => Container(
    constraints: BoxConstraints(minHeight: minHeight),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: ReefishColors.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );

  Widget _metricRow(String title, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(color: ReefishColors.textSecondary),
          ),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

String _number(double? value, String unit) => value == null
    ? '—'
    : '${value.toStringAsFixed(1).replaceAll('.', ',')} $unit';

String _location(JourneyLatLng? point) => point == null
    ? 'Lokasi tidak tersedia'
    : '${point.lat.toStringAsFixed(5)}, ${point.lng.toStringAsFixed(5)}';

String _sourceLabel(String? source) => switch (source) {
  'manual' => 'Tanpa pemantauan',
  'sailing' => 'Pantau langsung',
  'onboarding' => 'Pencatatan awal',
  _ => 'Mode tidak tersedia',
};

String _date(DateTime? value) {
  if (value == null) return 'Tanggal tidak tersedia';
  const months = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];
  final local = value.toUtc().add(const Duration(hours: 7));
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

String _time(DateTime? value) {
  if (value == null) return '—';
  final local = value.toUtc().add(const Duration(hours: 7));
  return '${local.hour.toString().padLeft(2, '0')}.${local.minute.toString().padLeft(2, '0')}';
}
