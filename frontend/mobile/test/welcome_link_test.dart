import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/auth/presentation/welcome_screen.dart';

void main() {
  testWidgets(
    'login link underlines only Masuk and supports pointer and keys',
    (tester) async {
      var loginCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(
            onCreateAccount: (_) {},
            onLogin: (_) => loginCount++,
          ),
        ),
      );

      final footer = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('welcome-login-link')),
          matching: find.byType(Text),
        ),
      );
      final prompt = tester.widget<Text>(find.text('Sudah Punya Akun? '));
      expect(prompt.style?.decoration, isNull);
      final spans = footer.textSpan! as TextSpan;
      expect(
        (spans.children!.last as TextSpan).style?.decoration,
        TextDecoration.underline,
      );

      final link = find.byKey(const Key('welcome-login-link'));
      final inkWell = tester.widget<InkWell>(
        find.descendant(of: link, matching: find.byType(InkWell)),
      );
      expect(inkWell.focusNode?.debugLabel, 'welcome-login-link');
      expect(
        inkWell.overlayColor?.resolve({WidgetState.hovered}),
        Colors.white.withValues(alpha: 0.12),
      );
      expect(
        inkWell.overlayColor?.resolve({WidgetState.pressed}),
        Colors.white.withValues(alpha: 0.24),
      );

      await tester.tap(link);
      expect(loginCount, 1);

      final actualFocusNode = tester
          .widget<InkWell>(
            find.descendant(of: link, matching: find.byType(InkWell)),
          )
          .focusNode!;
      actualFocusNode.requestFocus();
      await tester.pump();
      expect(tester.binding.focusManager.primaryFocus, same(actualFocusNode));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(loginCount, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(loginCount, 3);
    },
  );
}
