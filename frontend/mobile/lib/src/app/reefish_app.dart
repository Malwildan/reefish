import 'dart:async';

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

class ReefishApp extends StatefulWidget {
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
  State<ReefishApp> createState() => _ReefishAppState();
}

class _ReefishAppState extends State<ReefishApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<AuthSessionStatus>? _sessionSubscription;
  AuthSessionStatus? _lastSessionStatus;
  bool _routeUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    _lastSessionStatus = widget.authRepository.currentSessionStatus;
    _sessionSubscription = widget.authRepository.sessionChanges.listen(
      _handleSessionStatus,
      onError: (Object _, StackTrace __) {
        // Keep the last confirmed state when the SDK stream reports an error.
      },
    );
    if (_lastSessionStatus == AuthSessionStatus.signedIn) {
      _scheduleRouteUpdate();
    }
  }

  @override
  void didUpdateWidget(covariant ReefishApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authRepository == widget.authRepository) return;
    _sessionSubscription?.cancel();
    final previousStatus = _lastSessionStatus;
    _lastSessionStatus = widget.authRepository.currentSessionStatus;
    _sessionSubscription = widget.authRepository.sessionChanges.listen(
      _handleSessionStatus,
      onError: (Object _, StackTrace __) {
        // Keep the last confirmed state when the SDK stream reports an error.
      },
    );
    if (_lastSessionStatus == AuthSessionStatus.signedIn ||
        previousStatus == AuthSessionStatus.signedIn) {
      _scheduleRouteUpdate();
    }
  }

  void _handleSessionStatus(AuthSessionStatus status) {
    final previous = _lastSessionStatus;
    _lastSessionStatus = status;
    if (previous == status) {
      return;
    }
    _scheduleRouteUpdate();
  }

  void _scheduleRouteUpdate() {
    if (_routeUpdateScheduled) return;
    _routeUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routeUpdateScheduled = false;
      if (!mounted) return;
      if (_lastSessionStatus == AuthSessionStatus.signedIn) {
        _replaceWithSessionScreen();
      } else if (_lastSessionStatus == AuthSessionStatus.signedOut) {
        _replaceWithWelcome();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _replaceWithSessionScreen() {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    navigator.pushAndRemoveUntil<void>(
      reefishPageRoute(
        _SessionConfirmedScreen(authRepository: widget.authRepository),
      ),
      (_) => false,
    );
  }

  void _replaceWithWelcome() {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    navigator.pushAndRemoveUntil<void>(
      reefishPageRoute(_welcomeScreen()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Reefish',
      debugShowCheckedModeBanner: false,
      theme: ReefishTheme.light,
      builder: (context, child) {
        final page = child ?? const SizedBox.shrink();
        if (!widget.previewSafeArea) {
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

  Widget _initialScreen() => switch (widget.initialPage) {
    ReefishInitialPage.splash => SplashScreen(
      onComplete: (context) => Navigator.of(
        context,
      ).pushReplacement(reefishPageRoute(_welcomeScreen())),
    ),
    ReefishInitialPage.welcome => _welcomeScreen(),
    ReefishInitialPage.createAccount => _authScreen(
      AuthOperation.createAccount,
    ),
    ReefishInitialPage.login => _authScreen(AuthOperation.login),
  };

  Widget _welcomeScreen() => WelcomeScreen(
    onCreateAccount: (context) => Navigator.of(
      context,
    ).push(reefishPageRoute(_authScreen(AuthOperation.createAccount))),
    onLogin: (context) => Navigator.of(
      context,
    ).push(reefishPageRoute(_authScreen(AuthOperation.login))),
  );

  Widget _authScreen(AuthOperation operation) => AuthScreen(
    operation: operation,
    authRepository: widget.authRepository,
    onAuthenticated: widget.onAuthenticated,
    onBack: (context) => Navigator.of(
      context,
    ).pushReplacement(reefishPageRoute(_welcomeScreen())),
    onLoginFromSignup: operation == AuthOperation.createAccount
        ? (context) => Navigator.of(
            context,
          ).push(reefishPageRoute(_authScreen(AuthOperation.login)))
        : null,
  );
}

class _SessionConfirmedScreen extends StatefulWidget {
  const _SessionConfirmedScreen({required this.authRepository});

  final AuthRepository authRepository;

  @override
  State<_SessionConfirmedScreen> createState() =>
      _SessionConfirmedScreenState();
}

class _SessionConfirmedScreenState extends State<_SessionConfirmedScreen> {
  bool _isSigningOut = false;
  String? _message;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: ReefishColors.canvas,
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.verified_user_outlined, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Akun Reefish terhubung',
                style: TextStyle(
                  color: ReefishColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Sesi masuk aktif. Fitur akun akan tersedia di sini.',
                textAlign: TextAlign.center,
              ),
              if (_message case final message?) ...[
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSigningOut ? null : _signOut,
                child: _isSigningOut
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Keluar'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _signOut() async {
    setState(() {
      _isSigningOut = true;
      _message = null;
    });
    try {
      await widget.authRepository.signOut();
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = 'Tidak dapat keluar sekarang. Coba lagi.');
    } finally {
      if (mounted) setState(() => _isSigningOut = false);
    }
  }
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
