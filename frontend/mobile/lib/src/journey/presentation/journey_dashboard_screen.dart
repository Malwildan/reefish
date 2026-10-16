import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/reef_fish_theme.dart';
import '../domain/journey_insights.dart';
import '../domain/journey_models.dart';
import 'journey_full_map_screen.dart';
import 'journey_weather_widgets.dart';
import 'widgets/journey_dashboard_map.dart';
import 'widgets/reef_bottom_navigation.dart';

class JourneyDashboardScreen extends StatefulWidget {
  const JourneyDashboardScreen({
    this.dashboard,
    this.insights,
    this.loading = false,
    this.message,
    this.onRefresh,
    this.onStartJourney,
    this.onOpenMap,
    this.onOpenProfile,
    this.now,
    this.map,
    super.key,
  });

  final JourneyDashboard? dashboard;
  final JourneyInsights? insights;
  final bool loading;
  final String? message;
  final VoidCallback? onRefresh;
  final VoidCallback? onStartJourney;
  final VoidCallback? onOpenMap;
  final VoidCallback? onOpenProfile;
  final DateTime Function()? now;
  final Widget? map;

  @override
  State<JourneyDashboardScreen> createState() => _JourneyDashboardScreenState();
}

class _JourneyDashboardScreenState extends State<JourneyDashboardScreen> {
  final _recommendationController = ScrollController();
  double _scrollFraction = 0;

  @override
  void dispose() {
    _recommendationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = widget.dashboard;
    final insight = widget.insights;
    final weather = insight?.weather;
    final homePort = dashboard?.profile.boat?.homePort;
    final media = MediaQuery.of(context);
    final horizontalInset = math.min(
      24.0,
      math.max(16.0, (media.size.width - 382) / 2),
    );
    final recs = insight?.recommendations ?? const <JourneyRecommendation>[];
    final title = weather?.label == null
        ? 'Cuaca belum tersedia'
        : 'Cuaca hari ini ${weather!.label}';

    return Scaffold(
      backgroundColor: ReefishColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.axis == Axis.horizontal) {
                  final max = notification.metrics.maxScrollExtent;
                  final next = max <= 0
                      ? 0.0
                      : notification.metrics.pixels / max;
                  if ((_scrollFraction - next).abs() > .01 && mounted) {
                    setState(() => _scrollFraction = next.clamp(0, 1));
                  }
                }
                return false;
              },
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  horizontalInset,
                  19,
                  horizontalInset,
                  132,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: SizedBox(
                                  width: 192,
                                  child: Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: ReefishColors.textPrimary,
                                      fontSize: 24,
                                      height: 32 / 24,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -.4,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: SizedBox(
                                width: 59,
                                height: 52,
                                child: ClipRect(
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        left: -14,
                                        top: -19,
                                        width: 90,
                                        height: 90,
                                        child: Image.asset(
                                          'assets/journey/compass.png',
                                          fit: BoxFit.fill,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Material(
                                color: ReefishColors.primaryAction,
                                shape: const CircleBorder(
                                  side: BorderSide(color: ReefishColors.brand),
                                ),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => showModalBottomSheet<void>(
                                    context: context,
                                    builder: (_) => const SafeArea(
                                      child: Padding(
                                        padding: EdgeInsets.all(24),
                                        child: Text(
                                          'Pengumuman belum tersedia.',
                                        ),
                                      ),
                                    ),
                                  ),
                                  child: SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: Center(
                                      child: Semantics(
                                        label: 'Pengumuman',
                                        child: SvgPicture.asset(
                                          'assets/journey/notifications.svg',
                                          width: 24,
                                          height: 24,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Mau berlayar kemana hari ini?',
                          style: TextStyle(
                            color: ReefishColors.textPrimary,
                            fontSize: 14,
                            height: 22 / 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: math.min(
                        382.0,
                        media.size.width - horizontalInset * 2,
                      ),
                      child:
                          widget.map ??
                          JourneyDashboardMap(
                            homePort: homePort,
                            onExpand: widget.onOpenMap,
                          ),
                    ),
                    const SizedBox(height: 20),
                    JourneyWeatherStrip(weather: weather),
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 5),
                      child: JourneyWeatherAttribution(insights: insight),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Rekomendasi',
                      style: TextStyle(
                        color: ReefishColors.textPrimary,
                        fontSize: 24,
                        height: 32 / 24,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 256,
                      child: recs.isEmpty
                          ? _EmptyRecommendations(
                              loading: widget.loading,
                              message: insight?.recommendationMessage,
                            )
                          : ListView.separated(
                              controller: _recommendationController,
                              scrollDirection: Axis.horizontal,
                              clipBehavior: Clip.hardEdge,
                              itemCount: recs.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 16),
                              itemBuilder: (context, index) =>
                                  _RecommendationCard(
                                    recommendation: recs[index],
                                    fallback: insight?.isFallback ?? false,
                                    usable:
                                        insight?.recommendationsUsableAt(
                                          widget.now?.call() ?? DateTime.now(),
                                        ) ??
                                        false,
                                    onTap: () => _showRecommendation(
                                      context,
                                      recs[index],
                                      insight,
                                    ),
                                  ),
                            ),
                    ),
                    Center(
                      child: SizedBox(
                        width: 205,
                        height: 9,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Stack(
                            children: [
                              const ColoredBox(color: Color(0x66188E8B)),
                              Align(
                                alignment: Alignment(
                                  -1 + 2 * _scrollFraction,
                                  0,
                                ),
                                child: const FractionallySizedBox(
                                  widthFactor: .459,
                                  child: ColoredBox(color: ReefishColors.reef),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 48,
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: widget.onStartJourney,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ReefishColors.primaryAction,
                          foregroundColor: Colors.white,
                          elevation: 4,
                          shape: const StadiumBorder(),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Flexible(
                              child: Text(
                                'Mulai Berlayar',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SvgPicture.asset(
                              'assets/journey/sail.svg',
                              width: 22,
                              height: 22,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (widget.message != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        widget.message!,
                        style: const TextStyle(
                          color: ReefishColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      if (widget.onRefresh != null)
                        TextButton(
                          onPressed: widget.loading ? null : widget.onRefresh,
                          child: const Text('Muat ulang'),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 107,
              child: ReefBottomNavigation(
                active: ReefTab.home,
                onHome: widget.onRefresh,
                onProfile: widget.onOpenProfile,
                onSail: widget.onStartJourney,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRecommendation(
    BuildContext context,
    JourneyRecommendation recommendation,
    JourneyInsights? insights,
  ) {
    if (!(insights?.recommendationsUsableAt(
          widget.now?.call() ?? DateTime.now(),
        ) ??
        false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rekomendasi kedaluwarsa. Muat rekomendasi terbaru.'),
        ),
      );
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => JourneyRecommendationDetailScreen(
          recommendation: recommendation,
          insights: insights,
          homePort: widget.dashboard?.profile.boat?.homePort,
          onProfile: widget.onOpenProfile == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  widget.onOpenProfile!();
                },
          onStartJourney: widget.onStartJourney == null
              ? null
              : () {
                  if (!(insights?.recommendationsUsableAt(
                        widget.now?.call() ?? DateTime.now(),
                      ) ??
                      false)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Rekomendasi kedaluwarsa. Muat rekomendasi terbaru.',
                        ),
                      ),
                    );
                    return;
                  }
                  Navigator.of(context).pop();
                  widget.onStartJourney!();
                },
          now: widget.now,
        ),
      ),
    );
  }
}

String _number(double? value, String suffix, {bool convertMps = false}) {
  if (value == null) return '—';
  final shown = convertMps ? value * 3.6 : value;
  return '${shown == shown.roundToDouble() ? shown.toStringAsFixed(0) : shown.toStringAsFixed(1)} $suffix';
}

class _EmptyRecommendations extends StatelessWidget {
  const _EmptyRecommendations({required this.loading, this.message});
  final bool loading;
  final String? message;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: double.infinity,
      height: 132,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EFEC),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (loading) const SizedBox(height: 10),
          Text(
            loading
                ? 'Memuat rekomendasi…'
                : (message ?? 'Rekomendasi belum tersedia.'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ReefishColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    ),
  );
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.recommendation,
    required this.fallback,
    required this.usable,
    required this.onTap,
  });
  final JourneyRecommendation recommendation;
  final bool fallback;
  final bool usable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final type = _recommendationType(recommendation.type);
    return SizedBox(
      width: 283,
      height: 226,
      child: Material(
        color: ReefishColors.brand,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: usable ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  height: 60,
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: ReefishColors.canvas,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        usable
                            ? type
                            : (fallback
                                  ? 'Estimasi kedaluwarsa'
                                  : 'Rekomendasi kedaluwarsa'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ReefishColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _coordinates(recommendation.point),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ReefishColors.textPrimary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _CardValue(
                      icon: 'fish.svg',
                      label: 'Potensi Ikan',
                      value: usable ? _catch(recommendation) : 'Tidak berlaku',
                    ),
                    _CardValue(
                      icon: 'fuel.svg',
                      label: 'Estimasi BBM',
                      value: usable
                          ? _number(recommendation.predictedFuelLiters, 'L')
                          : 'Tidak berlaku',
                    ),
                  ],
                ),
                if (fallback)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Estimasi heuristik',
                      style: TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                  ),
                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: usable ? onTap : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16415E),
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      usable ? 'Lihat' : 'Kedaluwarsa',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardValue extends StatelessWidget {
  const _CardValue({
    required this.icon,
    required this.label,
    required this.value,
  });
  final String icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 111,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SvgPicture.asset('assets/journey/$icon', width: 18, height: 18),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

String _recommendationType(String type) => switch (type) {
  'fuel_saving' => 'Efisiensi Bensin',
  'catch_max' => 'Peningkatan Tangkapan',
  'balanced' => 'Seimbang',
  'habitual' => 'Kebiasaan Anda',
  _ => 'Rekomendasi',
};

String _catch(JourneyRecommendation recommendation) {
  final range = recommendation.catchRangeKg;
  if (range != null) return '${range[0]}–${range[1]} kg';
  return _number(recommendation.predictedCatchKg, 'kg');
}

String _coordinates(JourneyLatLng? point) {
  if (point == null) return 'Lokasi belum tersedia';
  return '${point.lat.toStringAsFixed(4)}°, ${point.lng.toStringAsFixed(4)}°';
}
