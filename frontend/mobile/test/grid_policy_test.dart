import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/map/data/grid_policy_snapshot_parser.dart';
import 'package:reefish_mobile/src/map/domain/grid_policy.dart';

void main() {
  final fetchedAt = DateTime.utc(2026, 10, 16, 1);
  final expiresAt = fetchedAt.add(const Duration(minutes: 10));
  const lockedCell = 'tp-id-utm49s-500m:v2:rp1:cp2';
  const openCell = 'tp-id-utm49s-500m:v2:rp1:cp3';

  GridPolicySnapshot snapshot({bool isDemo = false}) => GridPolicySnapshot(
    version: 'snapshot-v1',
    fetchedAt: fetchedAt,
    expiresAt: expiresAt,
    locks: const {
      lockedCell: GridLock(cellId: lockedCell, reason: 'temporary closure'),
    },
    isDemo: isDemo,
  );

  test('known lock remains locked after snapshot expiry', () {
    final policy = snapshot();

    expect(
      policy.accessFor(lockedCell, expiresAt.add(const Duration(days: 1))),
      GridAccess.locked,
    );
  });

  test('unlisted cells become unknown when freshness expires', () {
    final policy = snapshot();

    expect(policy.accessFor(openCell, expiresAt), GridAccess.unknown);
    expect(
      policy.canSelectFor(openCell, GridSelectionPurpose.fishing, expiresAt),
      isFalse,
    );
  });

  test(
    'fresh absence permits app fishing selection, but a lock never does',
    () {
      final policy = snapshot();

      expect(policy.accessFor(openCell, fetchedAt), GridAccess.unlocked);
      expect(
        policy.canSelectFor(openCell, GridSelectionPurpose.fishing, fetchedAt),
        isTrue,
      );
      expect(
        policy.canSelectFor(
          lockedCell,
          GridSelectionPurpose.fishing,
          fetchedAt,
        ),
        isFalse,
      );
    },
  );

  test(
    'departure purpose is independent of fishing locks and unknown policy',
    () {
      final policy = snapshot();
      final staleAt = expiresAt.add(const Duration(seconds: 1));

      expect(
        policy.canSelectFor(
          lockedCell,
          GridSelectionPurpose.departure,
          fetchedAt,
        ),
        isTrue,
      );
      expect(
        policy.canSelectFor(openCell, GridSelectionPurpose.departure, staleAt),
        isTrue,
      );
    },
  );

  test('demo snapshot never asserts unlocked access', () {
    final policy = snapshot(isDemo: true);

    expect(policy.accessFor(lockedCell, fetchedAt), GridAccess.locked);
    expect(policy.accessFor(openCell, fetchedAt), GridAccess.unknown);
  });

  test('snapshot parser rejects malformed lock contracts', () {
    expect(
      () => parseGridPolicySnapshot({
        'version': 'v1',
        'fetched_at': fetchedAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
        'locks': [
          {'cell_id': lockedCell, 'reason': 12},
        ],
        'is_demo': false,
      }),
      throwsA(isA<GridPolicyFormatException>()),
    );
  });
}
