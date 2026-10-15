import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/presentation/auth_cubit.dart';
import '../auth/domain/auth_repository.dart';
import '../theme/reef_fish_theme.dart';
import '../auth/presentation/auth_screen.dart';
import '../auth/presentation/splash_screen.dart';
import '../auth/presentation/welcome_screen.dart';

enum ReefishInitialPage { splash, welcome, createAccount, login }

extension ReefishInitialPageName on ReefishInitialPage {
  static ReefishInitialPage fromName(String name) => switch (name) {
        'welcome' => ReefishInitialPage.welcome,
        'signup' || 'create-account' => ReefishInitialPage.createAccount,
        'login' => ReefishInitialPage.login,
        _ => ReefishInitialPage.splash,
      };
}

class ReefishApp extends StatelessWidget {
  const ReefishApp({
    required this.authRepository,
    this.initialPage = ReefishInitialPage.splash,
    this.onAuthenticated,
    this.previewSafeArea = false,
    super.key,
  });

  final AuthRepository authRepository;
  final ReefishInitialPage initialPage;
  final AuthenticatedCallback? onAuthenticated;
  final bool previewSafeArea;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reefish',
      debugShowCheckedModeBanner: false,
      theme: ReefishTheme.light,
      builder: (context, child) {
        final page = child ?? const SizedBox.shrink();
        if (!previewSafeArea) {
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
            ),
            child: page,
          );
        }
        final media = MediaQuery.of(context);
        const previewPadding = EdgeInsets.only(top: 50, bottom: 34);
        return MediaQuery(
          data: media.copyWith(
            padding: previewPadding,
            viewPadding: previewPadding,
          ),
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
            ),
            child: page,
          ),
        );
      },
      home: _initialScreen(),
    );
  }

  Widget _initialScreen() => switch (initialPage) {
        ReefishInitialPage.splash => SplashScreen(
            onComplete: (context) => Navigator.of(context)
                .pushReplacement(reefishPageRoute(_welcomeScreen())),
          ),
        ReefishInitialPage.welcome => _welcomeScreen(),
        ReefishInitialPage.createAccount => _authScreen(
            AuthOperation.createAccount,
          ),
        ReefishInitialPage.login => _authScreen(AuthOperation.login),
      };

  Widget _welcomeScreen() => WelcomeScreen(
        onCreateAccount: (context) => Navigator.of(context)
            .push(reefishPageRoute(_authScreen(AuthOperation.createAccount))),
        onLogin: (context) => Navigator.of(context)
            .push(reefishPageRoute(_authScreen(AuthOperation.login))),
      );

  Widget _authScreen(AuthOperation operation) => AuthScreen(
        operation: operation,
        authRepository: authRepository,
        onAuthenticated: onAuthenticated,
        onBack: (context) => Navigator.of(context)
            .pushReplacement(reefishPageRoute(_welcomeScreen())),
        onLoginFromSignup: operation == AuthOperation.createAccount
            ? (context) => Navigator.of(context)
                .push(reefishPageRoute(_authScreen(AuthOperation.login)))
            : null,
      );
}

PageRoute<T> reefishPageRoute<T>(Widget child) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 450),
      reverseTransitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (_, __, ___) => child,
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
        child: child,
      ),
    );
