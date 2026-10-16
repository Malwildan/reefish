import 'journey_models.dart';

/// Optional live Go-service data shown alongside the Supabase journey data.
/// A missing response or field stays null; it is never filled with a design
/// placeholder.
class JourneyInsights {
  const JourneyInsights({
    this.weather,
    this.recommendations = const [],
    this.generatedAt,
    this.validUntil,
    this.weatherFetchedAt,
    this.isFallback = false,
    this.recommendationMessage,
    this.weatherMessage,
  });

  final JourneyWeather? weather;
  final List<JourneyRecommendation> recommendations;
  final DateTime? generatedAt;
  final DateTime? validUntil;
  final DateTime? weatherFetchedAt;
  final bool isFallback;
  final String? recommendationMessage;
  final String? weatherMessage;

  /// Recommendations are actionable only while the server-provided freshness
  /// window is known and has not elapsed.
  bool recommendationsUsableAt(DateTime now) =>
      validUntil != null && validUntil!.isAfter(now.toUtc());
}

class JourneyWeather {
  const JourneyWeather({
    this.tempC,
    this.windSpeedMs,
    this.windDirectionDeg,
    this.windDirectionLabel,
    this.waveHeightM,
    this.label,
    this.weatherCode,
    this.risk,
    this.time,
  });

  final double? tempC;
  final double? windSpeedMs;
  final double? windDirectionDeg;
  final String? windDirectionLabel;
  final double? waveHeightM;
  final String? label;
  final int? weatherCode;
  final String? risk;
  final DateTime? time;

  factory JourneyWeather.fromJson(Map<String, dynamic> json) => JourneyWeather(
    tempC: _number(json['temp_c']),
    windSpeedMs: _number(json['wind_speed_ms']),
    windDirectionDeg: _number(json['wind_dir_deg']),
    windDirectionLabel: _string(json['wind_dir_label']),
    waveHeightM: _number(json['wave_height_m']),
    label: _string(json['weather_label']),
    weatherCode: json['weather_code'] is int
        ? json['weather_code'] as int
        : null,
    risk: _string(json['risk']),
    time: _date(json['time']),
  );
}

class JourneyRecommendation {
  const JourneyRecommendation({
    this.id,
    required this.type,
    this.point,
    this.predictedFuelLiters,
    this.predictedCatchKg,
    this.catchRangeKg,
    this.distanceFromPortKm,
    this.departureTime,
    this.returnTime,
    this.confidence,
    this.reason,
    this.weatherSummary,
  });

  final String? id;
  final String type;
  final JourneyLatLng? point;
  final double? predictedFuelLiters;
  final double? predictedCatchKg;
  final List<double>? catchRangeKg;
  final double? distanceFromPortKm;
  final String? departureTime;
  final String? returnTime;
  final double? confidence;
  final String? reason;
  final JourneyWeather? weatherSummary;

  factory JourneyRecommendation.fromJson(Map<String, dynamic> json) {
    final point = _object(json['point']);
    final weather = _object(json['weather_summary']);
    final range = json['predicted_catch_range_kg'];
    return JourneyRecommendation(
      id: _string(json['id']),
      type: _string(json['type']) ?? 'unknown',
      point: point == null ? null : JourneyLatLng.fromJson(point),
      predictedFuelLiters: _number(json['predicted_fuel_liters']),
      predictedCatchKg: _number(json['predicted_catch_kg']),
      catchRangeKg:
          range is List &&
              range.length == 2 &&
              range.every((value) => value is num)
          ? range
                .map((value) => (value as num).toDouble())
                .toList(growable: false)
          : null,
      distanceFromPortKm: _number(json['distance_from_port_km']),
      departureTime: _string(json['departure_time']),
      returnTime: _string(json['return_time']),
      confidence: _number(json['confidence']),
      reason: _string(json['reason']),
      weatherSummary: weather == null ? null : JourneyWeather.fromJson(weather),
    );
  }
}

Map<String, dynamic>? _object(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;
double? _number(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;
String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;
DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
