import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/reef_fish_theme.dart';
import '../domain/journey_insights.dart';

/// Compact forecast metrics shared by the dashboard and the full map.
/// Missing service values remain visibly unknown as an em dash.
class JourneyWeatherStrip extends StatelessWidget {
  const JourneyWeatherStrip({super.key, required this.weather});

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
        _JourneyWeatherMetric(
          icon: 'temperature.svg',
          value: _weatherNumber(weather?.tempC, '°C'),
        ),
        _JourneyWeatherMetric(
          icon: 'wind.svg',
          value: _weatherNumber(
            weather?.windSpeedMs,
            'km/jam',
            convertMps: true,
          ),
        ),
        _JourneyWeatherMetric(
          icon: 'wave.svg',
          value: _weatherNumber(weather?.waveHeightM, 'm'),
        ),
      ],
    ),
  );
}

/// Shows the actual upstream source and timestamps returned with the forecast.
class JourneyWeatherAttribution extends StatelessWidget {
  const JourneyWeatherAttribution({
    super.key,
    required this.insights,
    this.compact = false,
  });

  final JourneyInsights? insights;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (insights?.weather == null) {
      return Text(
        insights?.weatherMessage ?? 'Data cuaca belum tersedia.',
        style: const TextStyle(
          color: ReefishColors.textSecondary,
          fontSize: 11,
          height: 16 / 11,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 2,
          children: [
            const Text(
              'Sumber cuaca: ',
              style: TextStyle(
                color: ReefishColors.textSecondary,
                fontSize: 11,
                height: 16 / 11,
              ),
            ),
            _JourneyWeatherSourceLink(
              label: 'Open-Meteo',
              uri: Uri.parse('https://open-meteo.com/en/docs'),
            ),
            const Text(
              '·',
              style: TextStyle(
                color: ReefishColors.textSecondary,
                fontSize: 11,
              ),
            ),
            _JourneyWeatherSourceLink(
              label: 'DWD',
              uri: Uri.parse('https://www.dwd.de/'),
            ),
          ],
        ),
        if (!compact) ...[
          const SizedBox(height: 1),
          Text(
            'Data dimuat: ${_weatherDateTime(insights?.weatherFetchedAt)} · Prakiraan: ${_weatherDateTime(insights?.weather?.time)}',
            style: const TextStyle(
              color: ReefishColors.textSecondary,
              fontSize: 11,
              height: 16 / 11,
            ),
          ),
        ],
      ],
    );
  }
}

class _JourneyWeatherMetric extends StatelessWidget {
  const _JourneyWeatherMetric({required this.icon, required this.value});

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

class _JourneyWeatherSourceLink extends StatelessWidget {
  const _JourneyWeatherSourceLink({required this.label, required this.uri});

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

String _weatherNumber(double? value, String suffix, {bool convertMps = false}) {
  if (value == null) return '—';
  final shown = convertMps ? value * 3.6 : value;
  return '${shown == shown.roundToDouble() ? shown.toStringAsFixed(0) : shown.toStringAsFixed(1)} $suffix';
}

String _weatherDateTime(DateTime? value) {
  if (value == null) return 'Belum tersedia';
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
