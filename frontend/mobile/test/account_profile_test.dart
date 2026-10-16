import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/account/profile_screen.dart';
import 'package:reefish_mobile/src/account/trip_detail_screen.dart';
import 'package:reefish_mobile/src/journey/domain/journey_models.dart';
import 'package:reefish_mobile/src/journey/domain/journey_repository.dart';

void main() {
  testWidgets(
    'profile reads current account and history at narrow width and large text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _FakeJourneyRepository();

      await tester.pumpWidget(
        _app(
          ProfileScreen(
            repository: repository,
            onHome: () {},
            onStartJourney: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Profil'), findsWidgets);
      expect(find.text('+628123456789'), findsOneWidget);
      expect(find.text('12,5 kg'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(repository.getMeCalls, 1);
      expect(repository.listCalls, [1]);
    },
  );

  testWidgets(
    'profile retries failed reads, pages history, and loads detail from repository',
    (tester) async {
      final repository = _FakeJourneyRepository()..failFirstProfileRead = true;
      await tester.pumpWidget(
        _app(
          ProfileScreen(
            repository: repository,
            onHome: () {},
            onStartJourney: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Coba lagi'), findsOneWidget);

      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(repository.listCalls, [1]);
      await tester.drag(find.byType(ListView).first, const Offset(0, -2400));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Muat riwayat lainnya'));
      await tester.tap(find.text('Muat riwayat lainnya'));
      await tester.pumpAndSettle();
      expect(repository.listCalls, [1, 2]);
      expect(find.text('11,0 kg'), findsOneWidget);

      await tester.ensureVisible(
        find.text('Lokasi tidak tersedia di ringkasan').first,
      );
      repository.failFirstDetailRead = true;
      await tester.tap(find.text('Lokasi tidak tersedia di ringkasan').first);
      await tester.pumpAndSettle();
      expect(
        find.text('Detail perjalanan belum dapat dimuat.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(repository.detailCalls, ['trip-9', 'trip-9']);
      expect(repository.detailCallCount, 2);
      expect(find.byType(TripDetailScreen), findsOneWidget);
      expect(find.text('Rincian perjalanan'), findsOneWidget);
      expect(find.textContaining('1,2 L'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
      await tester.drag(find.byType(ListView).last, const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(find.text('Tersimpan di akun'), findsOneWidget);
    },
  );

  testWidgets('detail offers a map only for returned track geometry', (
    tester,
  ) async {
    final repository = _FakeJourneyRepository()
      ..detailTrack = const [
        JourneyLatLng(lat: -8.1, lng: 112.4),
        JourneyLatLng(lat: -8.2, lng: 112.5),
      ];
    expect((await repository.getTripDetail('trip-1')).track.length, 2);
    repository.detailCallCount = 0;
    repository.detailCalls.clear();
    List<JourneyLatLng>? renderedTrack;
    await tester.pumpWidget(
      _app(
        TripDetailScreen(
          repository: repository,
          tripId: 'trip-1',
          trackMapBuilder: (trip) {
            renderedTrack = trip.track;
            return const Center(child: Text('Peta rekaman'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.detailCallCount, 1);
    expect(repository.detailTrack.length, 2);
    expect(find.text('Detail perjalanan belum dapat dimuat.'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('Lihat rekaman perjalanan'), findsOneWidget);
    await tester.ensureVisible(find.text('Lihat rekaman perjalanan'));
    await tester.tap(find.text('Lihat rekaman perjalanan'));
    await tester.pumpAndSettle();
    expect(find.text('Peta rekaman'), findsOneWidget);
    expect(renderedTrack, repository.detailTrack);
  });
}

Widget _app(Widget child) => MaterialApp(
  builder: (context, widget) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: const TextScaler.linear(1.3)),
    child: widget!,
  ),
  home: child,
);

class _FakeJourneyRepository implements JourneyRepository {
  bool failFirstProfileRead = false;
  int getMeCalls = 0;
  final List<int> listCalls = [];
  final List<String> detailCalls = [];
  int detailCallCount = 0;
  bool failFirstDetailRead = false;
  List<JourneyLatLng> detailTrack = const [];

  @override
  Future<JourneyProfile> getMe() async {
    getMeCalls++;
    if (failFirstProfileRead && getMeCalls == 1) throw StateError('offline');
    return const JourneyProfile(
      id: 'owner-1',
      phone: '+628123456789',
      nextStep: JourneyStep.done,
    );
  }

  @override
  Future<JourneyTripHistory> listTrips({
    int page = 1,
    int limit = 20,
    String? from,
    String? to,
    JourneyTripSource? source,
    String sort = '-departed_at',
  }) async {
    listCalls.add(page);
    final trips = page == 1
        ? List.generate(10, (index) => _trip(index + 1))
        : [_trip(11)];
    return JourneyTripHistory(
      trips: trips,
      page: page,
      limit: limit,
      total: 11,
      tripCount: 11,
    );
  }

  JourneyTripSummary _trip(int number) => JourneyTripSummary(
    id: 'trip-$number',
    source: 'manual',
    departedAt: DateTime.utc(2026, 10, 14, 0),
    returnedAt: DateTime.utc(2026, 10, 14, 6),
    catchKg: number == 1 ? 12.5 : number.toDouble(),
    fuelLiters: 2.5,
  );

  @override
  Future<JourneyTripDetail> getTripDetail(
    String id, {
    String track = 'simplified',
  }) async {
    detailCalls.add(id);
    detailCallCount++;
    if (failFirstDetailRead && detailCallCount == 1) {
      throw StateError('offline');
    }
    return JourneyTripDetail(
      id: id,
      source: 'manual',
      departedAt: DateTime.utc(2026, 10, 14),
      returnedAt: DateTime.utc(2026, 10, 14, 6),
      catchKg: 12.5,
      fuelLiters: 1.2,
      departure: const JourneyLatLng(lat: -8.1, lng: 112.4),
      track: detailTrack,
    );
  }

  @override
  Future<JourneyBoat> createBoat(JourneyBoatInput input) =>
      throw UnimplementedError();
  @override
  Future<JourneyTripSubmission> submitTrip(JourneyTripInput input) =>
      throw UnimplementedError();
  @override
  Future<JourneyDashboard> loadDashboard({int tripLimit = 5}) =>
      throw UnimplementedError();
}
