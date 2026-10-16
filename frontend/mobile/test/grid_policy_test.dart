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

  test('parsing without a live receipt keeps absolute server expiry', () {
    final policy = parseGridPolicySnapshot({
      'version': '7',
      'fetched_at': '2026-10-16T01:00:00.000Z',
      'expires_at': '2026-10-16T01:05:00.000Z',
      'is_demo': false,
      'locks': <Object>[],
    });

    expect(policy.validFrom, isNull);
    expect(policy.validUntil, isNull);
    expect(policy.isFreshAt(DateTime.utc(2026, 10, 16, 9, 35)), isFalse);
  });

  test(
    'parsed policy uses receipt-relative validity without extending TTL',
    () {
      final receivedAt = DateTime.utc(2026, 10, 16, 9, 35);
      final policy = parseGridPolicySnapshot(
        {
          'version': '7',
          'fetched_at': '2099-10-16T04:00:00.000Z',
          'expires_at': '2099-10-16T04:05:00.000Z',
          'is_demo': false,
          'locks': <Object>[],
        },
        receivedAt: receivedAt,
        requestDuration: const Duration(seconds: 30),
      );

      expect(policy.fetchedAt, DateTime.utc(2099, 10, 16, 4));
      expect(policy.expiresAt, DateTime.utc(2099, 10, 16, 4, 5));
      expect(policy.isFreshAt(receivedAt), isTrue);
      expect(
        policy.isFreshAt(
          receivedAt.add(const Duration(minutes: 4, seconds: 29)),
        ),
        isTrue,
      );
      expect(
        policy.isFreshAt(
          receivedAt.add(const Duration(minutes: 4, seconds: 30)),
        ),
        isFalse,
      );
    },
  );

  test('a request that consumes the whole server TTL stays unknown', () {
    final receivedAt = DateTime.utc(2026, 10, 16, 9, 35);
    final policy = parseGridPolicySnapshot(
      {
        'version': '7',
        'fetched_at': '2099-10-16T04:00:00.000Z',
        'expires_at': '2099-10-16T04:05:00.000Z',
        'is_demo': false,
        'locks': <Object>[],
      },
      receivedAt: receivedAt,
      requestDuration: const Duration(minutes: 5, seconds: 1),
    );

    expect(policy.isFreshAt(receivedAt), isFalse);
    expect(policy.accessFor('unlisted-cell', receivedAt), GridAccess.unknown);
  });

  test('effective validity must be paired and bounded by server TTL', () {
    expect(
      () => GridPolicySnapshot(
        version: '7',
        fetchedAt: fetchedAt,
        expiresAt: expiresAt,
        locks: const {},
        validFrom: fetchedAt,
      ),
      throwsArgumentError,
    );
    expect(
      () => GridPolicySnapshot(
        version: '7',
        fetchedAt: fetchedAt,
        expiresAt: expiresAt,
        locks: const {},
        validFrom: fetchedAt,
        validUntil: expiresAt.add(const Duration(seconds: 1)),
      ),
      throwsArgumentError,
    );
  });
}
