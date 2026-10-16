import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/auth/domain/auth_failure.dart';
import 'package:reefish_mobile/src/auth/domain/auth_repository.dart';
import 'package:reefish_mobile/src/auth/presentation/auth_cubit.dart';
import 'package:reefish_mobile/src/auth/presentation/auth_screen.dart';
import 'package:reefish_mobile/src/theme/reef_fish_theme.dart';

void main() {
  testWidgets('country picker changes the selected country and E.164 prefix', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    await tester.pumpWidget(_app(repository));

    await tester.tap(find.text('+62'));
    await tester.pumpAndSettle();
    final search = find.byType(TextField).last;
    await tester.enterText(search, 'United States');
    await tester.pumpAndSettle();
    await tester.tap(find.text('United States').last);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    tester.testTextInput.hide();
    await tester.pumpAndSettle();

    expect(find.text('+1'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '2025550119');
    await tester.enterText(find.byType(TextField).at(1), 'secure-pass');
    await tester.ensureVisible(find.text('Masuk'));
    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();

    expect(repository.phoneE164, '+12025550119');
  });

  testWidgets('focused phone field shows the active border', (tester) async {
    await tester.pumpWidget(_app(_FakeAuthRepository()));
    await tester.tap(find.byType(TextField).first);
    await tester.pump(const Duration(milliseconds: 130));

    final container = tester.widget<AnimatedContainer>(
      find.byKey(const Key('auth-phone-input-container')),
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.border!.top.color, ReefishColors.reef);
  });

  testWidgets('invalid credential feedback keeps values and clears on edit', (
    tester,
  ) async {
    final repository = _FakeAuthRepository()..failNextLogin = true;
    await tester.pumpWidget(_app(repository));
    await tester.enterText(find.byType(TextField).at(0), '081234567890');
    await tester.enterText(find.byType(TextField).at(1), 'wrong-password');
    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();

    expect(
      find.text('Nomor ponsel atau kata sandi tidak sesuai.'),
      findsOneWidget,
    );
    expect(
      _borderColor(tester, 'auth-phone-input-container'),
      ReefishColors.signupAccent,
    );
    expect(
      _borderColor(tester, 'auth-password-input-container'),
      ReefishColors.signupAccent,
    );
    expect(repository.phoneE164, '+6281234567890');
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      '081234567890',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      'wrong-password',
    );

    await tester.enterText(find.byType(TextField).at(1), 'corrected-pass');
    await tester.pumpAndSettle();
    expect(
      find.text('Nomor ponsel atau kata sandi tidak sesuai.'),
      findsNothing,
    );
    expect(
      _borderColor(tester, 'auth-password-input-container'),
      ReefishColors.reef,
    );
  });
}

Color _borderColor(WidgetTester tester, String key) {
  final container = tester.widget<AnimatedContainer>(find.byKey(Key(key)));
  return (container.decoration! as BoxDecoration).border!.top.color;
}

Widget _app(_FakeAuthRepository repository) => MaterialApp(
  theme: ReefishTheme.light,
  home: AuthScreen(
    operation: AuthOperation.login,
    authRepository: repository,
    onAuthenticated: null,
    onBack: (_) {},
  ),
);

class _FakeAuthRepository implements AuthRepository {
  final _sessionController = StreamController<AuthSessionStatus>.broadcast();
  bool failNextLogin = false;
  String? phoneE164;

  @override
  AuthSessionStatus get currentSessionStatus => AuthSessionStatus.signedOut;

  @override
  Stream<AuthSessionStatus> get sessionChanges => _sessionController.stream;

  @override
  Future<AuthResult> createAccount({
    required String phoneE164,
    required String password,
  }) async {
    this.phoneE164 = phoneE164;
    return AuthResult.authenticated;
  }

  @override
  Future<AuthResult> login({
    required String phoneE164,
    required String password,
  }) async {
    this.phoneE164 = phoneE164;
    if (failNextLogin) {
      failNextLogin = false;
      throw const AuthFailure(AuthFailureCode.invalidCredentials);
    }
    return AuthResult.authenticated;
  }

  @override
  Future<void> verifyPhone({
    required String phoneE164,
    required String otp,
  }) async {}

  @override
  Future<void> resendPhoneOtp({required String phoneE164}) async {}

  @override
  Future<void> signOut() async {}
}
