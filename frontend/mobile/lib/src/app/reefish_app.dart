import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/presentation/auth_cubit.dart';
import '../auth/domain/auth_repository.dart';
import '../theme/reef_fish_theme.dart';
import '../auth/presentation/auth_screen.dart';
import '../auth/presentation/splash_screen.dart';
import '../auth/presentation/welcome_screen.dart';
import '../map/domain/departure_repository.dart';
import '../map/domain/fishing_point_repository.dart';
import '../map/domain/grid_policy_repository.dart';
import 'departure_entry.dart';
import 'journey_entry.dart';
import '../journey/domain/journey_repository.dart';

enum ReefishInitialPage {
  splash,
  welcome,
  createAccount,
  login,
  departure,
  journey,
  dashboard,
}

extension ReefishInitialPageName on ReefishInitialPage {
  static ReefishInitialPage fromName(String name) => switch (name) {
    'welcome' => ReefishInitialPage.welcome,
    'signup' || 'create-account' => ReefishInitialPage.createAccount,
    'login' => ReefishInitialPage.login,
    'departure' || 'untracked' => ReefishInitialPage.departure,
    'journey' || 'create-journey' => ReefishInitialPage.journey,
    'dashboard' || 'home' => ReefishInitialPage.dashboard,
    _ => ReefishInitialPage.splash,
  };
}

class ReefishApp extends StatefulWidget {
  const ReefishApp({
    required this.authRepository,
    this.initialPage = ReefishInitialPage.splash,
    this.onAuthenticated,
    this.previewSafeArea = false,
    this.gridPolicyRepository,
    this.departureRepository,
    this.fishingPointRepository,
    this.journeyRepository,
    this.journeyDraftStore,
    super.key,
  });

  final AuthRepository authRepository;
  final ReefishInitialPage initialPage;
  final AuthenticatedCallback? onAuthenticated;
  final bool previewSafeArea;
  final GridPolicyRepository? gridPolicyRepository;
  final DepartureRepository? departureRepository;
  final FishingPointRepository? fishingPointRepository;
  final JourneyRepository? journeyRepository;
  final JourneyDraftStore? journeyDraftStore;

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
    // A second SIGNED_IN event can represent switching accounts. Replacing
    // the route also disposes widgets that may hold the previous account's
    // state. Token refresh events are filtered by the repository.
    if (status == AuthSessionStatus.signedOut && previous == status) {
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
        widget.initialPage == ReefishInitialPage.departure
            ? _departureScreen()
            : _hasJourneyBackend
            ? _journeyScreen(
                initialView: widget.initialPage == ReefishInitialPage.journey
                    ? JourneyEntryView.form
                    : widget.initialPage == ReefishInitialPage.dashboard
                    ? JourneyEntryView.dashboard
                    : JourneyEntryView.automatic,
              )
            : _SessionConfirmedScreen(
                authRepository: widget.authRepository,
                onOpenDeparture: _openDeparture,
              ),
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
        return LayoutBuilder(
          builder: (context, constraints) => MediaQuery(
            data: media.copyWith(
              size: constraints.biggest,
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
    ReefishInitialPage.departure => _departureScreen(),
    ReefishInitialPage.journey => _journeyScreen(
      initialView: JourneyEntryView.form,
    ),
    ReefishInitialPage.dashboard => _journeyScreen(
      initialView: JourneyEntryView.dashboard,
    ),
  };

  void _openDeparture() => _navigatorKey.currentState?.push<void>(
    reefishPageRoute(_departureScreen()),
  );

  Widget _departureScreen() => DepartureEntry(
    gridPolicyRepository: widget.gridPolicyRepository,
    departureRepository: widget.departureRepository,
    fishingPointRepository: widget.fishingPointRepository,
    onFishingPointSaved: (selection) => _navigatorKey.currentState?.push<void>(
      reefishPageRoute(
        JourneyEntry(
          repository: widget.journeyRepository,
          draftStore: widget.journeyDraftStore,
          selection: selection,
          initialView: JourneyEntryView.form,
          gridPolicyRepository: widget.gridPolicyRepository,
          onSignIn: _openJourneySignIn,
          onSignOut: widget.authRepository.signOut,
          onBack: () => _navigatorKey.currentState?.pop(),
        ),
      ),
    ),
    onSignIn: () => _navigatorKey.currentState?.push<void>(
      reefishPageRoute(_authScreen(AuthOperation.login)),
    ),
    onBack: () {
      final navigator = _navigatorKey.currentState;
      if (navigator?.canPop() ?? false) {
        navigator!.pop();
      } else {
        _replaceWithWelcome();
      }
    },
  );

  bool get _hasJourneyBackend {
    if (widget.journeyRepository != null) return true;
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  void _openJourneySignIn() => _navigatorKey.currentState?.push<void>(
    reefishPageRoute(_authScreen(AuthOperation.login)),
  );

  Widget _journeyScreen({
    JourneyEntryView initialView = JourneyEntryView.automatic,
  }) => JourneyEntry(
    repository: widget.journeyRepository,
    draftStore: widget.journeyDraftStore,
    initialView: initialView,
    gridPolicyRepository: widget.gridPolicyRepository,
    onSignIn: _openJourneySignIn,
    onSignOut: widget.authRepository.signOut,
    onBack: () {
      final navigator = _navigatorKey.currentState;
      if (navigator?.canPop() ?? false) {
        navigator!.pop();
      } else {
        _replaceWithWelcome();
      }
    },
  );

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
  const _SessionConfirmedScreen({
    required this.authRepository,
    required this.onOpenDeparture,
  });

  final AuthRepository authRepository;
  final VoidCallback onOpenDeparture;

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
                onPressed: widget.onOpenDeparture,
                child: const Text('Simpan titik keberangkatan'),
              ),
              const SizedBox(height: 12),
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
