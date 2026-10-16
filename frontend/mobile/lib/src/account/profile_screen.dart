import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../journey/domain/journey_models.dart';
import '../journey/domain/journey_repository.dart';
import '../journey/presentation/widgets/reef_bottom_navigation.dart';
import '../theme/reef_fish_theme.dart';
import 'trip_detail_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    required this.repository,
    required this.onHome,
    required this.onStartJourney,
    this.onPermissions,
    this.onSignOut,
    super.key,
  });

  final JourneyRepository repository;
  final VoidCallback onHome;
  final VoidCallback onStartJourney;
  final VoidCallback? onPermissions;
  final Future<void> Function()? onSignOut;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _pageSize = 10;
  JourneyProfile? _profile;
  final List<JourneyTripSummary> _trips = [];
  int? _total;
  int _page = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _signingOut = false;
  String? _error;
  String? _signOutError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _trips.clear();
      _page = 0;
      _total = null;
    });
    try {
      final profile = await widget.repository.getMe();
      final history = await widget.repository.listTrips(
        page: 1,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _trips.addAll(history.trips);
        _total = history.total;
        _page = 1;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Profil dan riwayat belum dapat dimuat.';
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final history = await widget.repository.listTrips(
        page: nextPage,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _trips.addAll(history.trips);
        _total = history.total ?? _total;
        _page = nextPage;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Riwayat berikutnya belum dapat dimuat. Coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  bool get _hasMore =>
      _total != null ? _trips.length < _total! : _trips.length >= _pageSize;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final inset = math.min(24.0, math.max(16.0, (width - 382) / 2));
    return Scaffold(
      backgroundColor: ReefishColors.canvas,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _profile == null
            ? _fullError()
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(inset, 20, inset, 130),
                  children: [
                    const Text(
                      'Profil',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Informasi Akun',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _accountCard(_profile),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Riwayat Penangkapan',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${_total ?? _trips.length} perjalanan',
                          style: const TextStyle(
                            color: ReefishColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_trips.isEmpty)
                      _emptyHistory()
                    else
                      for (final trip in _trips) ...[
                        _tripCard(context, trip),
                        const SizedBox(height: 14),
                      ],
                    if (_error != null) _inlineError(),
                    if (_hasMore)
                      OutlinedButton(
                        onPressed: _loadingMore ? null : _loadMore,
                        child: _loadingMore
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Muat riwayat lainnya'),
                      ),
                    if (widget.onPermissions != null) ...[
                      const SizedBox(height: 16),
                      Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: widget.onPermissions,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: ReefishColors.border),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Pengaturan dan izin',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  color: ReefishColors.textSecondary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _logoutButton(),
                  ],
                ),
              ),
      ),
      bottomNavigationBar: ReefBottomNavigation(
        onHome: widget.onHome,
        onSail: widget.onStartJourney,
      ),
    );
  }

  Widget _fullError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Profil dan riwayat belum dapat dimuat.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('Coba lagi')),
        ],
      ),
    ),
  );

  Widget _accountCard(JourneyProfile? profile) => Container(
    padding: const EdgeInsets.fromLTRB(15, 14, 15, 13),
    decoration: BoxDecoration(
      color: const Color(0xFFDCEDE9),
      border: Border.all(color: ReefishColors.textSecondary),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Nomor HP',
          style: TextStyle(color: ReefishColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Text(
          profile?.phone?.isNotEmpty == true
              ? profile!.phone!
              : 'Nomor telepon tidak tersedia',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  Widget _emptyHistory() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: ReefishColors.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Text('Belum ada perjalanan yang tercatat.'),
  );

  Widget _tripCard(BuildContext context, JourneyTripSummary trip) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => TripDetailScreen(
            repository: widget.repository,
            tripId: trip.id,
            onStartJourney: widget.onStartJourney,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
        decoration: BoxDecoration(
          border: Border.all(color: ReefishColors.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    trip.departedAt == null
                        ? 'Tanggal tidak tersedia'
                        : _dateLabel(trip.departedAt!),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                Text(
                  trip.catchKg == null
                      ? '— kg'
                      : '${_number(trip.catchKg!)} kg',
                  style: const TextStyle(
                    color: ReefishColors.primaryAction,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_locationLabel(trip), style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 5),
            Text(
              '${_timeLabel(trip.departedAt)}–${_timeLabel(trip.returnedAt)} · ${_sourceLabel(trip.source)}',
              style: const TextStyle(
                color: ReefishColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _inlineError() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      children: [
        Text(
          _error!,
          style: const TextStyle(color: ReefishColors.signupAccent),
        ),
        TextButton(onPressed: _loadMore, child: const Text('Coba lagi')),
      ],
    ),
  );

  Widget _logoutButton() => OutlinedButton.icon(
    onPressed: widget.onSignOut == null || _signingOut ? null : _signOut,
    icon: _signingOut
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.logout),
    label: Text(_signOutError ?? 'Keluar'),
    style: OutlinedButton.styleFrom(
      foregroundColor: ReefishColors.signupAccent,
      side: const BorderSide(color: Color(0xFFE7836A), width: 1.5),
      backgroundColor: const Color(0xFFFFF0ED),
      minimumSize: const Size.fromHeight(46),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      shape: const StadiumBorder(),
    ),
  );

  Future<void> _signOut() async {
    setState(() {
      _signingOut = true;
      _signOutError = null;
    });
    try {
      await widget.onSignOut?.call();
    } catch (_) {
      if (mounted) {
        setState(() => _signOutError = 'Belum dapat logout. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }
}

String _sourceLabel(String? source) => switch (source) {
  'manual' => 'Tanpa pemantauan',
  'sailing' => 'Pantau langsung',
  'onboarding' => 'Pencatatan awal',
  _ => 'Mode tidak tersedia',
};

String _locationLabel(JourneyTripSummary trip) =>
    'Lokasi tidak tersedia di ringkasan';

String _dateLabel(DateTime date) {
  const months = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];
  final local = date.toUtc().add(const Duration(hours: 7));
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

String _timeLabel(DateTime? date) {
  if (date == null) return '—';
  final local = date.toUtc().add(const Duration(hours: 7));
  return '${local.hour.toString().padLeft(2, '0')}.${local.minute.toString().padLeft(2, '0')}';
}

String _number(double value) => value.toStringAsFixed(1).replaceAll('.', ',');
