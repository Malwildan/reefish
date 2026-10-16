import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/reef_fish_theme.dart';
import '../domain/journey_insights.dart';
import '../domain/journey_models.dart';
import 'widgets/journey_dashboard_map.dart';
import 'widgets/reef_bottom_navigation.dart';

/// Full-screen read-only OSM map with the canonical 500 m grid overlay.
class JourneyFullMapScreen extends StatelessWidget {
  const JourneyFullMapScreen({
    this.homePort,
    this.center,
    this.plannedPoint,
    this.insights,
    this.onBack,
    this.map,
    super.key,
  });

  final JourneyLatLng? homePort;
  final JourneyLatLng? center;
  final JourneyLatLng? plannedPoint;
  final JourneyInsights? insights;
  final VoidCallback? onBack;
  final Widget? map;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: ReefishColors.canvas,
    body: SafeArea(
      child: Column(
        children: [
          SizedBox(
            height: 64,
            child: Row(
              children: [
                const SizedBox(width: 28),
                _BackButton(onPressed: onBack),
                const SizedBox(width: 12),
                const Text(
                  'Peta Laut',
                  style: TextStyle(
                    color: ReefishColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                map ??
                    JourneyDashboardMap(
                      homePort: homePort,
                      center: center,
                      plannedPoint: plannedPoint,
                      rounded: false,
                    ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Full recommendation detail page. The point and all metrics come from the
/// recommendation response; missing values are never inferred from the map.
class JourneyRecommendationDetailScreen extends StatelessWidget {
  const JourneyRecommendationDetailScreen({
    required this.recommendation,
    this.insights,
    this.homePort,
    this.onBack,
    this.onStartJourney,
    this.onProfile,
    this.map,
    this.now,
    super.key,
  });

  final JourneyRecommendation recommendation;
  final JourneyInsights? insights;
  final JourneyLatLng? homePort;
  final VoidCallback? onBack;
  final VoidCallback? onStartJourney;
  final VoidCallback? onProfile;
  final Widget? map;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    DateTime currentTime() => now?.call() ?? DateTime.now();
    final usable = insights?.recommendationsUsableAt(currentTime()) ?? false;
    final catchValue = _recommendationCatch(recommendation);
    final viewport = MediaQuery.sizeOf(context);
    final mapHeight = math.min(
      210.0,
      math.min(viewport.width * .55, viewport.height * .25),
    );
    return Scaffold(
      backgroundColor: ReefishColors.canvas,
      bottomNavigationBar: ReefBottomNavigation(
        active: ReefTab.home,
        onHome: onBack ?? () => Navigator.of(context).maybePop(),
        onProfile: onProfile,
        onSail: onStartJourney == null
            ? null
            : () {
                if (insights?.recommendationsUsableAt(currentTime()) ?? false) {
                  onStartJourney!();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Rekomendasi kedaluwarsa. Muat rekomendasi terbaru.',
                      ),
                    ),
                  );
                }
              },
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              height: 80,
              child: Row(
                children: [
                  const SizedBox(width: 24),
                  _BackButton(onPressed: onBack),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Detail rekomendasi',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ReefishColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 2, 24, 16),
                children: [
                  Text(
                    _recommendationType(recommendation.type),
                    style: const TextStyle(
                      color: ReefishColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _recommendationCoordinates(recommendation.point),
                    style: const TextStyle(
                      color: ReefishColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  if (!usable)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Rekomendasi kedaluwarsa atau waktu berlakunya belum tersedia.',
                        style: TextStyle(
                          color: ReefishColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: mapHeight,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          map ??
                              JourneyDashboardMap(
                                homePort: homePort,
                                center: recommendation.point,
                                plannedPoint: recommendation.point,
                              ),
                          Positioned(
                            right: 12,
                            top: 12,
                            child: Material(
                              color: ReefishColors.textPrimary,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => Navigator.of(context).push<void>(
                                  MaterialPageRoute<void>(
                                    builder: (_) => JourneyFullMapScreen(
                                      homePort: homePort,
                                      center: recommendation.point,
                                      plannedPoint: recommendation.point,
                                      insights: insights,
                                    ),
                                  ),
                                ),
                                child: const SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Center(
                                    child: Icon(
                                      Icons.open_in_full,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _NoticeCard(
                    title: 'Area direkomendasikan',
                    body: 'Periksa lokasi dan batas area sebelum berangkat.',
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          label: 'Potensi tangkapan',
                          value: catchValue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          label: 'Estimasi BBM',
                          value: _formatNumber(
                            recommendation.predictedFuelLiters,
                            'L',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Rekomendasi adalah perkiraan. Cek cuaca dan batas area sebelum melaut.',
                    style: TextStyle(
                      color: ReefishColors.textSecondary,
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const SizedBox(height: 4),
                  Text(
                    insights?.isFallback == true
                        ? 'Sumber: estimasi heuristik'
                        : 'Sumber: layanan rekomendasi',
                    style: const TextStyle(
                      color: ReefishColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  if (recommendation.reason != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      recommendation.reason!,
                      style: const TextStyle(
                        color: ReefishColors.textPrimary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                  _DetailRow(
                    label: 'Waktu berangkat',
                    value: recommendation.departureTime ?? '—',
                  ),
                  _DetailRow(
                    label: 'Waktu kembali',
                    value: recommendation.returnTime ?? '—',
                  ),
                  if (insights?.generatedAt != null)
                    _DetailRow(
                      label: 'Dibuat',
                      value: _dateTime(insights!.generatedAt),
                    ),
                  if (insights?.validUntil != null)
                    _DetailRow(
                      label: 'Berlaku hingga: ',
                      value: _dateTime(insights!.validUntil),
                    ),
                  if (recommendation.confidence != null)
                    _DetailRow(
                      label: 'Keyakinan model',
                      value:
                          '${(recommendation.confidence! * 100).toStringAsFixed(0)}%',
                    ),
                  _DetailRow(
                    label: 'Jarak dari pelabuhan',
                    value: _formatNumber(
                      recommendation.distanceFromPortKm,
                      'km',
                    ),
                  ),
                  if (recommendation.weatherSummary case final weather?) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Cuaca pada rekomendasi',
                      style: TextStyle(
                        color: ReefishColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    _DetailRow(
                      label: 'Angin',
                      value: _formatNumber(weather.windSpeedMs, 'm/dtk'),
                    ),
                    _DetailRow(
                      label: 'Gelombang',
                      value: _formatNumber(weather.waveHeightM, 'm'),
                    ),
                    _DetailRow(label: 'Risiko', value: weather.risk ?? '—'),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Kembali',
    button: true,
    child: Material(
      color: const Color(0xFFD8896A),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed ?? () => Navigator.of(context).maybePop(),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Center(
            child: SvgPicture.asset(
              'assets/icons/login-AkarIconsArrowLeft-b559ec96-131a-4c84-b0d4-8c5f220aab8d.svg',
              width: 22,
              height: 22,
            ),
          ),
        ),
      ),
    ),
  );
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 80),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: ReefishColors.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: ReefishColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: const TextStyle(
            color: ReefishColors.textPrimary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 76),
    padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: ReefishColors.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: ReefishColors.textSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: ReefishColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: ReefishColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: ReefishColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

String _recommendationType(String type) => switch (type) {
  'fuel_saving' => 'Efisiensi BBM',
  'catch_max' => 'Peningkatan Tangkapan',
  'balanced' => 'Seimbang',
  'habitual' => 'Kebiasaan Anda',
  _ => 'Rekomendasi',
};

String _recommendationCatch(JourneyRecommendation recommendation) {
  final range = recommendation.catchRangeKg;
  if (range != null) return '${range[0]}–${range[1]} kg';
  return _formatNumber(recommendation.predictedCatchKg, 'kg');
}

String _recommendationCoordinates(JourneyLatLng? point) {
  if (point == null) return 'Lokasi belum tersedia';
  final latHemisphere = point.lat < 0 ? 'S' : 'N';
  final lngHemisphere = point.lng < 0 ? 'W' : 'E';
  return '${point.lat.abs().toStringAsFixed(4)}° $latHemisphere, ${point.lng.abs().toStringAsFixed(4)}° $lngHemisphere';
}

String _formatNumber(double? value, String suffix) {
  if (value == null) return '—';
  final shown = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$shown $suffix';
}

String _dateTime(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
