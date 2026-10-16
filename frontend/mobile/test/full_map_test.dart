import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/journey/domain/journey_insights.dart';
import 'package:reefish_mobile/src/journey/presentation/journey_full_map_screen.dart';

void main() {
  testWidgets('full map shows live weather fields or unknown values', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: JourneyFullMapScreen(
          map: ColoredBox(color: Colors.blueGrey),
          insights: JourneyInsights(
            weather: JourneyWeather(
              tempC: null,
              windSpeedMs: null,
              waveHeightM: 0.8,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Peta Laut'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('0.8 m'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full map back button invokes its callback', (tester) async {
    var backCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: JourneyFullMapScreen(
          map: const ColoredBox(color: Colors.blueGrey),
          onBack: () => backCount++,
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Kembali'));
    expect(backCount, 1);
  });
}
