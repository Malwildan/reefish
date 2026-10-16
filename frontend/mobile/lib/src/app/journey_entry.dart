import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
import '../journey/presentation/widgets/journey_dashboard_map.dart';
import '../map/data/local_fishing_point_repository.dart';
import '../map/domain/fishing_point_repository.dart';
import '../map/domain/grid_policy_repository.dart';
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

  @override
  State<JourneyEntry> createState() => _JourneyEntryState();
}

class _JourneyEntryState extends State<JourneyEntry> {
  JourneyCubit? _cubit;
  FishingPointSelection? _selection;
  JourneyLatLng? _homePort;
  JourneyInsights? _insights;
  JourneyTripInput? _editableTrip;
  bool _insightsLoading = false;
  String? _setupError;
  GoJourneyInsightsRepository? _insightsRepository;

  @override
  void initState() {
    super.initState();
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
      final cubit = JourneyCubit(
        repository:
            widget.repository ??
            (client == null
                ? const _UnavailableJourneyRepository()
                : SupabaseJourneyRepository(client: client)),
        draftStore:
            widget.draftStore ??
            SharedPreferencesJourneyDraftStore(
              preferences: preferences,
              ownerId: owner,
            ),
      );
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
      if (widget.initialView == JourneyEntryView.form &&
          cubit.state.phase == JourneyPhase.dashboard) {
        await cubit.beginTrip();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _setupError = 'Penyimpanan perjalanan belum dapat dibuka.',
        );
      }
    }
  }

  @override
  void dispose() {
    _cubit?.close();
    _insightsRepository?.close();
    super.dispose();
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.profile?.name ?? 'Akun Reefish',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (state.profile?.phone case final phone?) Text(phone),
                const SizedBox(height: 20),
                const Text(
                  'Riwayat Perjalanan',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                if (state.dashboard?.history.trips.isEmpty ?? true)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Belum ada riwayat yang dapat ditampilkan.'),
                  ),
                for (final trip
                    in state.dashboard?.history.trips ?? <JourneyTripSummary>[])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      trip.departedAt == null
                          ? 'Perjalanan'
                          : _dateLabel(trip.departedAt!),
                    ),
                    subtitle: Text(
                      '${trip.catchKg?.toStringAsFixed(1) ?? '—'} kg · ${trip.fuelLiters?.toStringAsFixed(1) ?? '—'} L',
                    ),
                  ),
                if (widget.onSignOut != null)
                  OutlinedButton(
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      try {
                        await widget.onSignOut!();
                      } catch (_) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Belum dapat keluar. Coba lagi.'),
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('Keluar'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showFullMap(JourneyState state) {
    Navigator.of(context).push<void>(
      reefishPageRoute(
        Scaffold(
          appBar: AppBar(
            title: const Text('Peta Laut'),
            backgroundColor: ReefishColors.canvas,
          ),
          body: JourneyDashboardMap(homePort: state.profile?.boat?.homePort),
        ),
      ),
    );
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
            current.phase == JourneyPhase.dashboard &&
            previous.phase != current.phase,
        listener: (context, state) => _loadInsights(state),
        builder: (context, state) {
          final busy =
              state.phase == JourneyPhase.loading ||
              state.phase == JourneyPhase.submittingTrip;
          final message = _message(state);
          final dashboardView =
              state.phase == JourneyPhase.dashboard ||
              state.tripSubmitted ||
              (widget.initialView == JourneyEntryView.dashboard &&
                  state.profile?.nextStep != JourneyStep.boat &&
                  state.profile?.nextStep != JourneyStep.firstTrip) ||
              (widget.initialView == JourneyEntryView.automatic &&
                  state.phase == JourneyPhase.error &&
                  state.pendingDraft == null);
          if (dashboardView) {
            return JourneyDashboardScreen(
              dashboard: state.dashboard,
              insights: _insights,
              loading: busy || _insightsLoading,
              message: message,
              onRefresh: () async {
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
                      setState(() {
                        _editableTrip = null;
                        _selection = null;
                      });
                      cubit.beginTrip();
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
            key: ValueKey(state.pendingDraft?.trip.clientTripId ?? 'new-trip'),
            selection: _selection,
            pendingTrip: state.pendingDraft?.trip,
            initialTrip: _editableTrip,
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
            source: state.profile?.nextStep == JourneyStep.done
                ? JourneyTripSource.manual
                : JourneyTripSource.onboarding,
            busy: busy,
            message: message,
            onBack: widget.onBack,
            onChooseLocation: () => _chooseLocation(),
            onRetryPending: () {
              final draft = state.pendingDraft;
              if (draft != null) cubit.submitTrip(draft.trip);
            },
            onSubmit: (input) {
              if (state.failure?.code ==
                  JourneyFailureCode.authenticationRequired) {
                widget.onSignIn?.call();
                return;
              }
              cubit.submitTrip(input);
            },
          );
        },
      ),
    );
  }
}

String _dateLabel(DateTime at) {
  final wib = at.toUtc().add(const Duration(hours: 7));
  return '${wib.day.toString().padLeft(2, '0')}/${wib.month.toString().padLeft(2, '0')}/${wib.year}';
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
