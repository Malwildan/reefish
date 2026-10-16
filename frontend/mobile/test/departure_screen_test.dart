import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/map/data/device_location_service.dart';
import 'package:reefish_mobile/src/map/domain/departure_repository.dart';
import 'package:reefish_mobile/src/map/domain/fishing_point_repository.dart';
import 'package:reefish_mobile/src/map/domain/geo_point.dart';
import 'package:reefish_mobile/src/map/domain/grid_policy.dart';
import 'package:reefish_mobile/src/map/domain/grid_policy_repository.dart';
import 'package:reefish_mobile/src/map/presentation/departure_screen.dart';

const _departure = GeoPoint(latitude: -8.433, longitude: 112.683);
const _fishing = GeoPoint(latitude: -8.438, longitude: 112.69);

void main() {
  testWidgets('refreshes grid policy when returning to the app', (
    tester,
  ) async {
    final policy = _TestPolicy();
    await tester.pumpWidget(
      MaterialApp(
        home: DepartureScreen(
          gridPolicyRepository: policy,
          departureRepository: _TestDepartures(),
          mapBuilder: (_, __) => const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    expect(policy.requests, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(policy.requests, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(policy.requests, 2);
  });

  testWidgets('layout fits a narrow screen with enlarged text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(1.3),
            disableAnimations: true,
          ),
          child: DepartureScreen(
            gridPolicyRepository: _TestPolicy(),
            departureRepository: _TestDepartures(),
            locationService: _TestLocation(),
            mapBuilder: (context, onPointPicked) =>
                const ColoredBox(color: Color(0xFFE8EEEE)),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Simpan Titik Keberangkatan'), findsOneWidget);
    expect(find.text('Pilih Lokasi Saat Ini'), findsOneWidget);
    expect(find.text('Lihat Peta'), findsOneWidget);
    expect(find.text('Simpan'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Pilih Lokasi Saat Ini'));
    await tester.tap(find.text('Pilih Lokasi Saat Ini'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Edit'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Simpan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Tempatkan titik ikan?'), findsOneWidget);
    expect(find.text('Selesai'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual map selection confirms and persists before fish stage', (
    tester,
  ) async {
    final departures = _TestDepartures();
    final fishing = _TestFishingPoints();
    var mapPick = 0;
    var departureNotifications = 0;
    var fishingNotifications = 0;
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(430, 932),
            disableAnimations: true,
          ),
          child: DepartureScreen(
            gridPolicyRepository: _TestPolicy(),
            departureRepository: departures,
            fishingPointRepository: fishing,
            onSaved: (_) => departureNotifications++,
            onFishingPointSaved: (_) => fishingNotifications++,
            locationService: _TestLocation(),
            mapBuilder: (context, onPointPicked) => GestureDetector(
              key: const Key('manual-map'),
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  onPointPicked(mapPick++ == 0 ? _departure : _fishing),
              child: const ColoredBox(color: Color(0xFFE8EEEE)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('Lihat Peta'));
    await tester.pump();
    await tester.tapAt(const Offset(180, 250));
    await tester.pump();
    await tester.tap(find.text('Gunakan titik ini'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('Edit'), findsOneWidget);
    expect(departures.saved, isNull);
    expect(find.text('Titik keberangkatan'), findsOneWidget);

    await tester.tap(find.text('Simpan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(departures.saved?.point, _departure);
    expect(find.text('Tempatkan titik ikan?'), findsOneWidget);
    expect(fishing.saved, isNull);

    expect(find.byType(SnackBar), findsNothing);

    await tester.tapAt(const Offset(180, 250));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.textContaining('Titik penangkapan'), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Selesai'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(fishing.saved?.point, _fishing);
    expect(fishing.saved?.departure.point, _departure);
    expect(departures.saved?.point, _departure);
    expect(departureNotifications, 1);
    expect(fishingNotifications, 1);

    ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold)),
    ).hideCurrentSnackBar();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.bySemanticsLabel('Kembali'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Edit'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Pilih Lokasi Saat Ini'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Simpan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(departureNotifications, 2);
    expect(
      fishingNotifications,
      1,
      reason: 'Saving another departure must not notify an old fishing choice',
    );
    expect(tester.takeException(), isNull);
  });
}

class _TestPolicy implements GridPolicyRepository {
  int requests = 0;
  @override
  Future<GridPolicySnapshot> fetchSnapshot() async {
    requests++;
    final now = DateTime.now().toUtc();
    return GridPolicySnapshot(
      version: 'test',
      fetchedAt: now,
      expiresAt: now.add(const Duration(hours: 1)),
      locks: const {},
    );
  }
}

class _TestDepartures implements DepartureRepository {
  DeparturePoint? saved;
  @override
  Future<void> save(DeparturePoint departure) async => saved = departure;
  @override
  Future<DeparturePoint?> read() async => null;
}

class _TestFishingPoints implements FishingPointRepository {
  FishingPointSelection? saved;
  @override
  Future<void> save(FishingPointSelection selection) async => saved = selection;
  @override
  Future<FishingPointSelection?> read() async => saved;
}

class _TestLocation implements DeviceLocationService {
  @override
  Future<GeoPoint> getCurrentPosition() async => _departure;
}
