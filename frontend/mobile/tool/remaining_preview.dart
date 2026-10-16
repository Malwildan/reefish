// QA-only local browser fixture for the remaining Reefish mobile screens.
// Synthetic fixture content and controlled GPS are never sent to production.
// Run with: flutter run -d web-server -t tool/remaining_preview.dart --web-port 4197
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'package:reefish_mobile/src/account/account_permission_preferences.dart';
import 'package:reefish_mobile/src/account/permissions_screen.dart';
import 'package:reefish_mobile/src/account/profile_screen.dart';
import 'package:reefish_mobile/src/account/trip_detail_screen.dart';
import 'package:reefish_mobile/src/app/departure_entry.dart';
import 'package:reefish_mobile/src/app/journey_entry.dart';
import 'package:reefish_mobile/src/journey/domain/journey_insights.dart';
import 'package:reefish_mobile/src/journey/domain/journey_models.dart';
import 'package:reefish_mobile/src/journey/domain/journey_repository.dart';
import 'package:reefish_mobile/src/journey/presentation/create_journey_screen.dart';
import 'package:reefish_mobile/src/journey/presentation/journey_full_map_screen.dart';
import 'package:reefish_mobile/src/journey/presentation/widgets/journey_dashboard_map.dart';
import 'package:reefish_mobile/src/map/domain/departure_repository.dart';
import 'package:reefish_mobile/src/map/domain/fishing_point_repository.dart';
import 'package:reefish_mobile/src/map/domain/geo_point.dart';
import 'package:reefish_mobile/src/map/domain/grid_policy.dart';
import 'package:reefish_mobile/src/map/domain/grid_policy_repository.dart';
import 'package:reefish_mobile/src/sailing/application/sailing_bloc.dart';
import 'package:reefish_mobile/src/sailing/domain/sailing_location_source.dart';
import 'package:reefish_mobile/src/sailing/domain/sailing_session.dart';
import 'package:reefish_mobile/src/sailing/domain/sailing_session_store.dart';
import 'package:reefish_mobile/src/sailing/presentation/journey_mode_screen.dart';
import 'package:reefish_mobile/src/sailing/presentation/sailing_session_screen.dart';
import 'package:reefish_mobile/src/theme/reef_fish_theme.dart';

const _ownerId = 'qa-fixture-user';
const _home = JourneyLatLng(lat: -8.447, lng: 112.683);
const _departure = SailingPoint(lat: -8.447, lng: 112.683);
final _fakeNow = DateTime.utc(2026, 10, 16, 9, 0);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RemainingPreviewApp());
}

/// Browser-only fixture host. Everything under the app-sized repaint boundary
/// is production UI. The controls on the right are QA-only and excluded from
/// the saved 1:1 screenshot.
class RemainingPreviewApp extends StatefulWidget {
  const RemainingPreviewApp({super.key});

  @override
  State<RemainingPreviewApp> createState() => _RemainingPreviewAppState();
}

class _RemainingPreviewAppState extends State<RemainingPreviewApp> {
  final _captureKey = GlobalKey();
  final _repository = _FixtureJourneyRepository();
  final _draftStore = _MemoryDraftStore();
  final _preferences = _FixturePermissionPreferences();
  final _location = _ControlledLocationSource();
  final _sessionStore = _MemorySessionStore();
  final _selection = FishingPointSelection(
    point: const GeoPoint(latitude: -8.42, longitude: 112.70),
    cellId: '49S-UTM-QA-001',
    departure: DeparturePoint(
      point: const GeoPoint(latitude: -8.447, longitude: 112.683),
      cellId: '49S-UTM-QA-PORT',
      savedAt: _fakeNow,
    ),
    savedAt: _fakeNow,
  );
  late final JourneyInsights _insights = JourneyInsights(
    generatedAt: DateTime.now().toUtc(),
    validUntil: DateTime.now().toUtc().add(const Duration(hours: 1)),
    recommendations: const [
      JourneyRecommendation(
        id: '00000000-0000-4000-8000-000000000151',
        type: 'fuel_saving',
        point: JourneyLatLng(lat: -8.42, lng: 112.70),
        predictedFuelLiters: 15,
        predictedCatchKg: 12,
        catchRangeKg: [10, 14],
        reason:
            'Synthetic QA fixture near the Java pilot area; not a live prediction.',
      ),
      JourneyRecommendation(
        id: '00000000-0000-4000-8000-000000000152',
        type: 'catch_max',
        point: JourneyLatLng(lat: -8.42, lng: 112.70),
        predictedFuelLiters: 18,
        predictedCatchKg: 16,
        catchRangeKg: [14, 18],
        reason:
            'Synthetic QA fixture near the Java pilot area; not a live prediction.',
      ),
    ],
    recommendationMessage: 'Synthetic QA fixture only.',
    weatherMessage: 'Synthetic QA fixture only.',
  );

  Widget? _screen;
  SailingBloc? _sailingBloc;
  int _width = 430;
  int _height = 932;
  String _status = 'QA fixture active — synthetic data; no production writes.';
  String _captureLabel = 'dashboard';
  bool _fakeAck = false;
  bool _startingFakeSailing = false;

  @override
  void initState() {
    super.initState();
    final query = Uri.base.queryParameters;
    _width = int.tryParse(query['width'] ?? '') ?? 430;
    _height = int.tryParse(query['height'] ?? '') ?? 932;
    _showDashboard();
    ServicesBinding.instance.keyboard.addHandler(_onKey);
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !HardwareKeyboard.instance.isControlPressed) {
      return false;
    }
    switch (event.logicalKey.keyLabel.toLowerCase()) {
      case '1':
        _showMode(null);
        return true;
      case '2':
        _showMode(JourneyMode.tracked);
        return true;
      case '3':
        _showMode(JourneyMode.manual);
        return true;
      case 'p':
        _showProfile();
        return true;
      case 's':
        _showSettings();
        return true;
      case 'f':
        _showFullMap();
        return true;
      case 'r':
        _showRecommendation(0);
        return true;
    }
    return false;
  }

  @override
  void dispose() {
    ServicesBinding.instance.keyboard.removeHandler(_onKey);
    _sailingBloc?.close();
    _location.close();
    super.dispose();
  }

  void _setScreen(Widget screen) => setState(() => _screen = screen);

  void _showDashboard() {
    _captureLabel = 'dashboard';
    _setScreen(
      JourneyEntry(
        repository: _repository,
        draftStore: _draftStore,
        selection: _selection,
        initialView: JourneyEntryView.dashboard,
        gridPolicyRepository: _FreshFixtureGridPolicy(),
        sailingLocationSource: _location,
        sailingSessionStore: _sessionStore,
      ),
    );
  }

  void _showMode(JourneyMode? initial) {
    _captureLabel = switch (initial) {
      null => 'mode-unselected',
      JourneyMode.tracked => 'mode-tracked',
      JourneyMode.manual => 'mode-manual',
    };
    _setScreen(
      JourneyModeScreen(
        initialMode: initial,
        map: const JourneyDashboardMap(homePort: _home, rounded: false),
        onCancel: _showDashboard,
        onContinue: (mode) {
          if (mode == JourneyMode.manual) {
            _setScreen(_manualForm());
          } else {
            _startFakeSailing();
          }
        },
      ),
    );
  }

  Widget _manualForm() {
    _captureLabel = 'manual-summary';
    return CreateJourneyScreen(
      selection: _selection,
      source: JourneyTripSource.manual,
      onBack: _showDashboard,
      onChooseLocation: () => _setScreen(
        DepartureEntry(
          gridPolicyRepository: _FreshFixtureGridPolicy(),
          departureRepository: _MemoryDepartureRepository(),
          fishingPointRepository: _MemoryFishingPointRepository(),
          onBack: () => _showMode(JourneyMode.manual),
          onFishingPointSaved: (selection) => _setScreen(
            CreateJourneyScreen(
              selection: selection,
              source: JourneyTripSource.manual,
              onBack: _showDashboard,
              onChooseLocation: () => _showMode(JourneyMode.manual),
              onSubmit: _submitFakeTrip,
            ),
          ),
        ),
      ),
      onSubmit: _submitFakeTrip,
    );
  }

  void _showProfile() {
    _captureLabel = 'profile';
    _setScreen(
      ProfileScreen(
        repository: _repository,
        onHome: _showDashboard,
        onStartJourney: () => _showMode(null),
        onPermissions: _showSettings,
        onSignOut: () async {
          _setStatus(
            'Synthetic QA logout only; no production session changed.',
          );
          _showDashboard();
        },
      ),
    );
  }

  void _showSettings() {
    _captureLabel = 'settings';
    _setScreen(
      PermissionsScreen(
        ownerId: _ownerId,
        preferences: _preferences,
        locationPermission: const _GrantedFixtureLocationPermission(),
        onBack: _showProfile,
        onHome: _showDashboard,
        onStartJourney: () => _showMode(null),
        onCompleted: (_) => _showProfile(),
      ),
    );
  }

  void _showConsent(bool approved) {
    _captureLabel = approved ? 'permission-approved' : 'permission-consent';
    _preferences.termsAcceptedLocally = approved;
    _setScreen(
      PermissionsScreen(
        ownerId: _ownerId,
        variant: PermissionsScreenVariant.onboardingConsent,
        preferences: _preferences,
        locationPermission: const _GrantedFixtureLocationPermission(),
        onBack: _showDashboard,
        onCompleted: (_) => _showDashboard(),
      ),
    );
  }

  void _showTripDetail() {
    _captureLabel = 'trip-detail';
    _setScreen(
      TripDetailScreen(
        repository: _repository,
        tripId: 'QA-TRIP-001',
        onStartJourney: () => _showMode(null),
      ),
    );
  }

  void _showFullMap() {
    _captureLabel = 'full-map';
    _setScreen(
      JourneyFullMapScreen(
        homePort: _home,
        insights: _insights,
        onBack: _showDashboard,
      ),
    );
  }

  void _showRecommendation(int index) {
    _captureLabel = index == 0 ? 'recommendation-area' : 'recommendation-catch';
    _setScreen(
      JourneyRecommendationDetailScreen(
        recommendation: _insights.recommendations[index],
        insights: _insights,
        homePort: _home,
        onBack: _showDashboard,
        onStartJourney: () => _showMode(null),
        onProfile: _showProfile,
      ),
    );
  }

  Future<void> _startFakeSailing() async {
    if (_startingFakeSailing) return;
    _startingFakeSailing = true;
    try {
      await _sailingBloc?.close();
      // This store belongs only to the synthetic QA fixture. A new QA run
      // starts cleanly without touching any production session store.
      _sessionStore.value = null;
      _preferences.tracking = true;
      final bloc = SailingBloc(
        store: _sessionStore,
        locationSource: _location,
        now: DateTime.now,
      );
      _sailingBloc = bloc;
      await bloc.startSailing(ownerId: _ownerId, departure: _departure);
      _captureLabel = 'session-departure';
      _setStatus('Tracked session uses explicitly emitted synthetic QA GPS.');
      _showSailing();
    } finally {
      _startingFakeSailing = false;
    }
  }

  void _showSailing() {
    final bloc = _sailingBloc;
    if (bloc == null) return;
    _captureLabel = bloc.state.locationStatus == SailingLocationStatus.paused
        ? 'session-paused'
        : switch (bloc.state.phase) {
            SailingPhaseView.atDeparture => 'session-departure',
            SailingPhaseView.transit => 'session-transit',
            SailingPhaseView.fishing => 'session-fishing',
            SailingPhaseView.completed => 'session-completed',
            SailingPhaseView.idle => 'session-idle',
          };
    _setScreen(
      SailingSessionScreen(
        bloc: bloc,
        mapBuilder: (session) {
          final last = session?.track.isNotEmpty == true
              ? session!.track.last.point
              : null;
          return JourneyDashboardMap(
            homePort: _home,
            center: last ?? session?.departure,
            departure: session?.departure,
            currentPosition:
                bloc.state.locationStatus == SailingLocationStatus.available &&
                    session?.track.isNotEmpty == true &&
                    DateTime.now()
                            .toUtc()
                            .difference(session!.track.last.recordedAt)
                            .abs() <=
                        const Duration(minutes: 2)
                ? last
                : null,
            followPosition: true,
            fishingPoint: session?.actualFishingPoint,
            track:
                session?.track
                    .map(
                      (p) => JourneyLatLng(lat: p.point.lat, lng: p.point.lng),
                    )
                    .toList(growable: false) ??
                const [],
            rounded: false,
          );
        },
        onMarkFishing: () async {
          final track =
              bloc.state.session?.track ?? const <SailingTrackPoint>[];
          final last = track.isNotEmpty
              ? track.last.point
              : const SailingPoint(lat: -8.43, lng: 112.69);
          await bloc.markFishing(actualPoint: last);
          _setStatus('QA-only fishing point explicitly confirmed in fixture.');
        },
        onResumeTracking: () => bloc.resumeTracking(),
        onCompleted: _onSailingCompleted,
        onBack: () {
          bloc.pauseTracking();
          _showDashboard();
        },
      ),
    );
  }

  void _onSailingCompleted(SailingSession session) {
    _setStatus('Session completed in memory. No backend call was made.');
    try {
      session.toTripInput(fuelLiters: 4, catchKg: 12);
      _setScreen(
        CreateJourneyScreen(
          selection: _selection,
          source: JourneyTripSource.sailing,
          recordedSession: session,
          onBack: _showSailing,
          onChooseLocation: () {},
          onSubmit: _submitFakeTrip,
        ),
      );
    } catch (_) {
      _showSailing();
      _setStatus(
        'Completed session retained. Add two explicit synthetic GPS samples and confirm a fishing point before creating the sailing payload.',
      );
    }
  }

  void _submitFakeTrip(JourneyTripInput trip) {
    _repository.submitTrip(trip);
    setState(() {
      _fakeAck = true;
      _status =
          'FAKE ACK only: in-memory fixture repository accepted this trip; no production network write.';
    });
    _showTripDetail();
  }

  void _setStatus(String value) => setState(() => _status = value);

  Future<void> _emitFakeSample() async {
    final n = _location.sampleCount + 1;
    _location.emit(
      SailingPosition(
        point: SailingPoint(lat: -8.447 + n * .0003, lng: 112.683 + n * .0004),
        recordedAt: DateTime.now().toUtc().add(Duration(milliseconds: n)),
        accuracyM: 5,
        speedMs: 2.2,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    _setStatus('Emitted synthetic QA GPS sample $n at a controlled point.');
  }

  Future<void> _capture() async {
    final boundary =
        _captureKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      _setStatus('Capture unavailable: app-sized repaint boundary not ready.');
      return;
    }
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) {
      _setStatus('Capture unavailable: Flutter did not encode PNG bytes.');
      return;
    }
    final name = 'remaining-$_captureLabel-${_width}x$_height.png';
    try {
      final response = await http
          .post(
            Uri.base
                .resolve('/qa-capture')
                .replace(queryParameters: {'name': name}),
            headers: {'Content-Type': 'image/png'},
            body: data.buffer.asUint8List(),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw StateError('Capture server unavailable');
      }
      _setStatus(
        'Saved exact $_width×$_height production-widget screenshot: $name',
      );
    } catch (_) {
      _setStatus('Capture not saved. Run qa/remaining/serve.py and retry.');
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ReefishTheme.light,
    home: _screen ?? const Center(child: CircularProgressIndicator()),
    builder: (context, navigator) => Scaffold(
      backgroundColor: const Color(0xFFDFE5E3),
      body: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RepaintBoundary(
              key: _captureKey,
              child: SizedBox(
                width: _width.toDouble(),
                height: _height.toDouble(),
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: Size(_width.toDouble(), _height.toDouble()),
                    padding: const EdgeInsets.only(top: 50, bottom: 34),
                    viewPadding: const EdgeInsets.only(top: 50, bottom: 34),
                  ),
                  child: navigator!,
                ),
              ),
            ),
            SizedBox(
              width: 330,
              height: _height.toDouble(),
              child: _controls(),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _controls() => Material(
    color: Colors.white,
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'QA FIXTURES',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'App view: $_width × $_height CSS px. Panel is outside captured viewport.',
          ),
          const SizedBox(height: 12),
          Text(_status, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _capture,
            child: const Text('Simpan capture QA PNG'),
          ),
          const Divider(),
          _button('Dashboard / live OSM', _showDashboard),
          _button('Mode — unselected', () => _showMode(null)),
          _button('Mode — tracked', () => _showMode(JourneyMode.tracked)),
          _button('Mode — manual', () => _showMode(JourneyMode.manual)),
          _button('Permissions — consent unchecked', () => _showConsent(false)),
          _button(
            'Permissions — local consent checked',
            () => _showConsent(true),
          ),
          _button('Manual trip + picker', () => _setScreen(_manualForm())),
          _button('Profile', _showProfile),
          _button('Trip detail', _showTripDetail),
          _button('Settings and permissions', _showSettings),
          _button('Full map', _showFullMap),
          _button('Recommendation — area', () => _showRecommendation(0)),
          _button('Recommendation — catch', () => _showRecommendation(1)),
          const Divider(),
          _button('Start tracked QA session', _startFakeSailing),
          _button('Emit controlled synthetic GPS sample', _emitFakeSample),
          _button('Confirm departure', () async {
            await _sailingBloc?.markDeparted();
            _showSailing();
          }),
          _button('Explicitly confirm fishing point', () async {
            final bloc = _sailingBloc;
            if (bloc == null) return;
            await bloc.markFishing(
              actualPoint: const SailingPoint(lat: -8.43, lng: 112.69),
            );
            _showSailing();
          }),
          _button('Set capture label: stop-confirmation', () {
            _captureLabel = 'stop-confirmation';
            _setStatus(
              'Capture filename now labels the visible stop-confirmation overlay.',
            );
          }),
          _button('Recovery fixture (pause + resume)', () async {
            await _sailingBloc?.pauseTracking();
            _setStatus(
              'Paused persisted session; choose Aktifkan lokasi in app to resume with controlled source.',
            );
            _showSailing();
          }),
          if (_fakeAck)
            const Text(
              'Last fake ACK: in-memory only; no external writes.',
              style: TextStyle(color: Colors.green),
            ),
          const Divider(),
          const Text(
            'Fixture data and GPS samples are synthetic and visibly labeled. Tiles use live OSM. No production auth bypass or production write path is configured.',
          ),
        ],
      ),
    ),
  );

  Widget _button(String label, VoidCallback onPressed) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: OutlinedButton(onPressed: onPressed, child: Text(label)),
  );
}

class _FixtureJourneyRepository implements JourneyRepository {
  final List<JourneyTripInput> submitted = [];
  final _tripTime = DateTime.utc(2026, 10, 15, 2);
  JourneyProfile get _profile => const JourneyProfile(
    id: _ownerId,
    name: 'QA fixture — Nelayan',
    phone: '+62 812 0000 0000',
    role: 'nelayan',
    onboarded: true,
    nextStep: JourneyStep.done,
    boat: JourneyBoat(
      id: 'QA-BOAT',
      name: 'Perahu fixture',
      engineHp: 15,
      boatLengthM: 7,
      fuelType: 'solar',
      homePort: _home,
      isDefault: true,
    ),
    stats: JourneyStats(
      tripCount: 1,
      baselineFuelLiters: 4,
      baselineCatchKg: 12,
    ),
  );
  JourneyTripDetail get _detail => JourneyTripDetail(
    id: 'QA-TRIP-001',
    source: 'manual',
    departedAt: _tripTime,
    returnedAt: _tripTime.add(const Duration(hours: 5)),
    durationHours: 5,
    fuelLiters: 4,
    catchKg: 12,
    departure: _home,
    returnPoint: const JourneyLatLng(lat: -8.446, lng: 112.684),
    notes: 'Synthetic QA fixture. No live catch or route claim.',
  );
  JourneyTripSummary get _summary => JourneyTripSummary(
    id: 'QA-TRIP-001',
    source: 'manual',
    departedAt: _tripTime,
    returnedAt: _tripTime.add(const Duration(hours: 5)),
    durationHours: 5,
    fuelLiters: 4,
    catchKg: 12,
    fishingPointCount: 1,
    boatName: 'Perahu fixture',
  );
  JourneyDashboard get _dashboard => JourneyDashboard(
    profile: _profile,
    history: JourneyTripHistory(
      trips: [_summary, _summary, _summary],
      page: 1,
      limit: 5,
      total: 3 + submitted.length,
      tripCount: 3 + submitted.length,
      totalCatchKg: 12,
      totalFuelLiters: 4,
      averageCatchPerLiter: 3,
    ),
  );

  @override
  Future<JourneyProfile> getMe() async => _profile;
  @override
  Future<JourneyBoat> createBoat(JourneyBoatInput input) async =>
      _profile.boat!;
  @override
  Future<JourneyTripSubmission> submitTrip(JourneyTripInput input) async {
    submitted.add(input);
    return JourneyTripSubmission(trip: _detail, onboarded: true, replay: false);
  }

  @override
  Future<JourneyTripHistory> listTrips({
    int page = 1,
    int limit = 20,
    String? from,
    String? to,
    JourneyTripSource? source,
    String sort = '-departed_at',
  }) async => _dashboard.history;
  @override
  Future<JourneyTripDetail> getTripDetail(
    String id, {
    String track = 'simplified',
  }) async => _detail;
  @override
  Future<JourneyDashboard> loadDashboard({int tripLimit = 5}) async =>
      _dashboard;
}

class _MemoryDraftStore implements JourneyDraftStore {
  JourneyDraft? value;
  @override
  Future<void> save(JourneyDraft draft) async => value = draft;
  @override
  Future<JourneyDraft?> read() async => value;
  @override
  Future<void> delete() async => value = null;
}

class _MemorySessionStore implements SailingSessionStore {
  SailingSession? value;
  @override
  Future<SailingSession?> read() async => value;
  @override
  Future<void> save(SailingSession session) async => value = session;
  @override
  Future<void> clear({required String clientTripId}) async {
    if (value?.clientTripId == clientTripId) value = null;
  }
}

class _ControlledLocationSource implements SailingLocationSource {
  final _controller = StreamController<SailingPosition>.broadcast();
  int sampleCount = 0;
  @override
  Future<SailingPermission> requestForegroundPermission() async =>
      SailingPermission.granted;
  @override
  Stream<SailingPosition> get positions => _controller.stream;
  void emit(SailingPosition position) {
    sampleCount++;
    _controller.add(position);
  }

  Future<void> close() => _controller.close();
}

class _FreshFixtureGridPolicy implements GridPolicyRepository {
  @override
  Future<GridPolicySnapshot> fetchSnapshot() async {
    final now = DateTime.now().toUtc();
    return GridPolicySnapshot(
      version: 'qa-fixture-fresh',
      fetchedAt: now.subtract(const Duration(seconds: 1)),
      expiresAt: now.add(const Duration(minutes: 10)),
      locks: const {},
    );
  }
}

class _FixturePermissionPreferences implements AccountPermissionPreferences {
  bool tracking = false;
  bool termsAcceptedLocally = false;
  @override
  Future<bool> trackingAllowed(String ownerId) async => tracking;
  @override
  Future<void> setTrackingAllowed(String ownerId, bool allowed) async =>
      tracking = allowed;
  @override
  Future<bool> termsAccepted(String ownerId) async => termsAcceptedLocally;
  @override
  Future<void> setTermsAccepted(String ownerId, bool accepted) async =>
      termsAcceptedLocally = accepted;
}

class _GrantedFixtureLocationPermission implements LocationPermissionAdapter {
  const _GrantedFixtureLocationPermission();
  @override
  Future<bool> isGranted() async => true;
  @override
  Future<bool> request() async => true;
}

class _MemoryDepartureRepository implements DepartureRepository {
  DeparturePoint? value;
  @override
  Future<void> save(DeparturePoint departure) async => value = departure;
  @override
  Future<DeparturePoint?> read() async => value;
}

class _MemoryFishingPointRepository implements FishingPointRepository {
  FishingPointSelection? value;
  @override
  Future<void> save(FishingPointSelection selection) async => value = selection;
  @override
  Future<FishingPointSelection?> read() async => value;
}
