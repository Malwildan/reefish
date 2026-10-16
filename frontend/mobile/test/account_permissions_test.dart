import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/account/account_permission_preferences.dart';
import 'package:reefish_mobile/src/account/permissions_screen.dart';

void main() {
  testWidgets(
    'location opt-in starts off and persists only after OS permission is granted',
    (tester) async {
      final preferences = _MemoryPermissionPreferences();
      final location = _FakeLocationPermission(
        granted: false,
        requestResult: true,
      );
      var completedValue = false;

      await tester.pumpWidget(
        MaterialApp(
          home: PermissionsScreen(
            ownerId: 'account-a',
            preferences: preferences,
            locationPermission: location,
            onCompleted: (value) => completedValue = value,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Izin dan privasi'), findsOneWidget);
      expect(
        find.text('Berbagi ringkasan wilayah belum tersedia.'),
        findsOneWidget,
      );
      final locationSwitch = tester.widget<Switch>(find.byType(Switch).last);
      expect(locationSwitch.value, isFalse);

      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
      expect(location.requestCalls, 1);
      expect(await preferences.trackingAllowed('account-a'), isFalse);
      expect(await preferences.trackingAllowed('account-b'), isFalse);

      await tester.tap(find.text('Simpan perubahan'));
      await tester.pumpAndSettle();
      expect(await preferences.trackingAllowed('account-a'), isTrue);
      expect(completedValue, isTrue);
    },
  );

  testWidgets('denied OS permission leaves location opt-in disabled', (
    tester,
  ) async {
    final preferences = _MemoryPermissionPreferences();
    await tester.pumpWidget(
      MaterialApp(
        home: PermissionsScreen(
          ownerId: 'account-a',
          preferences: preferences,
          locationPermission: _FakeLocationPermission(
            granted: false,
            requestResult: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Lokasi saat mulai melaut'));
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(await preferences.trackingAllowed('account-a'), isFalse);
    expect(find.textContaining('Izin lokasi belum diberikan'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch).last).value, isFalse);
  });

  testWidgets(
    'settings reload after preference read failure and reports write failure',
    (tester) async {
      final preferences = _MemoryPermissionPreferences(
        failFirstRead: true,
        failWrites: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PermissionsScreen(
            ownerId: 'account-a',
            preferences: preferences,
            locationPermission: _FakeLocationPermission(
              granted: true,
              requestResult: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pengaturan belum dapat dimuat.'), findsOneWidget);
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(find.text('Izin dan privasi'), findsOneWidget);

      await tester.ensureVisible(find.text('Lokasi saat mulai melaut'));
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan perubahan'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(
        find.text('Pengaturan belum tersimpan. Coba lagi.'),
        findsOneWidget,
      );
      expect(await preferences.trackingAllowed('account-a'), isFalse);
    },
  );

  testWidgets(
    'onboarding consent variant stores local acceptance before continuing',
    (tester) async {
      var completed = false;
      final preferences = _MemoryPermissionPreferences();
      await tester.pumpWidget(
        MaterialApp(
          home: PermissionsScreen(
            ownerId: 'account-a',
            variant: PermissionsScreenVariant.onboardingConsent,
            preferences: preferences,
            locationPermission: _FakeLocationPermission(
              granted: false,
              requestResult: false,
            ),
            onCompleted: (_) => completed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Izin dan persetujuan'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -1100));
      await tester.pumpAndSettle();
      expect(
        find.text('Saya menyetujui Syarat dan Ketentuan yang berlaku.'),
        findsOneWidget,
      );
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox)).onChanged,
        isNotNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Selanjutnya'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(await preferences.termsAccepted('account-a'), isFalse);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Selanjutnya'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Selanjutnya'));
      await tester.pumpAndSettle();
      expect(await preferences.termsAccepted('account-a'), isTrue);
      expect(completed, isTrue);
    },
  );
}

class _MemoryPermissionPreferences implements AccountPermissionPreferences {
  _MemoryPermissionPreferences({
    this.failFirstRead = false,
    this.failWrites = false,
  });
  final Map<String, bool> _values = {};
  final bool failFirstRead;
  final bool failWrites;
  int _readCount = 0;
  @override
  Future<bool> trackingAllowed(String ownerId) async {
    _readCount++;
    if (failFirstRead && _readCount == 1) throw StateError('read failed');
    return _values[ownerId] ?? false;
  }

  @override
  Future<void> setTrackingAllowed(String ownerId, bool allowed) async {
    if (failWrites) throw StateError('write failed');
    _values[ownerId] = allowed;
  }

  @override
  Future<bool> termsAccepted(String ownerId) async =>
      _termsValues[ownerId] ?? false;

  @override
  Future<void> setTermsAccepted(String ownerId, bool accepted) async {
    if (failWrites) throw StateError('write failed');
    _termsValues[ownerId] = accepted;
  }

  final Map<String, bool> _termsValues = {};
}

class _FakeLocationPermission implements LocationPermissionAdapter {
  _FakeLocationPermission({required this.granted, required this.requestResult});
  final bool granted;
  final bool requestResult;
  int requestCalls = 0;
  @override
  Future<bool> isGranted() async => granted;
  @override
  Future<bool> request() async {
    requestCalls++;
    return requestResult;
  }
}
