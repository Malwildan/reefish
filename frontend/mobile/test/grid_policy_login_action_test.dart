import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/map/data/device_location_service.dart';
import 'package:reefish_mobile/src/map/domain/departure_repository.dart';
import 'package:reefish_mobile/src/map/domain/geo_point.dart';
import 'package:reefish_mobile/src/map/domain/grid_policy.dart';
import 'package:reefish_mobile/src/map/domain/grid_policy_failure.dart';
import 'package:reefish_mobile/src/map/domain/grid_policy_repository.dart';
import 'package:reefish_mobile/src/map/domain/metric_grid_500.dart';
import 'package:reefish_mobile/src/map/presentation/departure_screen.dart';

const _point = GeoPoint(latitude: -8.433, longitude: 112.683);

void main() {
  testWidgets(
    'missing session offers sign in instead of another cell or blind reload',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var signInCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(430, 932),
              disableAnimations: true,
            ),
            child: DepartureScreen(
              gridPolicyRepository: _SignedOutPolicies(),
              departureRepository: _SavedDeparture(),
              locationService: _Location(),
              onSignIn: () => signInCalls++,
              mapBuilder: (_, __) => const ColoredBox(color: Colors.blueGrey),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(
        find.text('Masuk terlebih dahulu untuk memverifikasi status petak.'),
        findsOneWidget,
      );
      expect(find.text('Muat ulang status'), findsNothing);
      await tester.tap(find.text('Masuk untuk verifikasi'));
      await tester.pump();
      expect(signInCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );
}

class _SignedOutPolicies implements GridPolicyRepository {
  @override
  Future<GridPolicySnapshot> fetchSnapshot() async =>
      throw const GridPolicyFailure(
        GridPolicyFailureCode.authenticationRequired,
      );
}

class _SavedDeparture implements DepartureRepository {
  @override
  Future<DeparturePoint?> read() async => DeparturePoint(
    point: _point,
    cellId: MetricGrid500().resolve(_point).id,
    savedAt: DateTime.utc(2026, 10, 16),
  );
  @override
  Future<void> save(DeparturePoint departure) async {}
}

class _Location implements DeviceLocationService {
  @override
  Future<GeoPoint> getCurrentPosition() async => _point;
}
