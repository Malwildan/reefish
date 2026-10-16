import '../domain/grid_policy.dart';

class GridPolicyFormatException implements Exception {
  const GridPolicyFormatException(this.message);
  final String message;

  @override
  String toString() => 'GridPolicyFormatException: $message';
}

GridPolicySnapshot parseGridPolicySnapshot(
  Object? value, {
  DateTime? receivedAt,
  Duration requestDuration = Duration.zero,
}) {
  if (value is! Map) {
    throw const GridPolicyFormatException('snapshot must be an object');
  }
  final json = Map<Object?, Object?>.from(value);
  final version = json['version'];
  final fetchedAt = _date(json['fetched_at'], 'fetched_at');
  final expiresAt = _date(json['expires_at'], 'expires_at');
  final rawLocks = json['locks'];
  final isDemo = json['is_demo'];
  if (version is! String || version.trim().isEmpty) {
    throw const GridPolicyFormatException('version must be a non-empty string');
  }
  if (rawLocks is! List) {
    throw const GridPolicyFormatException('locks must be an array');
  }
  if (isDemo is! bool) {
    throw const GridPolicyFormatException('is_demo must be a boolean');
  }

  final locks = <String, GridLock>{};
  for (final rawLock in rawLocks) {
    if (rawLock is! Map) {
      throw const GridPolicyFormatException('each lock must be an object');
    }
    final lock = Map<Object?, Object?>.from(rawLock);
    final cellId = lock['cell_id'];
    final reason = lock['reason'];
    if (cellId is! String || cellId.trim().isEmpty || reason is! String) {
      throw const GridPolicyFormatException(
        'each lock requires a cell_id and string reason',
      );
    }
    if (locks.containsKey(cellId)) {
      throw GridPolicyFormatException('duplicate lock for $cellId');
    }
    locks[cellId] = GridLock(cellId: cellId, reason: reason);
  }

  try {
    final received = receivedAt?.toUtc();
    final remainingTtl = expiresAt.difference(fetchedAt) - requestDuration;
    return GridPolicySnapshot(
      version: version,
      fetchedAt: fetchedAt,
      expiresAt: expiresAt,
      locks: locks,
      isDemo: isDemo,
      validFrom: received,
      validUntil: received?.add(
        remainingTtl.isNegative ? Duration.zero : remainingTtl,
      ),
    );
  } on ArgumentError catch (error) {
    throw GridPolicyFormatException(error.message.toString());
  }
}

DateTime _date(Object? value, String field) {
  if (value is! String) {
    throw GridPolicyFormatException('$field must be an ISO-8601 string');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw GridPolicyFormatException('$field is not a valid timestamp');
  }
  return parsed.toUtc();
}
