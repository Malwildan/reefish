import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../account/account_permission_preferences.dart';
import '../account/permissions_screen.dart';
import '../account/profile_screen.dart';
import '../journey/data/go_journey_insights_repository.dart';
import '../journey/data/shared_preferences_journey_draft_store.dart';
import '../journey/data/supabase_journey_repository.dart';
import '../journey/domain/journey_insights.dart';
import '../journey/domain/journey_models.dart';
import '../journey/domain/journey_repository.dart';
import '../journey/presentation/boat_setup_screen.dart';
import '../journey/presentation/create_journey_screen.dart';
import '../journey/presentation/journey_cubit.dart';
import '../journey/presentation/journey_dashboard_screen.dart';
import '../journey/presentation/journey_full_map_screen.dart';
import '../journey/presentation/widgets/journey_dashboard_map.dart';
import '../map/data/local_fishing_point_repository.dart';
import '../map/domain/fishing_point_repository.dart';
import '../map/domain/geo_point.dart';
import '../map/domain/grid_policy.dart';
import '../map/domain/grid_policy_repository.dart';
import '../map/domain/metric_grid_500.dart';
import '../map/data/supabase_grid_policy_repository.dart';
import '../map/data/unconfigured_grid_policy_repository.dart';
import '../sailing/application/sailing_bloc.dart';
import '../sailing/data/geolocator_sailing_location_source.dart';
import '../sailing/data/shared_preferences_sailing_session_store.dart';
import '../sailing/domain/sailing_location_source.dart';
import '../sailing/domain/sailing_session.dart';
import '../sailing/domain/sailing_session_store.dart';
import '../sailing/presentation/journey_mode_screen.dart';
import '../sailing/presentation/sailing_session_screen.dart';
import '../theme/reef_fish_theme.dart';
import 'departure_entry.dart';
import 'reefish_app.dart';

enum JourneyEntryView { automatic, form, dashboard }

/// Owns one signed-in journey workflow. Account switches replace this route.
class JourneyEntry extends StatefulWidget {
  const JourneyEntry({
    this.repository,
    this.draftStore,
    this.selection,
    this.initialView = JourneyEntryView.automatic,
    this.gridPolicyRepository,
    this.onSignIn,
    this.onSignOut,
    this.onBack,
    this.sailingSessionStore,
    this.sailingLocationSource,
    super.key,
  });

  final JourneyRepository? repository;
  final JourneyDraftStore? draftStore;
  final FishingPointSelection? selection;
  final JourneyEntryView initialView;
  final GridPolicyRepository? gridPolicyRepository;
  final VoidCallback? onSignIn;
  final Future<void> Function()? onSignOut;
  final VoidCallback? onBack;
  final SailingSessionStore? sailingSessionStore;
  final SailingLocationSource? sailingLocationSource;

  @override
  State<JourneyEntry> createState() => _JourneyEntryState();
}

class _JourneyEntryState extends State<JourneyEntry>
    with WidgetsBindingObserver {
  JourneyCubit? _cubit;
  JourneyRepository? _repository;
  SailingBloc? _sailingBloc;
  AccountPermissionPreferences? _permissionPreferences;
  String? _ownerId;
  StreamSubscription<AuthState>? _accountSubscription;
  bool _accountChanged = false;
  FishingPointSelection? _selection;
  JourneyLatLng? _homePort;
  JourneyInsights? _insights;
  JourneyTripInput? _editableTrip;
  bool _insightsLoading = false;
  String? _setupError;
  GoJourneyInsightsRepository? _insightsRepository;
  SailingSession? _recordedSession;
  String? _pendingSailingAckId;
  String? _fallbackClientTripId;
  bool _sailingClearInFlight = false;
  bool _manualFallback = false;
  String? _sessionCleanupError;
  bool _onboardingConsentShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selection = widget.selection;
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      SupabaseClient? client;
      try {
        client = Supabase.instance.client;
      } catch (_) {
        // Direct UI previews may run without an initialized backend client.
      }
      final owner = client?.auth.currentUser?.id ?? 'preview-anonymous';
      if (client != null) {
        _accountSubscription = client.auth.onAuthStateChange.listen((event) {
          final nextOwner = event.session?.user.id;
          if (!mounted || _accountChanged || nextOwner == owner) return;
          unawaited(
            _sailingBloc?.pauseTracking().catchError((Object _) {}) ??
                Future<void>.value(),
          );
          if (nextOwner == null) {
            return; // The app's sign-out route owns this case.
          }
          _accountChanged = true;
          setState(() => _setupError = 'Memuat akun yang sedang aktif…');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).pushAndRemoveUntil<void>(
              reefishPageRoute(
                JourneyEntry(
                  gridPolicyRepository: widget.gridPolicyRepository,
                  onSignIn: widget.onSignIn,
                  onSignOut: widget.onSignOut,
                  onBack: widget.onBack,
                ),
              ),
              (_) => false,
            );
          });
        });
      }
      _ownerId = owner;
      _permissionPreferences = SharedPreferencesAccountPermissionPreferences(
        preferences: preferences,
      );
      if (_selection == null) {
        try {
          _selection = await LocalFishingPointRepository(
            preferences: preferences,
            ownerId: owner,
          ).read();
        } catch (_) {
          // Preserve invalid local records and allow a new explicit selection.
        }
      }
      if (!mounted) return;
      _repository =
          widget.repository ??
          (client == null
              ? const _UnavailableJourneyRepository()
              : SupabaseJourneyRepository(client: client));
      final cubit = JourneyCubit(
        repository: _repository!,
        draftStore:
            widget.draftStore ??
            SharedPreferencesJourneyDraftStore(
              preferences: preferences,
              ownerId: owner,
            ),
      );
      final sailingBloc = SailingBloc(
        store:
            widget.sailingSessionStore ??
            SharedPreferencesSailingSessionStore(
              preferences: preferences,
              ownerId: owner,
            ),
        locationSource:
            widget.sailingLocationSource ??
            const GeolocatorSailingLocationSource(),
      );
      _sailingBloc = sailingBloc;
      await sailingBloc.restoreSession();
      final restored = sailingBloc.state.session;
      if (restored?.phase == SailingPhase.completed) {
        if (_canSubmitSession(restored!)) {
          _recordedSession = restored;
        } else {
          _incompleteSession = restored;
        }
      }
      const apiUrl = String.fromEnvironment('REEFISH_API_URL');
      final uri = Uri.tryParse(apiUrl);
      if (client != null &&
          uri != null &&
          uri.hasAuthority &&
          (uri.scheme == 'https' || uri.scheme == 'http')) {
        _insightsRepository = GoJourneyInsightsRepository(client, uri);
      }
      setState(() => _cubit = cubit);
      await cubit.initialize();
      if (!mounted) return;
      await _maybeShowOnboardingConsent(cubit);
      if (!mounted) return;
      if (widget.initialView == JourneyEntryView.form &&
          cubit.state.phase == JourneyPhase.dashboard) {
        await cubit.beginTrip();
      }
      final restoredPending = cubit.state.pendingDraft?.trip;
      if (restoredPending != null &&
          restored?.clientTripId == restoredPending.clientTripId) {
        _pendingSailingAckId = restored!.clientTripId;
        _incompleteSession = null;
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _setupError = 'Penyimpanan perjalanan belum dapat dibuka.',
        );
      }
    }
  }

  Future<void> _maybeShowOnboardingConsent(JourneyCubit cubit) async {
    final owner = _ownerId;
    final preferences = _permissionPreferences;
    final profile = cubit.state.profile;
    if (_onboardingConsentShown ||
        owner == null ||
        owner == 'preview-anonymous' ||
        preferences == null ||
        profile?.role != 'nelayan' ||
        (profile?.nextStep != JourneyStep.boat &&
            profile?.nextStep != JourneyStep.firstTrip)) {
      return;
    }
    final accepted = await preferences.termsAccepted(owner);
    if (!mounted || accepted) return;
    _onboardingConsentShown = true;
    await Navigator.of(context).push<void>(
      reefishPageRoute(
        PermissionsScreen(
          ownerId: owner,
          variant: PermissionsScreenVariant.onboardingConsent,
          onCompleted: (_) => Navigator.of(context).pop(),
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accountSubscription?.cancel();
    _cubit?.close();
    _insightsRepository?.close();
    _sailingBloc?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      final bloc = _sailingBloc;
      if (bloc != null && bloc.state.session?.phase != SailingPhase.completed) {
        unawaited(bloc.pauseTracking().catchError((Object _) {}));
      }
    }
  }

  String? _message(JourneyState state) {
    if (state.failure == null) return null;
    if (state.profile?.role == 'konservatif') {
      return 'Gunakan dashboard web untuk akun konservasi.';
    }
    if (state.tripSubmitted) {
      return 'Perjalanan sudah tersimpan. Dashboard belum dapat dimuat; coba muat ulang.';
    }
    return switch (state.failure!.code) {
      JourneyFailureCode.authenticationRequired =>
        'Masuk untuk menyimpan dan memuat perjalananmu.',
      JourneyFailureCode.apiNotAvailable =>
        'Layanan perjalanan belum tersedia. Data belum dikirim.',
      JourneyFailureCode.storage =>
        'Catatan tersimpan di perangkat belum dapat dibuka. Coba lagi.',
      JourneyFailureCode.validation => _validationMessage(state.failure!),
      JourneyFailureCode.backend =>
        state.tripSubmitted
            ? 'Perjalanan sudah tersimpan. Dashboard belum dapat dimuat; coba muat ulang.'
            : state.pendingDraft != null
            ? 'Perjalanan belum terkonfirmasi tersimpan. Coba kirim lagi dengan data yang sama.'
            : 'Data perjalanan belum dapat dimuat. Coba muat ulang.',
    };
  }

  Future<void> _loadInsights(JourneyState state) async {
    final point = state.profile?.boat?.homePort;
    final repository = _insightsRepository;
    if (_insightsLoading) return;
    if (repository == null) {
      if (point == null && mounted) {
        setState(
          () => _insights = const JourneyInsights(
            weatherMessage: 'Tambahkan lokasi pelabuhan untuk memuat cuaca.',
          ),
        );
      }
      return;
    }
    setState(() => _insightsLoading = true);
    try {
      final data = await repository.load(point: point);
      if (mounted) setState(() => _insights = data);
    } catch (_) {
      if (mounted) setState(() => _insights = null);
    } finally {
      if (mounted) setState(() => _insightsLoading = false);
    }
  }

  Future<void> _chooseLocation({bool departureOnly = false}) async {
    await Navigator.of(context).push<void>(
      reefishPageRoute(
        DepartureEntry(
          gridPolicyRepository: widget.gridPolicyRepository,
          onSignIn: widget.onSignIn,
          onBack: () => Navigator.of(context).pop(),
          onSaved: departureOnly
              ? (departure) {
                  Navigator.of(context).pop();
                  setState(
                    () => _homePort = JourneyLatLng(
                      lat: departure.point.latitude,
                      lng: departure.point.longitude,
                    ),
                  );
                }
              : null,
          onFishingPointSaved: departureOnly
              ? null
              : (selection) {
                  Navigator.of(context).pop();
                  setState(() => _selection = selection);
                },
        ),
      ),
    );
  }

  void _showProfile(JourneyState state) {
    final repository = _repository;
    if (repository == null) return;
    Navigator.of(context).push<void>(
      reefishPageRoute(
        ProfileScreen(
          repository: repository,
          onHome: () => Navigator.of(context).pop(),
          onStartJourney: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
            _openJourneyMode();
          },
          onPermissions: () => _openPermissions(),
          onSignOut: widget.onSignOut,
        ),
      ),
    );
  }

  void _showFullMap(JourneyState state) {
    Navigator.of(context).push<void>(
      reefishPageRoute(
        JourneyFullMapScreen(
          homePort: state.profile?.boat?.homePort,
          insights: _insights,
        ),
      ),
    );
  }

  void _openJourneyMode() {
    if (_sailingBloc?.state.session != null) {
      _resumeSailing();
      return;
    }
    final homePort = _cubit?.state.profile?.boat?.homePort;
    Navigator.of(context).push<void>(
      reefishPageRoute(
        JourneyModeScreen(
          map: JourneyDashboardMap(homePort: homePort, rounded: false),
          onCancel: () => Navigator.of(context).pop(),
          onContinue: (mode) {
            Navigator.of(context).pop();
            if (mode == JourneyMode.manual) {
              _beginManualTrip();
            } else {
              _beginTrackedTrip();
            }
          },
        ),
      ),
    );
  }

  Future<void> _beginManualTrip() async {
    final cubit = _cubit;
    if (cubit == null) return;
    final selection = await _chooseManualFishingPoint();
    if (!mounted || selection == null) return;
    setState(() {
      _editableTrip = null;
      _selection = selection;
      _manualFallback = false;
      _recordedSession = null;
      _fallbackClientTripId = null;
    });
    await cubit.beginTrip();
  }

  Future<FishingPointSelection?> _chooseManualFishingPoint() async {
    final result = Completer<FishingPointSelection?>();
    var completed = false;
    void finish(FishingPointSelection? selection) {
      if (completed) return;
      completed = true;
      if (!result.isCompleted) result.complete(selection);
    }

    await Navigator.of(context).push<void>(
      reefishPageRoute(
        DepartureEntry(
          gridPolicyRepository: widget.gridPolicyRepository,
          onSignIn: widget.onSignIn,
          onBack: () {
            Navigator.of(context).pop();
            finish(null);
          },
          onFishingPointSaved: (selection) {
            Navigator.of(context).pop();
            finish(selection);
          },
        ),
      ),
    );
    finish(null);
    return result.future;
  }

  Future<void> _beginTrackedTrip() async {
    if (!_isCurrentAccount()) return;
    final ownerId = _ownerId;
    final preferences = _permissionPreferences;
    if (ownerId == null ||
        ownerId == 'preview-anonymous' ||
        preferences == null) {
      _showMessage('Masuk ke akun untuk mencatat lokasi perjalanan.');
      return;
    }
    final allowed = await preferences.trackingAllowed(ownerId);
    if (!mounted) return;
    if (!allowed) {
      final termsAccepted = await preferences.termsAccepted(ownerId);
      if (!mounted) return;
      _openPermissions(
        onboardingConsent: !termsAccepted,
        onCompleted: (enabled) {
          Navigator.of(context).pop();
          if (enabled) {
            _chooseSailingDeparture();
          } else {
            _showMessage(
              'Lokasi tidak diaktifkan. Kamu tetap dapat mencatat perjalanan manual.',
            );
            _openJourneyMode();
          }
        },
      );
      return;
    }
    _chooseSailingDeparture();
  }

  Future<void> _resumeSailing() async {
    if (!_isCurrentAccount()) return;
    final bloc = _sailingBloc;
    final session = bloc?.state.session;
    final ownerId = _ownerId;
    final preferences = _permissionPreferences;
    if (bloc == null ||
        session == null ||
        ownerId == null ||
        preferences == null) {
      return;
    }
    if (session.ownerId != ownerId) {
      _showMessage('Sesi perjalanan ini tersimpan untuk akun lain.');
      return;
    }
    if (session.phase == SailingPhase.completed) {
      if (_pendingSailingAckId == session.clientTripId) {
        await _clearAcknowledgedSailingSession();
        return;
      }
      _handleCompletedSession(session, closeSessionRoute: false);
      return;
    }
    if (!await preferences.trackingAllowed(ownerId)) {
      if (!mounted) return;
      final termsAccepted = await preferences.termsAccepted(ownerId);
      if (!mounted) return;
      _openPermissions(
        onboardingConsent: !termsAccepted,
        onCompleted: (enabled) {
          Navigator.of(context).pop();
          if (enabled) {
            _resumeSailing();
          } else {
            _showMessage(
              'Sesi tetap tersimpan di perangkat dan pencatatan lokasi dijeda.',
            );
          }
        },
      );
      return;
    }
    await bloc.resumeTracking();
    if (mounted) _openSailingSession();
  }

  void _openPermissions({
    ValueChanged<bool>? onCompleted,
    bool onboardingConsent = false,
  }) {
    final owner = _ownerId;
    if (owner == null || owner == 'preview-anonymous') {
      _showMessage('Masuk ke akun untuk mengatur izin lokasi.');
      return;
    }
    Navigator.of(context).push<void>(
      reefishPageRoute(
        PermissionsScreen(
          ownerId: owner,
          variant: onboardingConsent
              ? PermissionsScreenVariant.onboardingConsent
              : PermissionsScreenVariant.settings,
          onBack: () => Navigator.of(context).pop(),
          onCompleted: onCompleted ?? _onPermissionSettingsSaved,
          onHome: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
          onStartJourney: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
            _openJourneyMode();
          },
        ),
      ),
    );
  }

  Future<void> _onPermissionSettingsSaved(bool enabled) async {
    if (!enabled) {
      try {
        await _sailingBloc?.pauseTracking();
      } catch (_) {
        // SailingBloc keeps the last durable state and exposes the pause error.
      }
    }
    if (mounted) Navigator.of(context).pop(enabled);
  }

  void _chooseSailingDeparture() {
    Navigator.of(context).push<void>(
      reefishPageRoute(
        DepartureEntry(
          gridPolicyRepository: widget.gridPolicyRepository,
          departureRepository: null,
          fishingPointRepository: null,
          onSignIn: widget.onSignIn,
          onBack: () => Navigator.of(context).pop(),
          onSaved: (departure) async {
            Navigator.of(context).pop();
            final bloc = _sailingBloc;
            final owner = _ownerId;
            if (bloc == null || owner == null || owner == 'preview-anonymous') {
              _showMessage('Akun belum siap untuk memulai pencatatan.');
              return;
            }
            if (!await (_permissionPreferences?.trackingAllowed(owner) ??
                Future<bool>.value(false))) {
              if (mounted) {
                final termsAccepted =
                    await (_permissionPreferences?.termsAccepted(owner) ??
                        Future<bool>.value(false));
                if (!mounted) return;
                _openPermissions(
                  onboardingConsent: !termsAccepted,
                  onCompleted: (enabled) {
                    Navigator.of(context).pop();
                    if (enabled) {
                      _chooseSailingDeparture();
                    } else {
                      _showMessage(
                        'Lokasi tidak diaktifkan. Kamu tetap dapat mencatat perjalanan manual.',
                      );
                      _openJourneyMode();
                    }
                  },
                );
              }
              return;
            }
            await bloc.startSailing(
              ownerId: owner,
              departure: SailingPoint(
                lat: departure.point.latitude,
                lng: departure.point.longitude,
              ),
            );
            if (!mounted) return;
            if (bloc.state.session == null) {
              _showMessage(bloc.state.error ?? 'Perjalanan belum dimulai.');
              return;
            }
            _openSailingSession();
          },
        ),
      ),
    );
  }

  void _openSailingSession() {
    final bloc = _sailingBloc;
    if (bloc == null) return;
    Navigator.of(context).push<void>(
      reefishPageRoute(
        SailingSessionScreen(
          bloc: bloc,
          mapBuilder: (session) {
            final lastFix = session?.track.isNotEmpty == true
                ? session!.track.last
                : null;
            final last = lastFix?.point;
            final isCurrent =
                session?.locationStatus == SailingLocationStatus.available &&
                lastFix != null &&
                DateTime.now().toUtc().difference(lastFix.recordedAt).abs() <=
                    const Duration(minutes: 2);
            return JourneyDashboardMap(
              homePort: _cubit?.state.profile?.boat?.homePort,
              center: last == null
                  ? session?.departure
                  : JourneyLatLng(lat: last.lat, lng: last.lng),
              departure: session?.departure,
              plannedPoint: session?.plannedFishingPoint,
              currentPosition: isCurrent ? last : null,
              followPosition: true,
              fishingPoint: session?.actualFishingPoint,
              track:
                  session?.track
                      .map(
                        (point) => JourneyLatLng(
                          lat: point.point.lat,
                          lng: point.point.lng,
                        ),
                      )
                      .toList(growable: false) ??
                  const [],
              rounded: false,
            );
          },
          onMarkFishing: _confirmActualFishingPoint,
          onResumeTracking: _resumeTrackedLocation,
          onCompleted: _handleCompletedSession,
          onBack: () async {
            try {
              await bloc.pauseTracking();
            } catch (_) {
              _showMessage(
                'Pencatatan dijeda, tetapi status lokal belum dapat diperbarui.',
              );
            }
            if (mounted) Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Future<void> _confirmActualFishingPoint() async {
    final bloc = _sailingBloc;
    if (bloc == null || bloc.state.session == null) return;
    if (!await _requireTrackingOptIn(
      onAllowed: () => unawaited(_confirmActualFishingPoint()),
    )) {
      return;
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: Duration(seconds: 12),
      ),
    );
    final now = DateTime.now().toUtc();
    final fixTime = position.timestamp.toUtc();
    if (!position.accuracy.isFinite ||
        position.accuracy <= 0 ||
        position.accuracy > 100 ||
        fixTime.isBefore(now.subtract(const Duration(minutes: 2))) ||
        fixTime.isAfter(now.add(const Duration(seconds: 30)))) {
      throw StateError(
        'Akurasi GPS saat ini belum cukup untuk mengonfirmasi titik.',
      );
    }
    final point = GeoPoint(
      latitude: position.latitude,
      longitude: position.longitude,
    );
    final cell = MetricGrid500().resolve(point);
    final repository = widget.gridPolicyRepository ?? _policyRepository();
    final snapshot = await repository.fetchSnapshot();
    final access = snapshot.accessFor(cell.id, DateTime.now());
    if (access != GridAccess.unlocked) {
      throw StateError(
        access == GridAccess.locked
            ? 'Petak ini terkunci untuk menangkap ikan.'
            : 'Status lock petak belum terverifikasi. Titik belum dicatat.',
      );
    }
    if (!mounted) return;
    final usePoint = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi titik penangkapan'),
        content: Text(
          'Gunakan lokasi GPS saat ini sebagai titik penangkapan ikan?\n\n'
          '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Periksa lagi'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Gunakan titik ini'),
          ),
        ],
      ),
    );
    if (usePoint == true) {
      if (!await (_permissionPreferences?.trackingAllowed(_ownerId ?? '') ??
          Future<bool>.value(false))) {
        if (mounted) {
          _promptTrackingPermission(
            onAllowed: () => unawaited(_confirmActualFishingPoint()),
            message:
                'Lokasi belum dicatat. Izinkan pencatatan lalu konfirmasi ulang.',
          );
        }
        return;
      }
      final confirmTime = DateTime.now().toUtc();
      if (fixTime.isBefore(confirmTime.subtract(const Duration(minutes: 2))) ||
          fixTime.isAfter(confirmTime.add(const Duration(seconds: 30)))) {
        throw StateError('Lokasi GPS sudah tidak cukup baru. Periksa kembali.');
      }
      final confirmedSnapshot = await repository.fetchSnapshot();
      final confirmedAccess = confirmedSnapshot.accessFor(
        cell.id,
        DateTime.now(),
      );
      if (confirmedAccess != GridAccess.unlocked) {
        throw StateError(
          confirmedAccess == GridAccess.locked
              ? 'Petak terkunci. Titik belum dicatat.'
              : 'Status lock petak belum terverifikasi. Titik belum dicatat.',
        );
      }
      await bloc.markFishing(
        actualPoint: SailingPoint(
          lat: position.latitude,
          lng: position.longitude,
        ),
      );
    }
  }

  Future<bool> _requireTrackingOptIn({required VoidCallback onAllowed}) async {
    if (!_isCurrentAccount()) return false;
    final owner = _ownerId;
    final preferences = _permissionPreferences;
    if (owner == null || owner == 'preview-anonymous' || preferences == null) {
      _showMessage('Masuk ke akun untuk memakai lokasi perjalanan.');
      return false;
    }
    if (await preferences.trackingAllowed(owner)) return true;
    if (!mounted) return false;
    _promptTrackingPermission(onAllowed: onAllowed);
    return false;
  }

  Future<void> _promptTrackingPermission({
    required VoidCallback onAllowed,
    String message = 'Pencatatan lokasi dinonaktifkan untuk akun ini.',
  }) async {
    final owner = _ownerId;
    final preferences = _permissionPreferences;
    if (owner == null || owner == 'preview-anonymous' || preferences == null) {
      _showMessage(message);
      return;
    }
    final termsAccepted = await preferences.termsAccepted(owner);
    if (!mounted) return;
    _openPermissions(
      onboardingConsent: !termsAccepted,
      onCompleted: (enabled) {
        Navigator.of(context).pop();
        if (enabled) {
          onAllowed();
        } else {
          _showMessage(message);
        }
      },
    );
  }

  Future<void> _resumeTrackedLocation() async {
    final bloc = _sailingBloc;
    if (bloc == null) return;
    if (!await _requireTrackingOptIn(
      onAllowed: () => unawaited(_resumeTrackedLocation()),
    )) {
      return;
    }
    await bloc.resumeTracking();
  }

  bool _isCurrentAccount() {
    if (_accountChanged) return false;
    try {
      if (Supabase.instance.client.auth.currentUser?.id == _ownerId) {
        return true;
      }
      _showMessage(
        'Akun telah berubah. Buka ulang halaman sebelum melanjutkan.',
      );
      return false;
    } catch (_) {
      return widget.repository != null; // Explicit local test dependency only.
    }
  }

  GridPolicyRepository _policyRepository() {
    try {
      return SupabaseGridPolicyRepository(client: Supabase.instance.client);
    } catch (_) {
      return const UnconfiguredGridPolicyRepository();
    }
  }

  void _handleCompletedSession(
    SailingSession session, {
    bool closeSessionRoute = true,
  }) {
    final isSubmittable = _canSubmitSession(session);
    if (!mounted) return;
    if (isSubmittable) {
      setState(() {
        _recordedSession = session;
        _manualFallback = false;
        _incompleteSession = null;
      });
    } else {
      setState(() {
        _recordedSession = null;
        _manualFallback = false;
        _incompleteSession = session;
      });
    }
    if (closeSessionRoute && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  bool _canSubmitSession(SailingSession session) =>
      session.phase == SailingPhase.completed &&
      session.departedAt != null &&
      session.returnedAt != null &&
      session.actualFishingPoint != null &&
      session.fishingStartedAt != null &&
      session.fishingEndedAt != null &&
      session.track.length >= 2;

  SailingSession? _incompleteSession;

  void _continueManualFallback() {
    setState(() {
      _fallbackClientTripId = _incompleteSession?.clientTripId;
      _incompleteSession = null;
      _manualFallback = true;
      _recordedSession = null;
      _selection = null;
      _editableTrip = null;
    });
    _cubit?.beginTrip();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _clearAcknowledgedSailingSession() async {
    final id = _pendingSailingAckId;
    final bloc = _sailingBloc;
    if (_sailingClearInFlight ||
        id == null ||
        bloc == null ||
        bloc.state.session?.clientTripId != id) {
      return;
    }
    _sailingClearInFlight = true;
    if (mounted) setState(() => _recordedSession = null);
    try {
      await bloc.clearAcknowledgedSession(id);
      if (mounted) {
        setState(() {
          _pendingSailingAckId = null;
          _recordedSession = null;
          _fallbackClientTripId = null;
          _sessionCleanupError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _sessionCleanupError =
              'Perjalanan tersimpan di server, tetapi salinan perangkat belum dapat dibersihkan.',
        );
      }
    } finally {
      _sailingClearInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = _cubit;
    if (_setupError != null) {
      return Scaffold(
        body: SafeArea(child: Center(child: Text(_setupError!))),
      );
    }
    if (cubit == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return BlocProvider.value(
      value: cubit,
      child: BlocConsumer<JourneyCubit, JourneyState>(
        listenWhen: (previous, current) =>
            (current.phase == JourneyPhase.dashboard &&
                previous.phase != current.phase) ||
            (current.tripSubmitted && !previous.tripSubmitted),
        listener: (context, state) {
          if (state.phase == JourneyPhase.dashboard) _loadInsights(state);
          // the transition into tripSubmitted is the server acknowledgement of a trip
          if (state.tripSubmitted && state.phase != JourneyPhase.dashboard) {
            _showMessage('Perjalanan tersimpan. Lihat di Profil › Riwayat.');
          }
          if (state.tripSubmitted &&
              _pendingSailingAckId == null &&
              state.pendingDraft != null &&
              _sailingBloc?.state.session?.clientTripId ==
                  state.pendingDraft!.trip.clientTripId) {
            _pendingSailingAckId = state.pendingDraft!.trip.clientTripId;
          }
          if (state.tripSubmitted && _pendingSailingAckId != null) {
            unawaited(_clearAcknowledgedSailingSession());
          }
        },
        builder: (context, state) {
          final busy =
              state.phase == JourneyPhase.loading ||
              state.phase == JourneyPhase.submittingTrip;
          final message = _message(state);
          if (_incompleteSession != null) {
            return _IncompleteSailingSessionScreen(
              onRecordManually: _continueManualFallback,
              onLater: () => setState(() => _incompleteSession = null),
            );
          }
          final dashboardView =
              _recordedSession == null &&
              !_manualFallback &&
              (state.phase == JourneyPhase.dashboard ||
                  state.tripSubmitted ||
                  (widget.initialView == JourneyEntryView.dashboard &&
                      state.profile?.nextStep != JourneyStep.boat &&
                      state.profile?.nextStep != JourneyStep.firstTrip) ||
                  (widget.initialView == JourneyEntryView.automatic &&
                      state.phase == JourneyPhase.error &&
                      state.pendingDraft == null));
          if (dashboardView) {
            return JourneyDashboardScreen(
              dashboard: state.dashboard,
              insights: _insights,
              loading: busy || _insightsLoading,
              message: _sessionCleanupError ?? message,
              onRefresh: () async {
                if (state.tripSubmitted && _pendingSailingAckId != null) {
                  await _clearAcknowledgedSailingSession();
                }
                await cubit.refresh();
                if (mounted) await _loadInsights(cubit.state);
              },
              onStartJourney: state.profile?.role == 'konservatif'
                  ? null
                  : () {
                      if (state.failure?.code ==
                          JourneyFailureCode.authenticationRequired) {
                        widget.onSignIn?.call();
                        return;
                      }
                      _openJourneyMode();
                    },
              onOpenMap: () => _showFullMap(state),
              onOpenProfile: () => _showProfile(state),
            );
          }
          if (state.phase == JourneyPhase.boat ||
              (state.profile?.nextStep == JourneyStep.boat &&
                  !state.tripSubmitted)) {
            return BoatSetupScreen(
              homePort:
                  _homePort ??
                  (_selection == null
                      ? null
                      : JourneyLatLng(
                          lat: _selection!.departure.point.latitude,
                          lng: _selection!.departure.point.longitude,
                        )),
              busy: busy,
              message: message,
              onSubmit: cubit.saveBoat,
              onBack: widget.onBack,
              onChooseLocation: () => _chooseLocation(departureOnly: true),
            );
          }
          if (state.profile == null &&
              busy &&
              widget.initialView == JourneyEntryView.automatic) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return CreateJourneyScreen(
            key: ValueKey(
              state.pendingDraft?.trip.clientTripId ??
                  _recordedSession?.clientTripId ??
                  'new-trip',
            ),
            selection: _selection,
            pendingTrip: state.pendingDraft?.trip,
            initialTrip: _editableTrip,
            recordedSession: _recordedSession,
            clientTripId: _fallbackClientTripId,
            onEditPending:
                state.failure?.code == JourneyFailureCode.validation &&
                    state.pendingDraft != null
                ? () async {
                    final input = state.pendingDraft!.trip;
                    _editableTrip = input;
                    await cubit.editRejectedTrip();
                    if (mounted && cubit.state.pendingDraft == null) {
                      setState(() => _editableTrip = input);
                    }
                  }
                : null,
            source:
                _recordedSession != null ||
                    _manualFallback ||
                    state.profile?.nextStep == JourneyStep.done
                ? JourneyTripSource.manual
                : JourneyTripSource.onboarding,
            busy: busy,
            message: _manualFallback
                ? 'Rekaman GPS tidak memenuhi syarat kirim. Pilih titik penangkapan dan masukkan waktu sebenarnya secara manual. Rekaman asli tetap tersimpan di perangkat.'
                : _sessionCleanupError ?? message,
            onBack: widget.onBack,
            onChooseLocation: () => _chooseLocation(),
            onRetryPending: () {
              if (!_isCurrentAccount()) return;
              final draft = state.pendingDraft;
              if (draft != null) cubit.submitTrip(draft.trip);
            },
            onSubmit: (input) {
              if (!_isCurrentAccount()) return;
              if (state.failure?.code ==
                  JourneyFailureCode.authenticationRequired) {
                widget.onSignIn?.call();
                return;
              }
              if (input.source == JourneyTripSource.sailing) {
                _pendingSailingAckId = input.clientTripId;
              } else if (_sailingBloc?.state.session?.clientTripId ==
                  input.clientTripId) {
                _pendingSailingAckId = input.clientTripId;
              }
              cubit.submitTrip(input);
            },
          );
        },
      ),
    );
  }
}

String _validationMessage(JourneyFailure failure) {
  final details = failure.details;
  final code = details is Map ? details['backendCode'] : null;
  return switch (code) {
    'OUT_OF_PILOT' =>
      'Lokasi berada di luar area layanan. Perbaiki lokasi perjalanan.',
    'INVALID_TIME_RANGE' =>
      'Periksa tanggal, jam berangkat, dan jam pulang perjalanan.',
    _ => 'Periksa kembali data perjalananmu.',
  };
}

class _IncompleteSailingSessionScreen extends StatelessWidget {
  const _IncompleteSailingSessionScreen({
    required this.onRecordManually,
    required this.onLater,
  });

  final VoidCallback onRecordManually;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: ReefishColors.canvas,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.route_outlined, size: 42),
                const SizedBox(height: 18),
                const Text(
                  'Rekaman perjalanan belum lengkap',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Perlu titik penangkapan yang kamu konfirmasi dan sedikitnya dua posisi GPS. Kamu dapat mencatat perjalanan secara manual dengan memilih titik nyata dan mengisi waktu sebenarnya. Rekaman GPS asli tetap tersimpan di perangkat.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    height: 1.45,
                    color: ReefishColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: onRecordManually,
                  child: const Text('Catat perjalanan manual'),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: onLater, child: const Text('Nanti')),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _UnavailableJourneyRepository implements JourneyRepository {
  const _UnavailableJourneyRepository();
  Never _fail() => throw const JourneyFailure(
    code: JourneyFailureCode.authenticationRequired,
    message: 'Masuk untuk melanjutkan perjalanan.',
  );
  @override
  Future<JourneyProfile> getMe() async => _fail();
  @override
  Future<JourneyBoat> createBoat(JourneyBoatInput input) async => _fail();
  @override
  Future<JourneyTripSubmission> submitTrip(JourneyTripInput input) async =>
      _fail();
  @override
  Future<JourneyTripHistory> listTrips({
    int page = 1,
    int limit = 20,
    String? from,
    String? to,
    JourneyTripSource? source,
    String sort = '-departed_at',
  }) async => _fail();
  @override
  Future<JourneyTripDetail> getTripDetail(
    String id, {
    String track = 'simplified',
  }) async => _fail();
  @override
  Future<JourneyDashboard> loadDashboard({int tripLimit = 5}) async => _fail();
}
