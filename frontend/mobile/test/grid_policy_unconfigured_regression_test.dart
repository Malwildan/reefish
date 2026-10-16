import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/map/data/device_location_service.dart';
import 'package:reefish_mobile/src/map/data/unconfigured_grid_policy_repository.dart';
import 'package:reefish_mobile/src/map/domain/departure_repository.dart';
import 'package:reefish_mobile/src/map/domain/geo_point.dart';
import 'package:reefish_mobile/src/map/presentation/departure_cubit.dart';

const _departure = GeoPoint(latitude: -8.433, longitude: 112.683);

void main() {
  test(
    'unconfigured service explains setup across five cells and reloads',
    () async {
      final cubit = DepartureCubit(
        gridPolicyRepository: const UnconfiguredGridPolicyRepository(),
        departureRepository: _Departures(),
        locationService: _Location(),
      );
      addTearDown(cubit.close);
      await cubit.initialize();
      cubit.selectPoint(_departure, source: DepartureSelectionSource.map);
      await cubit.saveAndOpenFishingStep();
      for (var i = 0; i < 5; i++) {
        cubit.selectFishingPoint(
          GeoPoint(latitude: -8.438 - i * .005, longitude: 112.69 + i * .005),
        );
        await cubit.refreshPolicy();
        expect(cubit.state.fishingMessage, contains('belum dikonfigurasi'));
        expect(cubit.state.canCompleteFishingAt(DateTime.now()), isFalse);
      }
    },
  );
}

class _Departures implements DepartureRepository {
  DeparturePoint? point;
  @override
  Future<DeparturePoint?> read() async => point;
  @override
  Future<void> save(DeparturePoint departure) async => point = departure;
}

class _Location implements DeviceLocationService {
  @override
  Future<GeoPoint> getCurrentPosition() async => _departure;
}
