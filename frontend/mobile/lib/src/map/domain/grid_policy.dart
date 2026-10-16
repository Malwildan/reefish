enum GridAccess { locked, unlocked, unknown }

enum GridSelectionPurpose { fishing, departure }

class GridLock {
  const GridLock({required this.cellId, required this.reason});

  final String cellId;
  final String reason;
}

/// A server policy snapshot is time-bounded. Known locks remain meaningful
/// after expiry; an expired snapshot cannot assert that an unlisted cell is
/// unlocked.
class GridPolicySnapshot {
  GridPolicySnapshot({
    required this.version,
    required this.fetchedAt,
    required this.expiresAt,
    required Map<String, GridLock> locks,
    this.isDemo = false,
  }) : locks = Map.unmodifiable(locks) {
    if (version.trim().isEmpty || !fetchedAt.isBefore(expiresAt)) {
      throw ArgumentError('Invalid grid policy snapshot metadata');
    }
    for (final entry in this.locks.entries) {
      if (entry.key != entry.value.cellId || entry.key.trim().isEmpty) {
        throw ArgumentError('Grid lock key must match its cell ID');
      }
    }
  }

  final String version;
  final DateTime fetchedAt;
  final DateTime expiresAt;
  final Map<String, GridLock> locks;
  final bool isDemo;

  bool isFreshAt(DateTime at) =>
      !at.isBefore(fetchedAt) && at.isBefore(expiresAt);

  GridAccess accessFor(String cellId, DateTime at) {
    if (locks.containsKey(cellId)) return GridAccess.locked;
    if (!isFreshAt(at) || isDemo) return GridAccess.unknown;
    return GridAccess.unlocked;
  }

  /// Policy locks govern fishing access only. Departure locations describe a
  /// planned trip and remain selectable even when fishing is locked/unknown.
  bool canSelectFor(String cellId, GridSelectionPurpose purpose, DateTime at) {
    if (purpose == GridSelectionPurpose.departure) return true;
    return accessFor(cellId, at) == GridAccess.unlocked;
  }
}
