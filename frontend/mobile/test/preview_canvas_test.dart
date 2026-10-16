import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/app/reefish_app.dart';
import 'package:reefish_mobile/src/auth/data/unconfigured_auth_repository.dart';
import 'package:reefish_mobile/src/auth/presentation/welcome_screen.dart';

void main() {
  testWidgets('preview uses the mobile canvas size inside a desktop window', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const Center(
        child: SizedBox(
          width: 430,
          height: 640,
          child: ReefishApp(
            authRepository: UnconfiguredAuthRepository(),
            initialPage: ReefishInitialPage.welcome,
            previewSafeArea: true,
          ),
        ),
      ),
    );
    await tester.pump();
    final pageContext = tester.element(find.byType(WelcomeScreen));
    expect(MediaQuery.sizeOf(pageContext), const Size(430, 640));
    expect(MediaQuery.paddingOf(pageContext).top, 50);
    expect(tester.takeException(), isNull);
  });
}
