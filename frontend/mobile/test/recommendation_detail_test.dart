import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/journey/domain/journey_insights.dart';
import 'package:reefish_mobile/src/journey/domain/journey_models.dart';
import 'package:reefish_mobile/src/journey/presentation/journey_full_map_screen.dart';

void main() {
  testWidgets('detail uses returned metrics and preserves unknown fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: JourneyRecommendationDetailScreen(
          map: const ColoredBox(color: Colors.blueGrey),
          recommendation: const JourneyRecommendation(
            type: 'fuel_saving',
            point: JourneyLatLng(lat: -8.44, lng: 112.68),
            predictedFuelLiters: 12,
            catchRangeKg: [4, 8],
            distanceFromPortKm: null,
            departureTime: null,
            returnTime: null,
            confidence: null,
          ),
          insights: JourneyInsights(
            validUntil: DateTime.utc(2030, 1, 1),
            isFallback: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Detail rekomendasi'), findsOneWidget);
    expect(find.text('Efisiensi BBM'), findsOneWidget);
    expect(find.text('8.4400° S, 112.6800° E'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Potensi tangkapan'), 120);
    expect(find.text('4.0–8.0 kg'), findsOneWidget);
    expect(find.text('12 L'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Sumber: estimasi heuristik'),
      100,
    );
    expect(find.text('Sumber: estimasi heuristik'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Jarak dari pelabuhan'), 100);
    expect(find.text('Jarak dari pelabuhan'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'detail has no own start button; starting lives in the bottom nav',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: JourneyRecommendationDetailScreen(
            map: const ColoredBox(color: Colors.blueGrey),
            recommendation: const JourneyRecommendation(type: 'balanced'),
            insights: JourneyInsights(
              validUntil: DateTime.now().toUtc().subtract(
                const Duration(minutes: 1),
              ),
            ),
            onStartJourney: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Rekomendasi kedaluwarsa atau waktu berlakunya belum tersedia.',
        ),
        findsOneWidget,
      );
      expect(find.text('Mulai Perjalanan'), findsNothing);
      expect(find.text('Tidak berlaku'), findsNothing);
    },
  );
}
