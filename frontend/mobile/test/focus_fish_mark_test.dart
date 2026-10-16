import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/map/presentation/widgets/focus_fish_mark.dart';

void main() {
  testWidgets('fish mark follows and repeats its two-second motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: FocusFishMark(variant: FocusFishMarkVariant.map)),
        ),
      ),
    );

    final atRest = _animatedOffsets(tester);
    expect(atRest, hasLength(3));
    for (final offset in atRest) {
      expect(offset.dx, closeTo(0, 1e-6));
      expect(offset.dy, closeTo(0, 1e-6));
    }

    await tester.pump(const Duration(milliseconds: 600));
    final midCycle = _animatedOffsets(tester);
    expect(midCycle, hasLength(3));
    for (final offset in midCycle) {
      expect(offset.dx, closeTo(1.662, 1e-3));
      expect(offset.dy, closeTo(-1.746, 1e-3));
    }

    await tester.pump(const Duration(milliseconds: 1400));
    final afterFullCycle = _animatedOffsets(tester);
    expect(afterFullCycle, hasLength(3));
    for (final offset in afterFullCycle) {
      expect(offset.dx, closeTo(atRest.first.dx, 1e-6));
      expect(offset.dy, closeTo(atRest.first.dy, 1e-6));
    }
  });

  testWidgets('reduced motion stays at rest without scheduling frames', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Center(
              child: FocusFishMark(variant: FocusFishMarkVariant.sheet),
            ),
          ),
        ),
      ),
    );

    final atRest = _animatedOffsets(tester);
    expect(atRest, hasLength(3));
    await tester.pump(const Duration(seconds: 5));

    final afterWait = _animatedOffsets(tester);
    expect(afterWait, hasLength(3));
    for (var i = 0; i < afterWait.length; i++) {
      expect(afterWait[i].dx, closeTo(atRest[i].dx, 1e-6));
      expect(afterWait[i].dy, closeTo(atRest[i].dy, 1e-6));
    }
    expect(tester.binding.transientCallbackCount, 0);
  });
}

List<Offset> _animatedOffsets(WidgetTester tester) => tester
    .widgetList<Transform>(find.byType(Transform))
    .where((transform) => transform.child is LayoutBuilder)
    .map((transform) {
      final translation = transform.transform.getTranslation();
      return Offset(translation.x, translation.y);
    })
    .toList();
