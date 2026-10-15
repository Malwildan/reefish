import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/app/reefish_app.dart';
import 'package:reefish_mobile/src/auth/data/unconfigured_auth_repository.dart';
import 'package:reefish_mobile/src/auth/domain/auth_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('welcome navigates to signup, login, and back', (tester) async {
    final repository = _FakeAuthRepository();
    await tester.pumpWidget(ReefishApp(
      authRepository: repository,
      initialPage: ReefishInitialPage.welcome,
    ));

    await tester.tap(find.text('Mulai'));
    await tester.pumpAndSettle();
    expect(find.text('Daftar'), findsOneWidget);
    expect(find.text('Nomor Telepon'), findsAtLeastNWidgets(1));

    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is Text &&
        widget.textSpan?.toPlainText().contains('Sudah Punya Akun?') == true));
    await tester.pumpAndSettle();
    expect(find.text('Masuk'), findsOneWidget);

    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is Semantics && widget.properties.label == 'Kembali'));
    await tester.pumpAndSettle();
    expect(find.text('Daftar'), findsOneWidget);

    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is Semantics && widget.properties.label == 'Kembali'));
    await tester.pumpAndSettle();
    expect(find.text('Mulai'), findsOneWidget);

    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is Text &&
        widget.textSpan?.toPlainText().contains('Sudah Punya Akun?') == true));
    await tester.pumpAndSettle();
    expect(find.text('Masuk'), findsOneWidget);

    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is Semantics && widget.properties.label == 'Kembali'));
    await tester.pumpAndSettle();
    expect(find.text('Mulai'), findsOneWidget);
  });

  testWidgets(
      'invalid form input is shown inline and never reaches the repository',
      (tester) async {
    final repository = _FakeAuthRepository();
    await tester.pumpWidget(ReefishApp(
      authRepository: repository,
      initialPage: ReefishInitialPage.createAccount,
    ));

    await tester.enterText(find.byType(TextField).at(0), '081234567890');
    await tester.enterText(find.byType(TextField).at(1), 'short');
    final passwordField = find.byType(TextField).at(1);
    expect(tester.widget<TextField>(passwordField).obscureText, isTrue);
    await tester.tap(find.byTooltip('Tampilkan kata sandi'));
    await tester.pump();
    expect(tester.widget<TextField>(passwordField).obscureText, isFalse);
    await tester.tap(find.byTooltip('Sembunyikan kata sandi'));
    await tester.pump();
    expect(tester.widget<TextField>(passwordField).obscureText, isTrue);

    await tester.tap(find.text('Daftar'));
    await tester.pumpAndSettle();

    expect(repository.createAccountCalls, 0);
    expect(find.text('Kata sandi minimal 8 karakter.'), findsOneWidget);
  });

  testWidgets(
      'pending login disables submit and duplicate taps call repository once',
      (tester) async {
    final repository = _FakeAuthRepository()..pending = Completer<void>();
    await tester.pumpWidget(ReefishApp(
      authRepository: repository,
      initialPage: ReefishInitialPage.login,
    ));
    await tester.enterText(find.byType(TextField).at(0), '081234567890');
    await tester.enterText(find.byType(TextField).at(1), 'secure-pass');
    final submit = find.text('Masuk');

    await tester.tap(submit);
    await tester.pump();
    expect(repository.loginCalls, 1);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(repository.loginCalls, 1);

    repository.pending!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('unconfigured auth explains the failure and stays on login',
      (tester) async {
    await tester.pumpWidget(const ReefishApp(
      authRepository: UnconfiguredAuthRepository(),
      initialPage: ReefishInitialPage.login,
    ));
    await tester.enterText(find.byType(TextField).at(0), '081234567890');
    await tester.enterText(find.byType(TextField).at(1), 'private-password');
    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();

    expect(find.text('Layanan akun belum terhubung. Coba lagi nanti.'),
        findsOneWidget);
    expect(find.text('Masuk'), findsOneWidget);
    expect(find.text('Dashboard'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
        isTrue);
  });

  testWidgets('splash timer is cancelled when its route is removed',
      (tester) async {
    await tester.pumpWidget(ReefishApp(
      authRepository: _FakeAuthRepository(),
    ));
    expect(find.text('Reefish'), findsOneWidget);

    await tester.pumpWidget(ReefishApp(
      authRepository: _FakeAuthRepository(),
      initialPage: ReefishInitialPage.welcome,
    ));
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('Mulai'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(ReefishApp(
      authRepository: _FakeAuthRepository(),
    ));
    await tester.pump(const Duration(milliseconds: 2499));
    expect(find.text('Mulai'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('Mulai'), findsOneWidget);
  });

  testWidgets(
      'compact viewport with keyboard inset and larger text has no overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    tester.binding.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(ReefishApp(
      authRepository: _FakeAuthRepository(),
      initialPage: ReefishInitialPage.createAccount,
    ));
    final passwordField = find.byType(TextField).at(1);
    await tester.ensureVisible(passwordField);
    await tester.pump();
    expect(tester.getRect(passwordField).bottom, lessThanOrEqualTo(380));
    await tester.enterText(passwordField, 'secure-pass');
    expect(find.byType(TextField), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}

class _FakeAuthRepository implements AuthRepository {
  int createAccountCalls = 0;
  int loginCalls = 0;
  Completer<void>? pending;

  @override
  Future<void> createAccount(
      {required String phoneE164, required String password}) {
    createAccountCalls++;
    return pending?.future ?? Future<void>.value();
  }

  @override
  Future<void> login({required String phoneE164, required String password}) {
    loginCalls++;
    return pending?.future ?? Future<void>.value();
  }
}
