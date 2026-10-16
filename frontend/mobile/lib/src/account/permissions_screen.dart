import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/reef_fish_theme.dart';
import 'account_permission_preferences.dart';
import '../journey/presentation/widgets/reef_bottom_navigation.dart';

enum PermissionsScreenVariant { settings, onboardingConsent }

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({
    required this.ownerId,
    this.variant = PermissionsScreenVariant.settings,
    this.onBack,
    this.onCompleted,
    this.preferences,
    this.locationPermission,
    this.onHome,
    this.onStartJourney,
    super.key,
  });

  final String ownerId;
  final PermissionsScreenVariant variant;
  final VoidCallback? onBack;
  final ValueChanged<bool>? onCompleted;
  final AccountPermissionPreferences? preferences;
  final LocationPermissionAdapter? locationPermission;
  final VoidCallback? onHome;
  final VoidCallback? onStartJourney;

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool? _trackingAllowed;
  bool _termsAccepted = false;
  bool _saving = false;
  String? _message;

  late Future<
    ({
      AccountPermissionPreferences preferences,
      LocationPermissionAdapter location,
      bool termsAccepted,
    })
  >
  _services;

  @override
  void initState() {
    super.initState();
    _services = _loadServices();
  }

  Future<
    ({
      AccountPermissionPreferences preferences,
      LocationPermissionAdapter location,
      bool termsAccepted,
    })
  >
  _loadServices() async {
    final injectedPreferences = widget.preferences;
    final preferences =
        injectedPreferences ??
        SharedPreferencesAccountPermissionPreferences(
          preferences: await SharedPreferences.getInstance(),
        );
    final allowed = await preferences.trackingAllowed(widget.ownerId);
    final termsAccepted = await preferences.termsAccepted(widget.ownerId);
    if (mounted) {
      setState(() {
        _trackingAllowed = allowed;
        _termsAccepted = termsAccepted;
      });
    }
    return (
      preferences: preferences,
      location:
          widget.locationPermission ?? const _GeolocatorPermissionAdapter(),
      termsAccepted: termsAccepted,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: ReefishColors.canvas,
    bottomNavigationBar: widget.variant == PermissionsScreenVariant.settings
        ? ReefBottomNavigation(
            onHome: widget.onHome,
            onProfile: widget.onBack,
            onSail: widget.onStartJourney,
          )
        : null,
    body: SafeArea(
      bottom: widget.variant != PermissionsScreenVariant.settings,
      child: FutureBuilder(
        future: _services,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _loadError();
          }
          if (!snapshot.hasData || _trackingAllowed == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return _content(
            snapshot.data!.preferences,
            snapshot.data!.location,
            snapshot.data!.termsAccepted,
          );
        },
      ),
    ),
  );

  Widget _loadError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Pengaturan belum dapat dimuat.'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => setState(() {
              _trackingAllowed = null;
              _termsAccepted = false;
              _message = null;
              _services = _loadServices();
            }),
            child: const Text('Coba lagi'),
          ),
        ],
      ),
    ),
  );

  Widget _content(
    AccountPermissionPreferences preferences,
    LocationPermissionAdapter location,
    bool termsAccepted,
  ) => widget.variant == PermissionsScreenVariant.settings
      ? _settingsContent(preferences, location, termsAccepted)
      : _consentContent(preferences, location);

  Widget _settingsContent(
    AccountPermissionPreferences preferences,
    LocationPermissionAdapter location,
    bool termsAccepted,
  ) => Column(
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Kembali',
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                  onPressed: widget.onBack,
                  icon: SvgPicture.asset(
                    'assets/icons/login-AkarIconsArrowLeft-b559ec96-131a-4c84-b0d4-8c5f220aab8d.svg',
                    width: 38,
                    height: 38,
                  ),
                ),
                const SizedBox(width: 2),
                const Text(
                  'Pengaturan',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 26),
            const Text(
              'Izin dan privasi',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Atur bagaimana data perjalanan dan lokasi digunakan.',
              style: TextStyle(color: ReefishColors.textSecondary),
            ),
            const SizedBox(height: 26),
            const _SettingCard(
              title: 'Ringkasan data per wilayah',
              subtitle: 'Berbagi data perjalanan dalam bentuk ringkasan.',
              value: false,
              enabled: false,
              onChanged: null,
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 7, 8, 8),
              child: Text(
                'Berbagi ringkasan wilayah belum tersedia.',
                style: TextStyle(
                  color: ReefishColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            _SettingCard(
              title: 'Lokasi saat mulai melaut',
              subtitle: 'Catat lokasi ketika perjalanan dimulai.',
              value: _trackingAllowed!,
              enabled: !_saving,
              onChanged: (value) => _requestTrackingAllowed(value, location),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(0, 14, 0, 28),
              child: Text(
                'Perjalanan tetap bisa dicatat tanpa pelacakan lokasi langsung.',
                style: TextStyle(
                  color: ReefishColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            _SettingInfoCard(
              title: 'Persetujuan wajib',
              subtitle: termsAccepted
                  ? 'Persetujuan dicatat di perangkat ini.'
                  : 'Belum disetujui di perangkat ini.',
            ),
            if (_message case final message?) ...[
              const SizedBox(height: 12),
              Text(
                message,
                style: const TextStyle(color: ReefishColors.signupAccent),
              ),
            ],
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 33),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _saving || _trackingAllowed == null
                ? null
                : () => _save(preferences),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Simpan perubahan'),
          ),
        ),
      ),
    ],
  );

  Widget _consentContent(
    AccountPermissionPreferences preferences,
    LocationPermissionAdapter location,
  ) => Column(
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton.filledTonal(
                tooltip: 'Kembali',
                onPressed: widget.onBack,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFD8896A),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.arrow_back),
              ),
            ),
            const SizedBox(height: 36),
            Align(
              alignment: Alignment.centerLeft,
              child: SvgPicture.asset(
                'assets/icons/login-ReefishMarkColorAtoll-fc2ecd40-eb81-448f-a0b0-ab29c7974c23.svg',
                width: 56,
                height: 42,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Izin dan persetujuan',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 34),
            const _ConsentSettingCard(
              title:
                  'Bagikan data perjalanan saya dalam ringkasan berdasarkan wilayah',
              value: false,
              enabled: false,
              onChanged: null,
            ),
            const SizedBox(height: 20),
            _ConsentSettingCard(
              title: 'Catat lokasi saya saat memulai perjalanan melaut',
              value: _trackingAllowed!,
              enabled: !_saving,
              onChanged: (value) => _requestTrackingAllowed(value, location),
            ),
            const SizedBox(height: 36),
            const Text(
              'Pilihan ini dapat diubah kapan saja di Pengaturan. Perjalanan tetap bisa dicatat tanpa pelacakan lokasi.',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 42),
            const Divider(),
            const SizedBox(height: 14),
            const Text(
              'PERSETUJUAN WAJIB',
              style: TextStyle(
                color: ReefishColors.textSecondary,
                fontSize: 11,
                letterSpacing: .2,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                  side: const BorderSide(
                    color: ReefishColors.textSecondary,
                    width: 1.5,
                  ),
                  value: _termsAccepted,
                  onChanged: _saving
                      ? null
                      : (value) => _setTermsAccepted(value ?? false),
                ),
                const SizedBox(width: 4),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Saya menyetujui Syarat dan Ketentuan yang berlaku.',
                          style: TextStyle(height: 1.4, fontSize: 13),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Wajib disetujui untuk melanjutkan.',
                          style: TextStyle(
                            color: ReefishColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_message case final message?) ...[
              const SizedBox(height: 12),
              Text(
                message,
                style: const TextStyle(color: ReefishColors.signupAccent),
              ),
            ],
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            style: FilledButton.styleFrom(
              disabledBackgroundColor: const Color(0xFFEEF1EC),
              disabledForegroundColor: ReefishColors.textSecondary,
              side: const BorderSide(color: ReefishColors.border, width: 2),
              textStyle: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            onPressed: _saving || _trackingAllowed == null || !_termsAccepted
                ? null
                : () => _save(preferences),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Selanjutnya'),
          ),
        ),
      ),
    ],
  );

  void _setTermsAccepted(bool accepted) {
    setState(() {
      _termsAccepted = accepted;
      _message = null;
    });
  }

  Future<void> _requestTrackingAllowed(
    bool value,
    LocationPermissionAdapter location,
  ) async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      if (value) {
        final granted = await location.isGranted() || await location.request();
        if (!mounted) return;
        if (!granted) {
          setState(
            () => _message =
                'Izin lokasi belum diberikan. Pengaturan tetap nonaktif.',
          );
          return;
        }
      }
      if (mounted) setState(() => _trackingAllowed = value);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Pengaturan belum tersimpan. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save(AccountPermissionPreferences preferences) async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await preferences.setTrackingAllowed(widget.ownerId, _trackingAllowed!);
      if (widget.variant == PermissionsScreenVariant.onboardingConsent) {
        await preferences.setTermsAccepted(widget.ownerId, _termsAccepted);
      }
      if (mounted) widget.onCompleted?.call(_trackingAllowed!);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Pengaturan belum tersimpan. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _SettingCard extends StatelessWidget {
  const _SettingCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    this.onChanged,
  });
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 96),
    padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: ReefishColors.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 7),
              Text(
                subtitle,
                style: const TextStyle(
                  color: ReefishColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Transform.scale(
          scale: .8,
          child: Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            inactiveTrackColor: const Color(0xFFE8ECE7),
            inactiveThumbColor: Colors.white,
            thumbColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? ReefishColors.brand
                  : Colors.white,
            ),
            trackColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? ReefishColors.brand.withValues(alpha: .25)
                  : const Color(0xFFEDF1EC),
            ),
            trackOutlineColor: const WidgetStatePropertyAll(
              ReefishColors.border,
            ),
          ),
        ),
      ],
    ),
  );
}

class _SettingInfoCard extends StatelessWidget {
  const _SettingInfoCard({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: ReefishColors.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 7),
        Text(
          subtitle,
          style: const TextStyle(
            color: ReefishColors.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

class _ConsentSettingCard extends StatelessWidget {
  const _ConsentSettingCard({
    required this.title,
    required this.value,
    required this.enabled,
    this.onChanged,
  });
  final String title;
  final bool value;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 72),
    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
    decoration: BoxDecoration(
      color: ReefishColors.field,
      border: Border.all(color: ReefishColors.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: ReefishColors.textSecondary,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Transform.scale(
          scale: .8,
          child: Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            thumbColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? ReefishColors.brand
                  : Colors.white,
            ),
            trackColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? ReefishColors.brand.withValues(alpha: .25)
                  : const Color(0xFFEDF1EC),
            ),
            trackOutlineColor: const WidgetStatePropertyAll(
              ReefishColors.border,
            ),
          ),
        ),
      ],
    ),
  );
}

class _GeolocatorPermissionAdapter implements LocationPermissionAdapter {
  const _GeolocatorPermissionAdapter();

  @override
  Future<bool> isGranted() async => _usable(await Geolocator.checkPermission());

  @override
  Future<bool> request() async => _usable(await Geolocator.requestPermission());

  bool _usable(LocationPermission permission) =>
      permission == LocationPermission.whileInUse ||
      permission == LocationPermission.always;
}
