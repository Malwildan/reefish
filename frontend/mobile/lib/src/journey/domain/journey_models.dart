import 'dart:math';

enum JourneyStep { boat, firstTrip, done, unknown }

enum JourneyTripSource { onboarding, manual, sailing }

extension JourneyTripSourceValue on JourneyTripSource {
  String get wireValue => switch (this) {
    JourneyTripSource.onboarding => 'onboarding',
    JourneyTripSource.manual => 'manual',
    JourneyTripSource.sailing => 'sailing',
  };
}

String createClientTripId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class JourneyLatLng {
  const JourneyLatLng({required this.lat, required this.lng});

  final double lat;
  final double lng;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  factory JourneyLatLng.fromJson(Map<String, dynamic> json) => JourneyLatLng(
    lat: _number(json['lat']) ?? double.nan,
    lng: _number(json['lng']) ?? double.nan,
  );

  void validate(String field) {
    if (!lat.isFinite ||
        lat < -90 ||
        lat > 90 ||
        !lng.isFinite ||
        lng < -180 ||
        lng > 180) {
      throw ArgumentError('$field must be a valid WGS84 point');
    }
  }
}

class JourneyBoatInput {
  const JourneyBoatInput({
    this.name,
    required this.engineHp,
    required this.boatLengthM,
    this.fuelType = 'solar',
    required this.homePort,
  });

  final String? name;
  final double engineHp;
  final double boatLengthM;
  final String fuelType;
  final JourneyLatLng homePort;

  Map<String, dynamic> toJson() {
    validate();
    return {
      'name': name,
      'engine_hp': engineHp,
      'boat_length_m': boatLengthM,
      'fuel_type': fuelType,
      'home_port': homePort.toJson(),
    };
  }

  void validate() {
    if (name != null && name!.length > 60) {
      throw ArgumentError.value(name, 'name', 'must be at most 60 characters');
    }
    if (!engineHp.isFinite || engineHp < 1 || engineHp > 500) {
      throw ArgumentError.value(
        engineHp,
        'engineHp',
        'must be between 1 and 500',
      );
    }
    if (!boatLengthM.isFinite || boatLengthM < 2 || boatLengthM > 30) {
      throw ArgumentError.value(
        boatLengthM,
        'boatLengthM',
        'must be between 2 and 30',
      );
    }
    if (fuelType != 'solar' && fuelType != 'bensin') {
      throw ArgumentError.value(fuelType, 'fuelType');
    }
    homePort.validate('homePort');
  }
}

class JourneyBoat {
  const JourneyBoat({
    required this.id,
    this.name,
    required this.engineHp,
    required this.boatLengthM,
    required this.fuelType,
    required this.homePort,
    required this.isDefault,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? name;
  final double? engineHp;
  final double? boatLengthM;
  final String? fuelType;
  final JourneyLatLng? homePort;
  final bool? isDefault;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory JourneyBoat.fromJson(Map<String, dynamic> json) => JourneyBoat(
    id: json['id'] as String? ?? '',
    name: json['name'] as String?,
    engineHp: _number(json['engine_hp']),
    boatLengthM: _number(json['boat_length_m']),
    fuelType: json['fuel_type'] as String?,
    homePort: _map(json['home_port']) == null
        ? null
        : JourneyLatLng.fromJson(_map(json['home_port'])!),
    isDefault: json['is_default'] as bool?,
    createdAt: _date(json['created_at']),
    updatedAt: _date(json['updated_at']),
  );
}

class JourneyStats {
  const JourneyStats({
    this.tripCount,
    this.baselineFuelLiters,
    this.baselineCatchKg,
    this.lastTripAt,
  });

  final int? tripCount;
  final double? baselineFuelLiters;
  final double? baselineCatchKg;
  final DateTime? lastTripAt;

  factory JourneyStats.fromJson(Map<String, dynamic> json) => JourneyStats(
    tripCount: _integer(json['trip_count']),
    baselineFuelLiters: _number(json['baseline_fuel_liters']),
    baselineCatchKg: _number(json['baseline_catch_kg']),
    lastTripAt: _date(json['last_trip_at']),
  );
}

class JourneyProfile {
  const JourneyProfile({
    required this.id,
    this.name,
    this.phone,
    this.role,
    this.onboarded,
    required this.nextStep,
    this.boat,
    this.stats,
  });

  final String id;
  final String? name;
  final String? phone;
  final String? role;
  final bool? onboarded;
  final JourneyStep nextStep;
  final JourneyBoat? boat;
  final JourneyStats? stats;

  factory JourneyProfile.fromJson(Map<String, dynamic> json) {
    final step = switch (json['next_step']) {
      'boat' => JourneyStep.boat,
      'first_trip' => JourneyStep.firstTrip,
      'done' => JourneyStep.done,
      _ => JourneyStep.unknown,
    };
    final boat = _map(json['boat']);
    final stats = _map(json['stats']);
    return JourneyProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String?,
      phone: json['phone'] as String?,
      role: json['role'] as String?,
      onboarded: json['onboarded'] as bool?,
      nextStep: step,
      boat: boat == null ? null : JourneyBoat.fromJson(boat),
      stats: stats == null ? null : JourneyStats.fromJson(stats),
    );
  }
}

class JourneyFishingPointInput {
  const JourneyFishingPointInput({
    required this.point,
    this.startedAt,
    this.endedAt,
    this.flagSource = 'manual',
    this.recommendationId,
    this.reportedCatchKg,
  });

  final JourneyLatLng point;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String flagSource;
  final String? recommendationId;
  final double? reportedCatchKg;

  Map<String, dynamic> toJson() => {
    ...point.toJson(),
    'started_at': startedAt?.toUtc().toIso8601String(),
    'ended_at': endedAt?.toUtc().toIso8601String(),
    'flag_source': flagSource,
    'recommendation_id': recommendationId,
    'reported_catch_kg': reportedCatchKg,
  };
}

class JourneyTrackPointInput {
  const JourneyTrackPointInput({
    required this.seq,
    required this.point,
    required this.recordedAt,
    this.speedMs,
    this.accuracyM,
  });

  final int seq;
  final JourneyLatLng point;
  final DateTime recordedAt;
  final double? speedMs;
  final double? accuracyM;

  Map<String, dynamic> toJson() => {
    'seq': seq,
    ...point.toJson(),
    'recorded_at': recordedAt.toUtc().toIso8601String(),
    'speed_ms': speedMs,
    'accuracy_m': accuracyM,
  };
}

class JourneyTripInput {
  JourneyTripInput({
    String? clientTripId,
    required this.source,
    this.departure,
    this.returnPoint,
    required this.departedAt,
    required this.returnedAt,
    required this.fuelLiters,
    required this.catchKg,
    required this.fishingPoints,
    this.track,
    this.selectedRecommendationId,
    this.notes,
  }) : clientTripId = clientTripId ?? createClientTripId();

  final String clientTripId;
  final JourneyTripSource source;
  final JourneyLatLng? departure;
  final JourneyLatLng? returnPoint;
  final DateTime departedAt;
  final DateTime returnedAt;
  final double fuelLiters;
  final double catchKg;
  final List<JourneyFishingPointInput> fishingPoints;
  final List<JourneyTrackPointInput>? track;
  final String? selectedRecommendationId;
  final String? notes;

  factory JourneyTripInput.fromJson(Map<String, dynamic> json) {
    final clientTripId = json['client_trip_id'];
    if (clientTripId is! String || !_isUuid(clientTripId)) {
      throw const FormatException('client_trip_id must be a non-empty UUID');
    }
    final source = switch (json['source']) {
      'onboarding' => JourneyTripSource.onboarding,
      'manual' => JourneyTripSource.manual,
      'sailing' => JourneyTripSource.sailing,
      _ => throw const FormatException('Unknown journey source'),
    };
    final points = json['fishing_points'];
    final track = json['track'];
    if (points is! List) {
      throw const FormatException('fishing_points is required');
    }
    if (json.containsKey('track') && track != null && track is! List) {
      throw const FormatException('track must be an array or null');
    }
    final trip = JourneyTripInput(
      clientTripId: clientTripId,
      source: source,
      departure: _optionalLatLng(json['departure']),
      returnPoint: _optionalLatLng(json['return_point']),
      departedAt: _requiredDate(json['departed_at']),
      returnedAt: _requiredDate(json['returned_at']),
      fuelLiters: _requiredNumber(json['fuel_liters']),
      catchKg: _requiredNumber(json['catch_kg']),
      fishingPoints: points
          .map((item) {
            final map = _map(item);
            if (map == null) {
              throw const FormatException('Invalid fishing point');
            }
            return JourneyFishingPointInput(
              point: JourneyLatLng.fromJson(map),
              startedAt: _optionalDate(map['started_at']),
              endedAt: _optionalDate(map['ended_at']),
              flagSource: map['flag_source'] as String? ?? 'manual',
              recommendationId: map['recommendation_id'] as String?,
              reportedCatchKg: _optionalNumber(map['reported_catch_kg']),
            );
          })
          .toList(growable: false),
      track: track is List
          ? track
                .map((item) {
                  final map = _map(item);
                  if (map == null) {
                    throw const FormatException('Invalid track point');
                  }
                  return JourneyTrackPointInput(
                    seq: _integer(map['seq']) ?? -1,
                    point: JourneyLatLng.fromJson(map),
                    recordedAt: _requiredDate(map['recorded_at']),
                    speedMs: _optionalNumber(map['speed_ms']),
                    accuracyM: _optionalNumber(map['accuracy_m']),
                  );
                })
                .toList(growable: false)
          : null,
      selectedRecommendationId: json['selected_recommendation_id'] as String?,
      notes: json['notes'] as String?,
    );
    trip.validate();
    return trip;
  }

  Map<String, dynamic> toJson({DateTime? now}) {
    validate(now: now);
    return {
      'client_trip_id': clientTripId,
      'source': source.wireValue,
      if (departure != null) 'departure': departure!.toJson(),
      if (returnPoint != null) 'return_point': returnPoint!.toJson(),
      'departed_at': departedAt.toUtc().toIso8601String(),
      'returned_at': returnedAt.toUtc().toIso8601String(),
      'fuel_liters': fuelLiters,
      'catch_kg': catchKg,
      'fishing_points': fishingPoints.map((point) => point.toJson()).toList(),
      if (track != null)
        'track': track!.map((point) => point.toJson()).toList(),
      if (selectedRecommendationId != null)
        'selected_recommendation_id': selectedRecommendationId,
      if (notes != null) 'notes': notes,
    };
  }

  void validate({DateTime? now}) {
    if (!_isUuid(clientTripId)) {
      throw ArgumentError.value(clientTripId, 'clientTripId', 'must be a UUID');
    }
    if (!fuelLiters.isFinite || fuelLiters <= 0 || fuelLiters > 500) {
      throw ArgumentError.value(
        fuelLiters,
        'fuelLiters',
        'must be > 0 and <= 500',
      );
    }
    if (!catchKg.isFinite || catchKg < 0 || catchKg > 5000) {
      throw ArgumentError.value(
        catchKg,
        'catchKg',
        'must be between 0 and 5000',
      );
    }
    final duration = returnedAt.difference(departedAt);
    if (duration <= Duration.zero || duration > const Duration(hours: 72)) {
      throw ArgumentError(
        'returnedAt must be after departedAt and within 72 hours',
      );
    }
    final current = (now ?? DateTime.now()).toUtc();
    if (returnedAt.toUtc().isAfter(current.add(const Duration(minutes: 10)))) {
      throw ArgumentError(
        'returnedAt cannot be more than 10 minutes in the future',
      );
    }
    if (fishingPoints.isEmpty || fishingPoints.length > 50) {
      throw ArgumentError('fishingPoints must contain between 1 and 50 points');
    }
    departure?.validate('departure');
    returnPoint?.validate('returnPoint');
    for (final point in fishingPoints) {
      point.point.validate('fishingPoint');
      if (point.reportedCatchKg != null &&
          (!point.reportedCatchKg!.isFinite ||
              point.reportedCatchKg! < 0 ||
              point.reportedCatchKg! > 5000)) {
        throw ArgumentError.value(point.reportedCatchKg, 'reportedCatchKg');
      }
    }
    if (source == JourneyTripSource.sailing &&
        (track == null || track!.length < 2)) {
      throw ArgumentError('sailing requires at least 2 track points');
    }
    if (track != null && track!.length > 5000) {
      throw ArgumentError('track must contain at most 5000 points');
    }
    var previousSeq = -1;
    for (final point in track ?? const <JourneyTrackPointInput>[]) {
      point.point.validate('trackPoint');
      if (point.seq <= previousSeq) {
        throw ArgumentError('track seq must increase');
      }
      previousSeq = point.seq;
      final time = point.recordedAt.toUtc();
      if (time.isBefore(
            departedAt.toUtc().subtract(const Duration(minutes: 10)),
          ) ||
          time.isAfter(returnedAt.toUtc().add(const Duration(minutes: 10)))) {
        throw ArgumentError('track point time must be within the trip window');
      }
    }
    if (notes != null && notes!.length > 500) {
      throw ArgumentError.value(
        notes,
        'notes',
        'must be at most 500 characters',
      );
    }
  }
}

class JourneyTripSummary {
  const JourneyTripSummary({
    required this.id,
    this.source,
    this.departedAt,
    this.returnedAt,
    this.durationHours,
    this.fuelLiters,
    this.catchKg,
    this.distanceFromPortKm,
    this.totalDistanceKm,
    this.fuelEfficiencyPct,
    this.catchPerLiter,
    this.fishingPointCount,
    this.mainGridId,
    this.followedRecommendationType,
    this.zoneViolation,
    this.boatName,
  });

  final String id;
  final String? source;
  final DateTime? departedAt;
  final DateTime? returnedAt;
  final double? durationHours;
  final double? fuelLiters;
  final double? catchKg;
  final double? distanceFromPortKm;
  final double? totalDistanceKm;
  final double? fuelEfficiencyPct;
  final double? catchPerLiter;
  final int? fishingPointCount;
  final String? mainGridId;
  final String? followedRecommendationType;
  final bool? zoneViolation;
  final String? boatName;

  factory JourneyTripSummary.fromJson(Map<String, dynamic> json) {
    final boat = _map(json['boat']);
    final id = json['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('Trip id must not be empty');
    }
    return JourneyTripSummary(
      id: id,
      source: json['source'] as String?,
      departedAt: _date(json['departed_at']),
      returnedAt: _date(json['returned_at']),
      durationHours: _number(json['duration_h']),
      fuelLiters: _number(json['fuel_liters']),
      catchKg: _number(json['catch_kg']),
      distanceFromPortKm: _number(json['distance_from_port_km']),
      totalDistanceKm: _number(json['total_distance_km']),
      fuelEfficiencyPct: _number(json['fuel_efficiency_pct']),
      catchPerLiter: _number(json['catch_per_liter']),
      fishingPointCount: _integer(json['fishing_point_count']),
      mainGridId: json['main_grid_id'] as String?,
      followedRecommendationType:
          json['followed_recommendation_type'] as String?,
      zoneViolation: json['zone_violation'] as bool?,
      boatName: boat?['name'] as String?,
    );
  }
}

class JourneyFishingPointDetail {
  const JourneyFishingPointDetail({
    required this.point,
    this.id,
    this.gridId,
    this.startedAt,
    this.endedAt,
  });

  final JourneyLatLng point;
  final String? id;
  final String? gridId;
  final DateTime? startedAt;
  final DateTime? endedAt;
}

class JourneyTripDetail extends JourneyTripSummary {
  const JourneyTripDetail({
    required super.id,
    super.source,
    super.departedAt,
    super.returnedAt,
    super.durationHours,
    super.fuelLiters,
    super.catchKg,
    super.distanceFromPortKm,
    super.totalDistanceKm,
    super.fuelEfficiencyPct,
    super.catchPerLiter,
    super.fishingPointCount,
    super.mainGridId,
    super.followedRecommendationType,
    super.zoneViolation,
    super.boatName,
    this.departure,
    this.returnPoint,
    this.fishingHours,
    this.fuelPerKm,
    this.notes,
    this.track = const [],
    this.fishingPoints = const [],
  });

  final JourneyLatLng? departure;
  final JourneyLatLng? returnPoint;
  final double? fishingHours;
  final double? fuelPerKm;
  final String? notes;
  final List<JourneyLatLng> track;
  final List<JourneyFishingPointDetail> fishingPoints;

  factory JourneyTripDetail.fromJson(Map<String, dynamic> json) {
    final summary = JourneyTripSummary.fromJson(json);
    return JourneyTripDetail(
      id: summary.id,
      source: summary.source,
      departedAt: summary.departedAt,
      returnedAt: summary.returnedAt,
      durationHours: summary.durationHours,
      fuelLiters: summary.fuelLiters,
      catchKg: summary.catchKg,
      distanceFromPortKm: summary.distanceFromPortKm,
      totalDistanceKm: summary.totalDistanceKm,
      fuelEfficiencyPct: summary.fuelEfficiencyPct,
      catchPerLiter: summary.catchPerLiter,
      fishingPointCount: summary.fishingPointCount,
      mainGridId: summary.mainGridId,
      followedRecommendationType: summary.followedRecommendationType,
      zoneViolation: summary.zoneViolation,
      boatName: summary.boatName,
      departure: _map(json['departure']) == null
          ? null
          : JourneyLatLng.fromJson(_map(json['departure'])!),
      returnPoint: _map(json['return_point']) == null
          ? null
          : JourneyLatLng.fromJson(_map(json['return_point'])!),
      fishingHours: _number(json['fishing_hours']),
      fuelPerKm: _number(json['fuel_per_km']),
      notes: json['notes'] as String?,
      track: _tripDetailTrack(json['track']),
      fishingPoints: _tripDetailFishingPoints(json['fishing_points']),
    );
  }
}

List<JourneyLatLng> _tripDetailTrack(Object? value) {
  final geometry = _map(value);
  if (geometry == null ||
      geometry['type'] != 'LineString' ||
      geometry['coordinates'] is! List) {
    return const [];
  }
  final coordinates = geometry['coordinates'] as List;
  if (coordinates.length < 2 || coordinates.length > 5000) return const [];
  final points = <JourneyLatLng>[];
  for (final coordinate in coordinates) {
    if (coordinate is! List || coordinate.length != 2) return const [];
    final lng = _detailCoordinate(coordinate[0], -180, 180);
    final lat = _detailCoordinate(coordinate[1], -90, 90);
    if (lat == null || lng == null) return const [];
    points.add(JourneyLatLng(lat: lat, lng: lng));
  }
  return List.unmodifiable(points);
}

List<JourneyFishingPointDetail> _tripDetailFishingPoints(Object? value) {
  if (value is! List) return const [];
  final points = <JourneyFishingPointDetail>[];
  for (final item in value) {
    final row = _map(item);
    if (row == null) continue;
    final lat = _detailCoordinate(row['lat'], -90, 90);
    final lng = _detailCoordinate(row['lng'], -180, 180);
    if (lat == null || lng == null) continue;
    points.add(
      JourneyFishingPointDetail(
        point: JourneyLatLng(lat: lat, lng: lng),
        id: row['id'] is String ? row['id'] as String : null,
        gridId: row['grid_id'] is String ? row['grid_id'] as String : null,
        startedAt: _date(row['started_at']),
        endedAt: _date(row['ended_at']),
      ),
    );
  }
  return List.unmodifiable(points);
}

double? _detailCoordinate(Object? value, double minimum, double maximum) {
  if (value is! num) return null;
  final coordinate = value.toDouble();
  if (!coordinate.isFinite || coordinate < minimum || coordinate > maximum) {
    return null;
  }
  return coordinate;
}

class JourneyTripHistory {
  const JourneyTripHistory({
    required this.trips,
    this.page,
    this.limit,
    this.total,
    this.tripCount,
    this.totalCatchKg,
    this.totalFuelLiters,
    this.averageCatchPerLiter,
  });

  final List<JourneyTripSummary> trips;
  final int? page;
  final int? limit;
  final int? total;
  final int? tripCount;
  final double? totalCatchKg;
  final double? totalFuelLiters;
  final double? averageCatchPerLiter;

  factory JourneyTripHistory.fromJson(Map<String, dynamic> json) {
    final meta = _map(json['meta']) ?? const <String, dynamic>{};
    final summary = _map(json['summary']) ?? const <String, dynamic>{};
    final rows = json['data'];
    return JourneyTripHistory(
      trips: rows is List
          ? rows
                .whereType<Map>()
                .map(
                  (row) => JourneyTripSummary.fromJson(
                    Map<String, dynamic>.from(row),
                  ),
                )
                .toList(growable: false)
          : const [],
      page: _integer(meta['page']),
      limit: _integer(meta['limit']),
      total: _integer(meta['total']),
      tripCount: _integer(summary['trip_count']),
      totalCatchKg: _number(summary['total_catch_kg']),
      totalFuelLiters: _number(summary['total_fuel_liters']),
      averageCatchPerLiter: _number(summary['avg_catch_per_liter']),
    );
  }
}

class JourneyDashboard {
  const JourneyDashboard({required this.profile, required this.history});

  final JourneyProfile profile;
  final JourneyTripHistory history;
}

class JourneyTripSubmission {
  const JourneyTripSubmission({
    required this.trip,
    required this.onboarded,
    required this.replay,
    this.recommendations,
  });

  final JourneyTripDetail trip;
  final bool? onboarded;
  final bool replay;
  final Map<String, dynamic>? recommendations;

  factory JourneyTripSubmission.fromJson(Map<String, dynamic> json) {
    final user = _map(json['user']);
    final recs = _map(json['recommendations']);
    final trip = _map(json['trip']) ?? const <String, dynamic>{};
    return JourneyTripSubmission(
      trip: JourneyTripDetail.fromJson(trip),
      onboarded: user?['onboarded'] as bool?,
      replay: json['replay'] as bool? ?? false,
      recommendations: recs,
    );
  }
}

class JourneyDraft {
  const JourneyDraft({required this.ownerId, required this.trip});

  final String ownerId;
  final JourneyTripInput trip;
}

Map<String, dynamic>? _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;
double? _number(Object? value) => value is num ? value.toDouble() : null;
int? _integer(Object? value) => value is int ? value : null;
DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;
JourneyLatLng? _optionalLatLng(Object? value) {
  final map = _map(value);
  return map == null ? null : JourneyLatLng.fromJson(map);
}

DateTime? _optionalDate(Object? value) =>
    value == null ? null : _requiredDate(value);
double? _optionalNumber(Object? value) =>
    value == null ? null : _requiredNumber(value);
DateTime _requiredDate(Object? value) =>
    _date(value) ?? (throw const FormatException('Expected an ISO-8601 date'));
double _requiredNumber(Object? value) =>
    _number(value) ?? (throw const FormatException('Expected a number'));

bool _isUuid(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
).hasMatch(value);
