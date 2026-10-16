import '../domain/geo_point.dart';
import '../domain/grid_policy.dart';
import '../domain/grid_policy_repository.dart';
import '../domain/metric_grid_500.dart';

/// Explicitly labeled, local preview data. These example locks are not
/// authoritative restrictions and the remaining cells stay unknown.
class DemoGridPolicyRepository implements GridPolicyRepository {
  DemoGridPolicyRepository({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  @override
  Future<GridPolicySnapshot> fetchSnapshot() async {
    final grid = MetricGrid500();
    final anchor = grid.resolve(
      const GeoPoint(latitude: -8.433, longitude: 112.683),
    );
    final locks = <String, GridLock>{};
    for (final cell in [
      anchor,
      grid.cellFromIndexes(anchor.row, anchor.col + 1),
    ]) {
      locks[cell.id] = GridLock(
        cellId: cell.id,
        reason: 'DEMO preview lock; not an official closure',
      );
    }
    final now = _clock().toUtc();
    return GridPolicySnapshot(
      version: 'demo-v1',
      fetchedAt: now,
      expiresAt: now.add(const Duration(hours: 1)),
      locks: locks,
      isDemo: true,
    );
  }
}
