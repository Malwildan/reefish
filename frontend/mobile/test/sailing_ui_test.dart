import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/sailing/application/sailing_bloc.dart';
import 'package:reefish_mobile/src/sailing/domain/sailing_location_source.dart';
import 'package:reefish_mobile/src/sailing/domain/sailing_session.dart';
import 'package:reefish_mobile/src/sailing/domain/sailing_session_store.dart';
import 'package:reefish_mobile/src/sailing/presentation/journey_mode_screen.dart';
import 'package:reefish_mobile/src/sailing/presentation/sailing_session_screen.dart';
import 'package:reefish_mobile/src/theme/reef_fish_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('JourneyModeScreen', () {
    testWidgets('requires one selection and submits only that mode once', (
      tester,
    ) async {
      await _setViewport(tester, const Size(430, 932));
      final selections = <JourneyMode>[];
      var cancelCount = 0;
      await tester.pumpWidget(
        _app(
          JourneyModeScreen(
            map: const ColoredBox(color: Color(0xFF082029)),
            onContinue: selections.add,
            onCancel: () => cancelCount++,
          ),
        ),
      );

      expect(find.text('Pilih cara mencatat perjalanan'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('journey-mode-sheet'))).height,
        521,
      );
      final submit = tester.widget<FilledButton>(
        find.byKey(const ValueKey('journey-mode-continue')),
      );
      expect(submit.onPressed, isNull);
      expect(find.text('Pilih salah satu mode'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('journey-mode-manual')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('journey-mode-continue')));
      await tester.pump();
      expect(selections, [JourneyMode.manual]);
      expect(cancelCount, 0);
      await tester.tap(find.byKey(const ValueKey('journey-mode-back')));
      expect(cancelCount, 1);
    });

    testWidgets('fits 360 logical pixels with 1.3 text scale', (tester) async {
      await _setViewport(tester, const Size(360, 800));
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(1.3),
          ),
          child: _app(
            JourneyModeScreen(
              map: const ColoredBox(color: Color(0xFF082029)),
              onContinue: (_) {},
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('journey-mode-continue')),
      );
      expect(find.text('Tanpa pemantauan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('SailingSessionScreen', () {
    testWidgets('idle rejection keeps panel text readable on the canvas', (
      tester,
    ) async {
      await _setViewport(tester, const Size(430, 932));
      final store = _MemoryStore();
      store.session = SailingSession(
        ownerId: 'owner-1',
        clientTripId: 'existing-trip',
        phase: SailingPhase.atDeparture,
        departure: const SailingPoint(lat: -8.4, lng: 112.6),
        startedAt: DateTime.utc(2026),
        track: const [],
        locationStatus: SailingLocationStatus.paused,
      );

      final bloc = SailingBloc(
        store: store,
        locationSource: _GrantedLocationSource(),
      );
      await bloc.startSailing(
        ownerId: 'owner-1',
        departure: const SailingPoint(lat: -8.4, lng: 112.6),
      );

      await tester.pumpWidget(
        _app(
          SailingSessionScreen(
            bloc: bloc,
            mapBuilder: (_) => const ColoredBox(color: Color(0xFF082029)),
            onMarkFishing: () async {},
            onResumeTracking: bloc.resumeTracking,
            onCompleted: (_) {},
            onBack: () {},
          ),
        ),
      );
      await tester.pump();

      expect(bloc.state.phase, SailingPhaseView.idle);
      expect(find.text('Perjalanan belum dimulai'), findsOneWidget);
      expect(
        find.text('Mulai perjalanan dari titik keberangkatan.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('sailing-error')), findsOneWidget);
      for (final text in [
        find.text('Perjalanan belum dimulai'),
        find.text('Mulai perjalanan dari titik keberangkatan.'),
      ]) {
        final widget = tester.widget<Text>(text);
        expect(widget.style?.color, ReefishColors.textPrimary);
      }
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('sailing-error')))
            .style
            ?.color,
        const Color(0xFF8E352B),
      );
      await bloc.close();
    });

    testWidgets('shows explicit phase actions and delivers completion once', (
      tester,
    ) async {
      await _setViewport(tester, const Size(430, 932));
      final bloc = _newBloc();
      final completed = <SailingSession>[];
      await bloc.startSailing(
        ownerId: 'owner-1',
        departure: const SailingPoint(lat: -8.4, lng: 112.6),
      );

      await tester.pumpWidget(
        _app(
          SailingSessionScreen(
            bloc: bloc,
            mapBuilder: (_) => const ColoredBox(color: Color(0xFF082029)),
            onMarkFishing: () async => bloc.markFishing(
              actualPoint: const SailingPoint(lat: -8.5, lng: 112.7),
            ),
            onResumeTracking: bloc.resumeTracking,
            onCompleted: completed.add,
            onBack: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Kamu Masih di Daratan!'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sailing-primary-action')));
      await tester.pumpAndSettle();
      expect(bloc.state.phase, SailingPhaseView.transit);
      expect(find.text('Menuju Titik Penangkapan'), findsOneWidget);
      expect(find.textContaining('Sistem otomatis mendeteksi'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('sailing-primary-action')));
      await tester.pumpAndSettle();
      expect(bloc.state.phase, SailingPhaseView.fishing);
      expect(find.text('Sedang Menangkap Ikan'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sailing-primary-action')));
      await tester.pumpAndSettle();
      expect(bloc.state.phase, SailingPhaseView.completed);
      expect(completed, hasLength(1));
      await tester.pump();
      expect(completed, hasLength(1));
      await bloc.close();
    });

    testWidgets('stop confirmation cancel keeps the session active', (
      tester,
    ) async {
      await _setViewport(tester, const Size(430, 932));
      final bloc = _newBloc();
      var completedCount = 0;
      await bloc.startSailing(
        ownerId: 'owner-1',
        departure: const SailingPoint(lat: -8.4, lng: 112.6),
      );

      await tester.pumpWidget(
        _app(
          SailingSessionScreen(
            bloc: bloc,
            mapBuilder: (_) => const ColoredBox(color: Color(0xFF082029)),
            onMarkFishing: () async {},
            onResumeTracking: bloc.resumeTracking,
            onCompleted: (_) => completedCount++,
            onBack: () {},
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('sailing-stop')));
      await tester.pumpAndSettle();
      expect(find.text('Apakah Kamu Yakin Ingin Berhenti?'), findsOneWidget);
      expect(find.textContaining('Waktu berjalan'), findsOneWidget);
      expect(find.textContaining('Sisa Waktu'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('sailing-stop-continue')));
      await tester.pumpAndSettle();
      expect(bloc.state.phase, SailingPhaseView.atDeparture);
      expect(completedCount, 0);
      await bloc.close();
    });
  });
}

Widget _app(Widget child) =>
    MaterialApp(theme: ReefishTheme.light, home: child);

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

SailingBloc _newBloc() => SailingBloc(
  store: _MemoryStore(),
  locationSource: _GrantedLocationSource(),
);

class _MemoryStore implements SailingSessionStore {
  SailingSession? session;

  @override
  Future<SailingSession?> read() async => session;

  @override
  Future<void> save(SailingSession value) async => session = value;

  @override
  Future<void> clear({required String clientTripId}) async {
    if (session?.clientTripId == clientTripId) session = null;
  }
}

class _GrantedLocationSource implements SailingLocationSource {
  @override
  Future<SailingPermission> requestForegroundPermission() async =>
      SailingPermission.granted;

  @override
  Stream<SailingPosition> get positions => const Stream.empty();
}
