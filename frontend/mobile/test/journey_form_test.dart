import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/journey/domain/journey_models.dart';
import 'package:reefish_mobile/src/journey/presentation/create_journey_screen.dart';
import 'package:reefish_mobile/src/map/domain/departure_repository.dart';
import 'package:reefish_mobile/src/map/domain/fishing_point_repository.dart';
import 'package:reefish_mobile/src/map/domain/geo_point.dart';
import 'package:reefish_mobile/src/theme/reef_fish_theme.dart';

void main() {
  final selection = FishingPointSelection(
    point: const GeoPoint(latitude: -8.51, longitude: 112.71),
    cellId: 'internal-cell-id-must-not-be-sent',
    departure: DeparturePoint(
      point: const GeoPoint(latitude: -8.49, longitude: 112.69),
      cellId: 'departure-cell',
      savedAt: DateTime.utc(2026, 10, 1),
    ),
    savedAt: DateTime.utc(2026, 10, 2),
  );

  Future<void> openScreen(
    WidgetTester tester,
    ValueChanged<JourneyTripInput> onSubmit,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    await tester.pumpWidget(
      MaterialApp(
        theme: ReefishTheme.light,
        home: CreateJourneyScreen(selection: selection, onSubmit: onSubmit),
      ),
    );
  }

  Future<void> setText(WidgetTester tester, String key, String value) async {
    final input = find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(TextField),
    );
    await tester.enterText(input, value);
    await tester.pump();
  }

  Future<DateTime> chooseYesterday(WidgetTester tester) async {
    final nowWib = DateTime.now().toUtc().add(const Duration(hours: 7));
    final yesterday = DateTime.utc(
      nowWib.year,
      nowWib.month,
      nowWib.day,
    ).subtract(const Duration(days: 1));
    await tester.tap(find.byKey(const ValueKey('journey-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(yesterday.day.toString()).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pilih'));
    await tester.pumpAndSettle();
    return yesterday;
  }

  testWidgets(
    'submits a completed trip in UTC with WIB date and overnight rollover',
    (tester) async {
      JourneyTripInput? submitted;
      await openScreen(tester, (input) => submitted = input);
      final yesterday = await chooseYesterday(tester);
      await setText(tester, 'journey-fuel', '18.5');
      await setText(tester, 'journey-catch', '27');
      await setText(tester, 'journey-depart-hour', '22');
      await setText(tester, 'journey-depart-minute', '15');
      await setText(tester, 'journey-return-hour', '02');
      await setText(tester, 'journey-return-minute', '45');
      await tester.tap(find.byKey(const ValueKey('journey-submit')));
      await tester.pump();

      expect(submitted, isNotNull);
      expect(submitted!.source, JourneyTripSource.onboarding);
      expect(submitted!.fuelLiters, 18.5);
      expect(submitted!.catchKg, 27);
      expect(submitted!.departure!.lat, -8.49);
      expect(submitted!.departure!.lng, 112.69);
      expect(submitted!.returnPoint!.lat, -8.49);
      expect(submitted!.fishingPoints.single.point.lat, -8.51);
      expect(submitted!.fishingPoints.single.point.lng, 112.71);
      expect(submitted!.fishingPoints.single.startedAt, isNull);
      expect(
        submitted!.fishingPoints.single.endedAt,
        isNull,
        reason: 'Trip duration must not be invented as fishing duration',
      );
      expect(
        submitted!.fishingPoints.single.toJson(),
        isNot(contains('cell_id')),
      );
      expect(submitted!.clientTripId, isNotEmpty);
      expect(
        submitted!.departedAt,
        DateTime.utc(yesterday.year, yesterday.month, yesterday.day, 15, 15),
      );
      expect(
        submitted!.returnedAt,
        DateTime.utc(yesterday.year, yesterday.month, yesterday.day, 19, 45),
      );
    },
  );

  testWidgets('defaults untouched minutes to zero when hours are entered', (
    tester,
  ) async {
    JourneyTripInput? submitted;
    await openScreen(tester, (input) => submitted = input);
    final yesterday = await chooseYesterday(tester);
    await setText(tester, 'journey-fuel', '12');
    await setText(tester, 'journey-catch', '14');
    await setText(tester, 'journey-depart-hour', '05');
    await setText(tester, 'journey-return-hour', '19');
    await tester.tap(find.byKey(const ValueKey('journey-submit')));
    await tester.pump();

    expect(submitted, isNotNull);
    expect(
      submitted!.departedAt,
      DateTime.utc(yesterday.year, yesterday.month, yesterday.day - 1, 22),
    );
    expect(
      submitted!.returnedAt,
      DateTime.utc(yesterday.year, yesterday.month, yesterday.day, 12),
    );
  });

  testWidgets('does not infer midnight when both hour fields are empty', (
    tester,
  ) async {
    await openScreen(tester, (_) {});
    await setText(tester, 'journey-fuel', '12');
    await setText(tester, 'journey-catch', '14');
    await tester.tap(find.byKey(const ValueKey('journey-submit')));
    await tester.pump();

    expect(find.text('Jam berangkat wajib diisi (00–23).'), findsOneWidget);
  });

  testWidgets('reports a cleared minute field as invalid', (tester) async {
    await openScreen(tester, (_) {});
    await setText(tester, 'journey-fuel', '12');
    await setText(tester, 'journey-catch', '14');
    await setText(tester, 'journey-depart-hour', '05');
    await setText(tester, 'journey-return-hour', '19');
    await setText(tester, 'journey-depart-minute', '');
    await tester.tap(find.byKey(const ValueKey('journey-submit')));
    await tester.pump();

    expect(find.text('Menit berangkat wajib diisi (00–59).'), findsOneWidget);
  });

  testWidgets(
    'equal departure and return times stay invalid instead of becoming a 24 hour trip',
    (tester) async {
      var submitCount = 0;
      await openScreen(tester, (_) => submitCount++);
      await chooseYesterday(tester);
      await setText(tester, 'journey-fuel', '10');
      await setText(tester, 'journey-catch', '0');
      await setText(tester, 'journey-depart-hour', '08');
      await setText(tester, 'journey-depart-minute', '30');
      await setText(tester, 'journey-return-hour', '08');
      await setText(tester, 'journey-return-minute', '30');
      await tester.tap(find.byKey(const ValueKey('journey-submit')));
      await tester.pump();

      expect(submitCount, 0);
      expect(
        find.byKey(const ValueKey('journey-form-message')),
        findsOneWidget,
      );
      expect(
        find.text('Jam pulang harus setelah jam berangkat.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('rejects non-positive fuel before producing a trip', (
    tester,
  ) async {
    var submitted = false;
    await openScreen(tester, (_) => submitted = true);
    await setText(tester, 'journey-fuel', '0');
    await setText(tester, 'journey-catch', '0');
    await tester.tap(find.byKey(const ValueKey('journey-submit')));
    await tester.pump();

    expect(submitted, isFalse);
    expect(
      find.text('Masukkan bensin lebih dari 0 dan maksimal 500 liter.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'stays scrollable at 360px and 1.3 text scale with keyboard open',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpWidget(
        MaterialApp(
          theme: ReefishTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: CreateJourneyScreen(onSubmit: (_) {}, selection: selection),
        ),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('journey-catch')));
      await tester.pump();
      await tester.showKeyboard(
        find.descendant(
          of: find.byKey(const ValueKey('journey-catch')),
          matching: find.byType(TextField),
        ),
      );
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('journey-submit')));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey('journey-submit'))).dy,
        lessThanOrEqualTo(500),
      );
      expect(find.byKey(const ValueKey('journey-date')), findsOneWidget);
    },
  );

  testWidgets('uses a rejected trip as editable prefill', (tester) async {
    JourneyTripInput? submitted;
    final initial = JourneyTripInput(
      clientTripId: 'previously-rejected-trip',
      source: JourneyTripSource.manual,
      departedAt: DateTime.utc(2026, 10, 10, 2),
      returnedAt: DateTime.utc(2026, 10, 10, 7),
      fuelLiters: 15,
      catchKg: 24,
      fishingPoints: const [
        JourneyFishingPointInput(point: JourneyLatLng(lat: -8.5, lng: 112.7)),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ReefishTheme.light,
        home: CreateJourneyScreen(
          selection: selection,
          initialTrip: initial,
          source: JourneyTripSource.manual,
          onSubmit: (value) => submitted = value,
        ),
      ),
    );
    final fuelField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('journey-fuel')),
        matching: find.byType(TextField),
      ),
    );
    expect(fuelField.controller!.text, '15.0');
    await setText(tester, 'journey-catch', '30');
    await tester.tap(find.byKey(const ValueKey('journey-submit')));
    await tester.pump();

    expect(submitted, isNotNull);
    expect(submitted!.source, JourneyTripSource.manual);
    expect(submitted!.fuelLiters, 15);
    expect(submitted!.catchKg, 30);
    expect(submitted!.clientTripId, isNot('previously-rejected-trip'));
  });
}
