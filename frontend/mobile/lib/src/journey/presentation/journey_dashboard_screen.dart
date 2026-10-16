import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/reef_fish_theme.dart';
import '../domain/journey_insights.dart';
import '../domain/journey_models.dart';
import 'widgets/journey_dashboard_map.dart';

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
                    _WeatherStrip(weather: weather),
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 5),
                      child: weather == null
                          ? Text(
                              insight?.weatherMessage ??
                                  'Data cuaca belum tersedia.',
                              style: const TextStyle(
                                color: ReefishColors.textSecondary,
                                fontSize: 11,
                                height: 16 / 11,
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Sumber cuaca: ',
                                      style: TextStyle(
                                        color: ReefishColors.textSecondary,
                                        fontSize: 11,
                                        height: 16 / 11,
                                      ),
                                    ),
                                    _WeatherSourceLink(
                                      label: 'Open-Meteo',
                                      uri: Uri.parse(
                                        'https://open-meteo.com/en/docs',
                                      ),
                                    ),
                                    const Text(
                                      ' · ',
                                      style: TextStyle(
                                        color: ReefishColors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                    _WeatherSourceLink(
                                      label: 'DWD',
                                      uri: Uri.parse('https://www.dwd.de/'),
                                    ),
                                  ],
                                ),
                                Text(
                                  'Data dimuat: ${_dateTime(insight?.weatherFetchedAt)} · Prakiraan: ${_dateTime(weather.time)}',
                                  style: const TextStyle(
                                    color: ReefishColors.textSecondary,
                                    fontSize: 11,
                                    height: 16 / 11,
                                  ),
                                ),
                              ],
                            ),
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
                                          DateTime.now(),
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
              child: _BottomNavigation(
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ReefishColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _RecommendationDetails(
        recommendation: recommendation,
        insights: insights,
      ),
    );
  }
}

class _WeatherStrip extends StatelessWidget {
  const _WeatherStrip({required this.weather});
  final JourneyWeather? weather;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    height: 39,
    decoration: BoxDecoration(
      color: const Color(0xFFD9ECE8),
      border: Border.all(color: ReefishColors.reef, width: 2),
      borderRadius: BorderRadius.circular(40),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _WeatherMetric(
          icon: 'temperature.svg',
          value: _number(weather?.tempC, '°C'),
        ),
        _WeatherMetric(
          icon: 'wind.svg',
          value: _number(weather?.windSpeedMs, 'km/jam', convertMps: true),
        ),
        _WeatherMetric(
          icon: 'wave.svg',
          value: _number(weather?.waveHeightM, 'm'),
        ),
      ],
    ),
  );
}

String _number(double? value, String suffix, {bool convertMps = false}) {
  if (value == null) return '—';
  final shown = convertMps ? value * 3.6 : value;
  return '${shown == shown.roundToDouble() ? shown.toStringAsFixed(0) : shown.toStringAsFixed(1)} $suffix';
}

class _WeatherMetric extends StatelessWidget {
  const _WeatherMetric({required this.icon, required this.value});
  final String icon;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SvgPicture.asset(
        'assets/journey/$icon',
        width: icon == 'temperature.svg' ? 19 : 20,
        height: icon == 'temperature.svg' ? 19 : 20,
      ),
      const SizedBox(width: 8),
      Text(
        value,
        style: const TextStyle(
          color: ReefishColors.primaryAction,
          fontSize: 12,
          height: 18 / 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _WeatherSourceLink extends StatelessWidget {
  const _WeatherSourceLink({required this.label, required this.uri});

  final String label;
  final Uri uri;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => launchUrl(uri, mode: LaunchMode.externalApplication),
    child: Text(
      label,
      style: const TextStyle(
        color: ReefishColors.textSecondary,
        decoration: TextDecoration.underline,
        fontSize: 11,
        height: 16 / 11,
      ),
    ),
  );
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

class _RecommendationDetails extends StatelessWidget {
  const _RecommendationDetails({
    required this.recommendation,
    required this.insights,
  });
  final JourneyRecommendation recommendation;
  final JourneyInsights? insights;

  @override
  Widget build(BuildContext context) {
    final weather = recommendation.weatherSummary;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ReefishColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _recommendationType(recommendation.type),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: ReefishColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _coordinates(recommendation.point),
              style: const TextStyle(
                fontSize: 14,
                color: ReefishColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              insights?.isFallback == true
                  ? 'Sumber: estimasi heuristik'
                  : 'Sumber: layanan rekomendasi',
              style: const TextStyle(
                fontSize: 12,
                color: ReefishColors.textSecondary,
              ),
            ),
            if (recommendation.reason != null) ...[
              const SizedBox(height: 10),
              Text(
                recommendation.reason!,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: ReefishColors.textPrimary,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _detailRow(
              'Estimasi BBM',
              _number(recommendation.predictedFuelLiters, 'L'),
            ),
            _detailRow('Potensi tangkapan', _catch(recommendation)),
            _detailRow(
              'Jarak dari home port',
              _number(recommendation.distanceFromPortKm, 'km'),
            ),
            _detailRow(
              'Waktu berangkat',
              recommendation.departureTime ?? 'Belum tersedia',
            ),
            _detailRow(
              'Waktu kembali',
              recommendation.returnTime ?? 'Belum tersedia',
            ),
            _detailRow(
              'Keyakinan model',
              recommendation.confidence == null
                  ? 'Belum tersedia'
                  : '${(recommendation.confidence! * 100).toStringAsFixed(0)}%',
            ),
            if (weather != null) ...[
              const SizedBox(height: 12),
              const Text(
                'Cuaca pada rekomendasi',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: ReefishColors.textPrimary,
                ),
              ),
              _detailRow('Angin', _number(weather.windSpeedMs, 'm/dtk')),
              _detailRow('Gelombang', _number(weather.waveHeightM, 'm')),
              _detailRow('Risiko', weather.risk ?? 'Belum tersedia'),
            ],
            if (insights?.weatherFetchedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Cuaca pelabuhan diperbarui: ${_dateTime(insights!.weatherFetchedAt)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: ReefishColors.textSecondary,
                ),
              ),
            ],
            if (insights?.generatedAt != null ||
                insights?.validUntil != null) ...[
              const SizedBox(height: 10),
              Text(
                'Dibuat: ${_dateTime(insights?.generatedAt)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: ReefishColors.textSecondary,
                ),
              ),
              Text(
                'Berlaku hingga: ${_dateTime(insights?.validUntil)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: ReefishColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Widget _detailRow(String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          color: ReefishColors.textSecondary,
        ),
      ),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: ReefishColors.textPrimary,
          ),
        ),
      ),
    ],
  ),
);

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({this.onHome, this.onProfile, this.onSail});
  final VoidCallback? onHome;
  final VoidCallback? onProfile;
  final VoidCallback? onSail;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = math.min(428.0, constraints.maxWidth);
      return Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: width,
          height: 107,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: SvgPicture.asset(
                  'assets/journey/bottom-nav.svg',
                  fit: BoxFit.fill,
                ),
              ),
              Positioned(
                left: 25 * width / 428,
                right: 25 * width / 428,
                top: 32,
                height: 75,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _NavButton(
                      label: 'Home',
                      icon: 'home.svg',
                      onPressed: onHome,
                      selected: true,
                    ),
                    _NavButton(icon: 'user.svg', onPressed: onProfile),
                  ],
                ),
              ),
              Positioned(
                left: width / 2 - 27.5,
                top: 10,
                child: Material(
                  color: ReefishColors.brand,
                  shape: const CircleBorder(),
                  elevation: 5,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onSail,
                    child: SizedBox(
                      width: 55,
                      height: 55,
                      child: Center(
                        child: SvgPicture.asset(
                          'assets/journey/boat.svg',
                          width: 24,
                          height: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    this.label,
    this.onPressed,
    this.selected = false,
  });
  final String icon;
  final String? label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 70,
    height: 75,
    child: InkWell(
      onTap: onPressed,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset('assets/journey/$icon', width: 24, height: 24),
          if (label != null) ...[
            const SizedBox(height: 5),
            Text(
              label!,
              style: TextStyle(
                color: selected
                    ? ReefishColors.textPrimary
                    : ReefishColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
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

String _dateTime(DateTime? value) {
  if (value == null) return 'Belum tersedia';
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
