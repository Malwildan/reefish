import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/journey/domain/journey_insights.dart';
import 'package:reefish_mobile/src/journey/presentation/journey_dashboard_screen.dart';
import 'package:reefish_mobile/src/journey/presentation/journey_full_map_screen.dart';

void main() {
  test('weather and prediction fields preserve missing API values', () {
    final weather = JourneyWeather.fromJson({
      'temp_c': null,
      'wind_speed_ms': null,
      'wave_height_m': null,
      'risk': 'unknown',
    });
    final recommendation = JourneyRecommendation.fromJson({
      'type': 'catch_max',
      'predicted_fuel_liters': null,
      'predicted_catch_kg': null,
      'predicted_catch_range_kg': null,
      'confidence': null,
    });

    expect(weather.tempC, isNull);
    expect(weather.windSpeedMs, isNull);
    expect(weather.waveHeightM, isNull);
    expect(weather.risk, 'unknown');
    expect(recommendation.predictedFuelLiters, isNull);
    expect(recommendation.predictedCatchKg, isNull);
    expect(recommendation.catchRangeKg, isNull);
    expect(recommendation.confidence, isNull);
  });

  testWidgets(
    'dashboard explains missing weather without showing Figma values',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
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
          home: const JourneyDashboardScreen(map: SizedBox.expand()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cuaca belum tersedia'), findsOneWidget);
      expect(find.text('Rekomendasi belum tersedia.'), findsOneWidget);
      expect(find.text('29°C'), findsNothing);
      expect(find.text('12km/jam'), findsNothing);
      expect(find.text('15 L'), findsNothing);
      expect(find.text('Tinggi'), findsNothing);
    },
  );

  testWidgets('dashboard shows API weather values, source, and freshness', (
    tester,
  ) async {
    final fetchedAt = DateTime.parse('2026-10-16T05:00:00Z');
    await tester.pumpWidget(
      MaterialApp(
        home: JourneyDashboardScreen(
          insights: JourneyInsights(
            weather: JourneyWeather.fromJson({
              'time': '2026-10-16T05:00:00Z',
              'weather_label': 'Berawan sebagian',
              'temp_c': 27.4,
              'wind_speed_ms': 4.2,
              'wave_height_m': 0.8,
              'risk': 'low',
            }),
            weatherFetchedAt: fetchedAt,
          ),
          map: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cuaca hari ini Berawan sebagian'), findsOneWidget);
    expect(find.text('27.4 °C'), findsOneWidget);
    expect(find.text('15.1 km/jam'), findsOneWidget);
    expect(find.text('0.8 m'), findsOneWidget);
    expect(find.text('Sumber cuaca: '), findsOneWidget);
    expect(find.text('Open-Meteo'), findsOneWidget);
    expect(find.text('DWD'), findsOneWidget);
    expect(find.textContaining('Data dimuat: '), findsOneWidget);
    expect(find.textContaining('Prakiraan: '), findsOneWidget);
  });

  testWidgets('dashboard states that weather needs a home port', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: JourneyDashboardScreen(
          insights: JourneyInsights(
            weatherMessage: 'Tambahkan lokasi pelabuhan untuk memuat cuaca.',
          ),
          map: SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Tambahkan lokasi pelabuhan untuk memuat cuaca.'),
      findsOneWidget,
    );
    expect(find.text('29°C'), findsNothing);
  });

  testWidgets('shows API recommendation values and fallback provenance', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    final recommendation = JourneyRecommendation.fromJson({
      'id': 'rec-1',
      'type': 'fuel_saving',
      'point': {'lat': -8.44, 'lng': 112.68},
      'predicted_fuel_liters': 15.0,
      'predicted_catch_range_kg': [12.0, 18.0],
      'departure_time': '04:30',
      'return_time': '11:00',
      'confidence': 0.72,
      'reason': 'Angin dan gelombang sesuai rentang perjalanan.',
      'weather_summary': {
        'wind_speed_ms': 4.2,
        'wave_height_m': 0.8,
        'risk': 'low',
      },
    });
    final insights = JourneyInsights(
      recommendations: [recommendation],
      generatedAt: now,
      validUntil: now.add(const Duration(hours: 2)),
      isFallback: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: JourneyDashboardScreen(
          insights: insights,
          map: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Efisiensi Bensin'), findsOneWidget);
    expect(find.text('15 L'), findsOneWidget);
    expect(find.text('12.0–18.0 kg'), findsOneWidget);
    await tester.ensureVisible(find.text('Lihat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lihat'));
    await tester.pumpAndSettle();

    expect(find.byType(JourneyRecommendationDetailScreen), findsOneWidget);
    final detailList = find.descendant(
      of: find.byType(JourneyRecommendationDetailScreen),
      matching: find.byType(ListView),
    );
    // Drag below the embedded map, which owns its own pan gestures.
    await tester.dragFrom(
      tester.getBottomLeft(detailList) + const Offset(16, -24),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sumber: estimasi heuristik'), findsOneWidget);
    expect(
      find.text('Angin dan gelombang sesuai rentang perjalanan.'),
      findsOneWidget,
    );
    expect(find.text('04:30'), findsOneWidget);
    await tester.dragFrom(
      tester.getBottomLeft(detailList) + const Offset(16, -24),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Berlaku hingga: '), findsOneWidget);
  });

  testWidgets('expired recommendation has no active view action', (
    tester,
  ) async {
    final insights = JourneyInsights(
      recommendations: const [
        JourneyRecommendation(type: 'balanced', predictedFuelLiters: 15),
      ],
      validUntil: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: JourneyDashboardScreen(
          insights: insights,
          map: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rekomendasi kedaluwarsa'), findsOneWidget);
    expect(find.text('Kedaluwarsa'), findsOneWidget);
    expect(find.text('15 L'), findsNothing);
  });
}
