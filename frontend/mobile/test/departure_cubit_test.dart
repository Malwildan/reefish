import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/map/data/device_location_service.dart';
import 'package:reefish_mobile/src/map/domain/departure_repository.dart';
import 'package:reefish_mobile/src/map/domain/fishing_point_repository.dart';
import 'package:reefish_mobile/src/map/domain/geo_point.dart';
import 'package:reefish_mobile/src/map/domain/grid_policy.dart';
import 'package:reefish_mobile/src/map/domain/grid_policy_failure.dart';
import 'package:reefish_mobile/src/map/domain/grid_policy_repository.dart';
import 'package:reefish_mobile/src/map/domain/metric_grid_500.dart';
import 'package:reefish_mobile/src/map/presentation/departure_cubit.dart';

const _point = GeoPoint(latitude: -8.433, longitude: 112.683);
const _fishingPoint = GeoPoint(latitude: -8.438, longitude: 112.69);

void main() {
  group('DepartureCubit', () {
    late _PolicyRepository policy;
    late _DepartureRepository departures;
    late _FishingRepository fishingPoints;
    late _LocationService location;
    late DepartureCubit cubit;

    setUp(() {
      policy = _PolicyRepository();
      departures = _DepartureRepository();
      fishingPoints = _FishingRepository();
      location = _LocationService();
      cubit = DepartureCubit(
        gridPolicyRepository: policy,
        departureRepository: departures,
        fishingPointRepository: fishingPoints,
        locationService: location,
      );
    });

    tearDown(() => cubit.close());

    test(
      'departure remains selectable for locked and unknown policy cells',
      () async {
        final cell = MetricGrid500().resolve(_point);
        policy.snapshot = _snapshot(
          locks: {
            cell.id: GridLock(cellId: cell.id, reason: 'demo restriction'),
          },
        );
        await cubit.refreshPolicy();

        expect(
          cubit.selectPoint(_point, source: DepartureSelectionSource.map),
          isTrue,
        );
        expect(cubit.state.cell?.id, cell.id);
        expect(cubit.state.message, contains('demo restriction'));

        policy.snapshot = _snapshot(
          locks: {
            cell.id: GridLock(cellId: cell.id, reason: 'updated policy reason'),
          },
        );
        await cubit.refreshPolicy();
        expect(cubit.state.message, contains('updated policy reason'));

        policy.snapshot = _snapshot(isDemo: true);
        await cubit.refreshPolicy();
        expect(
          cubit.state.point,
          _point,
          reason: 'policy refresh keeps the selection',
        );
        expect(
          cubit.state.policy?.accessFor(cell.id, DateTime.now()),
          GridAccess.unknown,
        );
        expect(cubit.state.canSave, isTrue);
      },
    );

    test(
      'location denial preserves manual selection and allows save',
      () async {
        cubit.selectPoint(_point, source: DepartureSelectionSource.map);
        location.failure = const LocationServiceFailure(
          'Izin lokasi ditolak. Kamu tetap bisa memilih titik di peta.',
        );

        await cubit.selectCurrentLocation();

        expect(cubit.state.point, _point);
        expect(cubit.state.locating, isFalse);
        expect(cubit.state.message, contains('Izin lokasi ditolak'));
        expect(cubit.state.canSave, isTrue);

        await cubit.save();
        expect(departures.saved?.point, _point);
        expect(cubit.state.saved, isTrue);
      },
    );

    test(
      'manual pick wins when a one-shot GPS request finishes later',
      () async {
        final pending = Completer<GeoPoint>();
        location.pending = pending;
        const anotherPoint = GeoPoint(latitude: -8.438, longitude: 112.69);
        final request = cubit.selectCurrentLocation();
        cubit.selectPoint(anotherPoint, source: DepartureSelectionSource.map);
        pending.complete(_point);
        await request;

        expect(cubit.state.point, anotherPoint);
        expect(cubit.state.source, DepartureSelectionSource.map);
        expect(cubit.state.locating, isFalse);
      },
    );

    test('save is disabled until a valid point is selected', () async {
      expect(cubit.state.canSave, isFalse);
      await cubit.save();
      expect(departures.saved, isNull);
      expect(
        cubit.selectPoint(
          const GeoPoint(latitude: -8.0, longitude: 112.683),
          source: DepartureSelectionSource.map,
        ),
        isFalse,
      );
      expect(cubit.state.canSave, isFalse);
    });

    test(
      'locked and unknown fishing cells cannot be selected or persisted',
      () async {
        final cell = MetricGrid500().resolve(_fishingPoint);
        cubit.selectPoint(_point, source: DepartureSelectionSource.map);
        await cubit.saveAndOpenFishingStep();

        policy.snapshot = _snapshot(
          locks: {cell.id: GridLock(cellId: cell.id, reason: 'zona ditutup')},
        );
        await cubit.refreshPolicy();
        expect(cubit.selectFishingPoint(_fishingPoint), isFalse);
        expect(cubit.state.fishingMessage, contains('zona ditutup'));
        expect(await cubit.completeFishingSelection(), isNull);
        expect(fishingPoints.saved, isNull);

        policy.snapshot = _snapshot(isDemo: true);
        await cubit.refreshPolicy();
        expect(cubit.selectFishingPoint(_fishingPoint), isFalse);
        expect(cubit.state.fishingMessage, contains('belum terverifikasi'));
        expect(await cubit.completeFishingSelection(), isNull);
        expect(fishingPoints.saved, isNull);
      },
    );

    test('fishing save stays separate from the persisted departure', () async {
      cubit.selectPoint(_point, source: DepartureSelectionSource.map);
      await cubit.saveAndOpenFishingStep();
      expect(cubit.state.step, DepartureFlowStep.fishing);
      expect(cubit.selectFishingPoint(_fishingPoint), isTrue);

      final selected = await cubit.completeFishingSelection();
      expect(selected?.point, _fishingPoint);
      expect(fishingPoints.saved?.point, _fishingPoint);
      expect(fishingPoints.saved?.departure.point, _point);
      expect(departures.saved?.point, _point);
      expect(cubit.state.saved, isTrue);
      expect(cubit.state.fishingSaved, isTrue);
    });

    test(
      'fishing selection freezes during policy refresh and writes once',
      () async {
        cubit.selectPoint(_point, source: DepartureSelectionSource.map);
        await cubit.saveAndOpenFishingStep();
        cubit.selectFishingPoint(_fishingPoint);
        final pending = Completer<GridPolicySnapshot>();
        policy.nextFetch = pending;

        final firstSave = cubit.completeFishingSelection();
        expect(cubit.state.fishingSaving, isTrue);
        expect(cubit.selectFishingPoint(_point), isFalse);
        expect(await cubit.completeFishingSelection(), isNull);

        pending.complete(_snapshot());
        final saved = await firstSave;
        expect(saved?.point, _fishingPoint);
        expect(fishingPoints.saveCount, 1);
        expect(fishingPoints.saved?.point, _fishingPoint);
      },
    );

    test(
      'a failed submit refresh cannot reuse an earlier open policy',
      () async {
        cubit.selectPoint(_point, source: DepartureSelectionSource.map);
        await cubit.saveAndOpenFishingStep();
        expect(cubit.selectFishingPoint(_fishingPoint), isTrue);
        final pending = Completer<GridPolicySnapshot>();
        policy.nextFetch = pending;
        final submit = cubit.completeFishingSelection();
        pending.completeError(StateError('offline during submit'));
        expect(await submit, isNull);
        expect(fishingPoints.saveCount, 0);
        expect(cubit.state.fishingSaving, isFalse);
        expect(cubit.state.isError, isTrue);
      },
    );

    test(
      'lost session blocks cached-open cells until policy refresh succeeds',
      () async {
        cubit.selectPoint(_point, source: DepartureSelectionSource.map);
        await cubit.saveAndOpenFishingStep();
        expect(cubit.selectFishingPoint(_fishingPoint), isTrue);
        final pending = Completer<GridPolicySnapshot>();
        policy.nextFetch = pending;
        final refresh = cubit.refreshPolicy();
        pending.completeError(
          const GridPolicyFailure(GridPolicyFailureCode.authenticationRequired),
        );
        expect(await refresh, isFalse);
        for (var i = 0; i < 5; i++) {
          expect(
            cubit.selectFishingPoint(
              GeoPoint(
                latitude: -8.438 - i * .005,
                longitude: 112.69 + i * .005,
              ),
            ),
            isFalse,
          );
          expect(cubit.state.fishingMessage, contains('Masuk terlebih dahulu'));
          expect(cubit.state.canCompleteFishingAt(DateTime.now()), isFalse);
        }
        expect(fishingPoints.saveCount, 0);
        expect(await cubit.refreshPolicy(), isTrue);
        expect(cubit.state.policyFailure, isNull);
        expect(cubit.selectFishingPoint(_fishingPoint), isTrue);
        expect(cubit.state.canCompleteFishingAt(DateTime.now()), isTrue);
      },
    );
  });
}

GridPolicySnapshot _snapshot({
  Map<String, GridLock> locks = const {},
  bool isDemo = false,
}) {
  final now = DateTime.now().toUtc();
  return GridPolicySnapshot(
    version: isDemo ? 'demo' : 'test',
    fetchedAt: now.subtract(const Duration(minutes: 1)),
    expiresAt: now.add(const Duration(minutes: 1)),
    locks: locks,
    isDemo: isDemo,
  );
}

class _PolicyRepository implements GridPolicyRepository {
  GridPolicySnapshot snapshot = _snapshot();
  Completer<GridPolicySnapshot>? nextFetch;
  @override
  Future<GridPolicySnapshot> fetchSnapshot() async {
    final pending = nextFetch;
    nextFetch = null;
    return pending?.future ?? snapshot;
  }
}

class _DepartureRepository implements DepartureRepository {
  DeparturePoint? saved;
  @override
  Future<void> save(DeparturePoint departure) async => saved = departure;
  @override
  Future<DeparturePoint?> read() async => saved;
}

class _FishingRepository implements FishingPointRepository {
  FishingPointSelection? saved;
  int saveCount = 0;
  @override
  Future<void> save(FishingPointSelection selection) async {
    saveCount++;
    saved = selection;
  }

  @override
  Future<FishingPointSelection?> read() async => saved;
}

class _LocationService implements DeviceLocationService {
  Object? failure;
  Completer<GeoPoint>? pending;
  @override
  Future<GeoPoint> getCurrentPosition() {
    if (pending != null) return pending!.future;
    if (failure case final error?) return Future.error(error);
    return Future.value(_point);
  }
}
