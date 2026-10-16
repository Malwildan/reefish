import 'dart:math';

import '../../journey/domain/journey_models.dart';

enum SailingPhase { atDeparture, transit, fishing, completed }

enum SailingLocationStatus { permissionRequired, available, lost, paused }

enum SailingReturnLocationKind { lastKnown }

class SailingReturnLocation {
  const SailingReturnLocation({
    required this.point,
    required this.recordedAt,
    this.kind = SailingReturnLocationKind.lastKnown,
  });

  final SailingPoint point;
  final DateTime recordedAt;
  final SailingReturnLocationKind kind;

  Map<String, dynamic> toJson() => {
    'point': point.toJson(),
    'recorded_at': recordedAt.toUtc().toIso8601String(),
    'kind': kind.name,
  };

  factory SailingReturnLocation.fromJson(Map<String, dynamic> json) =>
      SailingReturnLocation(
        point: SailingPoint.fromJson(
          Map<String, dynamic>.from(json['point'] as Map),
        ),
        recordedAt: DateTime.parse(json['recorded_at'] as String).toUtc(),
        kind: SailingReturnLocationKind.values.byName(json['kind'] as String),
      );
}

class SailingPoint extends JourneyLatLng {
  const SailingPoint({required super.lat, required super.lng});

  factory SailingPoint.fromJson(Map<String, dynamic> json) =>
      SailingPoint(lat: _double(json['lat']), lng: _double(json['lng']));
}

class SailingTrackPoint {
  const SailingTrackPoint({
    required this.seq,
    required this.point,
    required this.recordedAt,
    this.speedMs,
    this.accuracyM,
  });

  final int seq;
  final SailingPoint point;
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

  factory SailingTrackPoint.fromJson(Map<String, dynamic> json) =>
      SailingTrackPoint(
        seq: json['seq'] as int,
        point: SailingPoint.fromJson(json),
        recordedAt: DateTime.parse(json['recorded_at'] as String).toUtc(),
        speedMs: _optionalDouble(json['speed_ms']),
        accuracyM: _optionalDouble(json['accuracy_m']),
      );

  JourneyTrackPointInput toInput() => JourneyTrackPointInput(
    seq: seq,
    point: JourneyLatLng(lat: point.lat, lng: point.lng),
    recordedAt: recordedAt,
    speedMs: speedMs,
    accuracyM: accuracyM,
  );
}

/// Durable foreground sailing record. Planned fishing location is kept
/// separately from the user-confirmed actual fishing point.
class SailingSession {
  SailingSession({
    required this.ownerId,
    required this.clientTripId,
    required this.phase,
    required this.departure,
    required this.startedAt,
    this.departedAt,
    required List<SailingTrackPoint> track,
    required this.locationStatus,
    this.plannedFishingPoint,
    this.actualFishingPoint,
    this.fishingStartedAt,
    this.fishingEndedAt,
    this.returnedAt,
    this.returnLocation,
  }) : track = List.unmodifiable(track);

  final String ownerId;
  final String clientTripId;
  final SailingPhase phase;
  final SailingPoint departure;
  final SailingPoint? plannedFishingPoint;
  final SailingPoint? actualFishingPoint;
  final DateTime startedAt;
  final DateTime? departedAt;
  final DateTime? fishingStartedAt;
  final DateTime? fishingEndedAt;
  final DateTime? returnedAt;
  final SailingReturnLocation? returnLocation;
  final List<SailingTrackPoint> track;
  final SailingLocationStatus locationStatus;

  SailingSession copyWith({
    SailingPhase? phase,
    SailingPoint? plannedFishingPoint,
    SailingPoint? actualFishingPoint,
    DateTime? departedAt,
    DateTime? fishingStartedAt,
    DateTime? fishingEndedAt,
    DateTime? returnedAt,
    SailingReturnLocation? returnLocation,
    List<SailingTrackPoint>? track,
    SailingLocationStatus? locationStatus,
  }) => SailingSession(
    ownerId: ownerId,
    clientTripId: clientTripId,
    phase: phase ?? this.phase,
    departure: departure,
    plannedFishingPoint: plannedFishingPoint ?? this.plannedFishingPoint,
    actualFishingPoint: actualFishingPoint ?? this.actualFishingPoint,
    startedAt: startedAt,
    departedAt: departedAt ?? this.departedAt,
    fishingStartedAt: fishingStartedAt ?? this.fishingStartedAt,
    fishingEndedAt: fishingEndedAt ?? this.fishingEndedAt,
    returnedAt: returnedAt ?? this.returnedAt,
    returnLocation: returnLocation ?? this.returnLocation,
    track: track ?? this.track,
    locationStatus: locationStatus ?? this.locationStatus,
  );

  Map<String, dynamic> toJson() => {
    'owner_id': ownerId,
    'client_trip_id': clientTripId,
    'phase': phase.name,
    'departure': departure.toJson(),
    'planned_fishing_point': plannedFishingPoint?.toJson(),
    'actual_fishing_point': actualFishingPoint?.toJson(),
    'started_at': startedAt.toUtc().toIso8601String(),
    'departed_at': departedAt?.toUtc().toIso8601String(),
    'fishing_started_at': fishingStartedAt?.toUtc().toIso8601String(),
    'fishing_ended_at': fishingEndedAt?.toUtc().toIso8601String(),
    'returned_at': returnedAt?.toUtc().toIso8601String(),
    'return_location': returnLocation?.toJson(),
    'location_status': locationStatus.name,
    'track': track.map((point) => point.toJson()).toList(growable: false),
  };

  factory SailingSession.fromJson(Map<String, dynamic> json) {
    final track = json['track'];
    if (track is! List) throw const FormatException('track must be a list');
    final session = SailingSession(
      ownerId: json['owner_id'] as String,
      clientTripId: json['client_trip_id'] as String,
      phase: SailingPhase.values.byName(json['phase'] as String),
      departure: SailingPoint.fromJson(
        Map<String, dynamic>.from(json['departure'] as Map),
      ),
      plannedFishingPoint: _point(json['planned_fishing_point']),
      actualFishingPoint: _point(json['actual_fishing_point']),
      startedAt: DateTime.parse(json['started_at'] as String).toUtc(),
      departedAt: _date(json['departed_at']),
      fishingStartedAt: _date(json['fishing_started_at']),
      fishingEndedAt: _date(json['fishing_ended_at']),
      returnedAt: _date(json['returned_at']),
      returnLocation: json['return_location'] is Map
          ? SailingReturnLocation.fromJson(
              Map<String, dynamic>.from(json['return_location'] as Map),
            )
          : null,
      locationStatus: SailingLocationStatus.values.byName(
        json['location_status'] as String,
      ),
      track: track
          .map(
            (item) => SailingTrackPoint.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
    );
    session.validate();
    return session;
  }

  void validate() {
    if (ownerId.trim().isEmpty || !_isUuid(clientTripId)) {
      throw const FormatException('Invalid sailing owner or trip id');
    }
    departure.validate('departure');
    plannedFishingPoint?.validate('plannedFishingPoint');
    actualFishingPoint?.validate('actualFishingPoint');
    returnLocation?.point.validate('returnLocation');
    if (track.length > maxTrackPoints) {
      throw const FormatException('Sailing track exceeds the API limit');
    }
    DateTime? last;
    for (var i = 0; i < track.length; i++) {
      final point = track[i];
      point.point.validate('track[$i]');
      if (point.seq != i || (last != null && !point.recordedAt.isAfter(last))) {
        throw const FormatException('Track points must be ordered and unique');
      }
      if (point.accuracyM != null &&
          (!point.accuracyM!.isFinite || point.accuracyM! <= 0)) {
        throw const FormatException('Invalid track accuracy');
      }
      if (point.speedMs != null &&
          (!point.speedMs!.isFinite || point.speedMs! < 0)) {
        throw const FormatException('Invalid track speed');
      }
      last = point.recordedAt;
    }
    if (phase == SailingPhase.fishing &&
        (actualFishingPoint == null ||
            fishingStartedAt == null ||
            fishingEndedAt != null)) {
      throw const FormatException('Fishing phase needs a confirmed point');
    }
    if (phase == SailingPhase.completed &&
        actualFishingPoint != null &&
        (fishingStartedAt == null || fishingEndedAt == null)) {
      throw const FormatException(
        'Completed fishing session needs start and end times',
      );
    }
    if (actualFishingPoint == null &&
        (fishingStartedAt != null || fishingEndedAt != null)) {
      throw const FormatException('Fishing times need an actual fishing point');
    }
    if (phase == SailingPhase.completed && returnedAt == null) {
      throw const FormatException(
        'Completed sailing record needs a return time',
      );
    }
    if (returnLocation != null &&
        (phase != SailingPhase.completed ||
            track.isEmpty ||
            returnLocation!.recordedAt != track.last.recordedAt ||
            returnLocation!.point.lat != track.last.point.lat ||
            returnLocation!.point.lng != track.last.point.lng)) {
      throw const FormatException(
        'Return location must identify the last recorded GPS fix.',
      );
    }
    if (phase == SailingPhase.completed &&
        actualFishingPoint != null &&
        fishingEndedAt == null) {
      throw const FormatException(
        'Completed fishing session needs an end time',
      );
    }
  }

  JourneyTripInput toTripInput({
    required double fuelLiters,
    required double catchKg,
  }) {
    if (phase != SailingPhase.completed ||
        actualFishingPoint == null ||
        fishingStartedAt == null ||
        fishingEndedAt == null ||
        returnedAt == null ||
        departedAt == null ||
        track.length < 2) {
      throw StateError(
        'Sesi belum memiliki titik aktual, waktu keberangkatan, dan dua titik GPS yang diperlukan.',
      );
    }
    return JourneyTripInput(
      clientTripId: clientTripId,
      source: JourneyTripSource.sailing,
      departure: JourneyLatLng(lat: departure.lat, lng: departure.lng),
      departedAt: departedAt!,
      returnedAt: returnedAt!,
      fuelLiters: fuelLiters,
      catchKg: catchKg,
      fishingPoints: [
        JourneyFishingPointInput(
          point: JourneyLatLng(
            lat: actualFishingPoint!.lat,
            lng: actualFishingPoint!.lng,
          ),
          startedAt: fishingStartedAt,
          endedAt: fishingEndedAt,
          flagSource: 'user_confirmed',
        ),
      ],
      track: track.map((point) => point.toInput()).toList(growable: false),
    );
  }
}

const maxTrackPoints = 5000;

String newSailingClientTripId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

bool _isUuid(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
).hasMatch(value);
double _double(Object? value) => value is num ? value.toDouble() : double.nan;
double? _optionalDouble(Object? value) =>
    value is num ? value.toDouble() : null;
DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;
SailingPoint? _point(Object? value) => value is Map
    ? SailingPoint.fromJson(Map<String, dynamic>.from(value))
    : null;
