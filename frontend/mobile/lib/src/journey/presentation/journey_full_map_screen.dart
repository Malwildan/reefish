import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../map/data/asset_marine_repository.dart';
import '../../map/data/supabase_grid_policy_repository.dart';
import '../../map/data/supabase_marine_repository.dart';
import '../../map/data/unconfigured_grid_policy_repository.dart';
import '../../map/domain/geo_point.dart';
import '../../map/domain/grid_cell.dart';
import '../../map/domain/grid_policy.dart';
import '../../map/domain/grid_policy_failure.dart';
import '../../map/domain/grid_policy_repository.dart';
import '../../map/domain/marine_cell_lookup.dart';
import '../../map/domain/marine_data.dart';
import '../../map/domain/marine_repository.dart';
import '../../map/domain/metric_grid_500.dart';
import '../../map/presentation/marine_map_cubit.dart';
import '../../map/presentation/widgets/marine_cell_detail_sheet.dart';
import '../../map/presentation/widgets/marine_cell_summary_popup.dart';
import '../../theme/reef_fish_theme.dart';
import '../domain/journey_insights.dart';
import '../domain/journey_models.dart';
import 'journey_weather_widgets.dart';
import 'widgets/journey_dashboard_map.dart';
import 'widgets/reef_bottom_navigation.dart';

/// Full-screen read-only OSM map with the canonical 500 m grid overlay.
class JourneyFullMapScreen extends StatefulWidget {
  const JourneyFullMapScreen({
    this.homePort,
    this.center,
    this.plannedPoint,
    this.insights,
    this.onBack,
    this.map,
    this.marineRepository,
    this.gridPolicyRepository,
    this.mapBuilder,
    this.onGridTap,
    super.key,
  });

  final JourneyLatLng? homePort;
  final JourneyLatLng? center;
  final JourneyLatLng? plannedPoint;
  final JourneyInsights? insights;
  final VoidCallback? onBack;
  final Widget? map;
  final MarineRepository? marineRepository;
  final GridPolicyRepository? gridPolicyRepository;
  final Widget Function(ValueChanged<GeoPoint> onGridTap)? mapBuilder;
  final ValueChanged<GridCell>? onGridTap;

  @override
  State<JourneyFullMapScreen> createState() => _JourneyFullMapScreenState();
}

class _JourneyFullMapScreenState extends State<JourneyFullMapScreen> {
  final MetricGrid500 _grid = MetricGrid500();
  late final MarineMapCubit _marine;
  late final GridPolicyRepository _policies;
  GridPolicySnapshot? _policy;
  GridPolicyFailure? _policyFailure;
  bool _policyLoading = true;
  bool _policyRefreshInFlight = false;
  GridCell? _activeCell;
  MarineDataset? _preparedDataset;
  MarineCellLookup? _cellLookup;

  @override
  void initState() {
    super.initState();
    _marine = MarineMapCubit(
      repository: widget.marineRepository ?? _defaultMarineRepository(),
    )..initialize();
    _policies = widget.gridPolicyRepository ?? _defaultGridPolicyRepository();
    _loadPolicy();
  }

  MarineRepository _defaultMarineRepository() {
    try {
      return SupabaseMarineRepository(client: Supabase.instance.client);
    } catch (_) {
      return AssetMarineRepository();
    }
  }

  GridPolicyRepository _defaultGridPolicyRepository() {
    try {
      return SupabaseGridPolicyRepository(client: Supabase.instance.client);
    } catch (_) {
      return const UnconfiguredGridPolicyRepository();
    }
  }

  Future<void> _loadPolicy() async {
    if (_policyRefreshInFlight) return;
    _policyRefreshInFlight = true;
    if (mounted) {
      setState(() {
        _policyLoading = true;
        _policyFailure = null;
      });
    }
    try {
      final policy = await _policies.fetchSnapshot();
      if (!mounted) return;
      setState(() {
        _policy = policy;
        _policyFailure = null;
        _policyLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _policy = null;
        _policyFailure = error is GridPolicyFailure
            ? error
            : const GridPolicyFailure(GridPolicyFailureCode.unavailable);
        _policyLoading = false;
      });
    } finally {
      _policyRefreshInFlight = false;
    }
  }

  void _inspectPoint(GeoPoint point) {
    if (!_grid.initialBounds.contains(point)) {
      setState(() => _activeCell = null);
      return;
    }
    final cell = _grid.resolve(point);
    setState(() => _activeCell = cell);
    final policy = _policy;
    if (!_policyLoading &&
        (_policyFailure != null ||
            (policy != null && !policy.isFreshAt(DateTime.now())))) {
      _loadPolicy();
    }
    widget.onGridTap?.call(cell);
  }

  void _prepareDataset(MarineDataset dataset) {
    if (identical(_preparedDataset, dataset)) return;
    _preparedDataset = dataset;
    _cellLookup = MarineCellLookup(dataset);
  }

  void _closePopup() => setState(() => _activeCell = null);

  GridAccess _accessFor(GridCell cell) =>
      _policy?.accessFor(cell.id, DateTime.now()) ?? GridAccess.unknown;

  String _policyStatus(GridCell cell) {
    final access = _accessFor(cell);
    if (_policyFailure != null) return _policyFailure!.userMessage;
    if (_policyLoading) return 'Memverifikasi status petak…';
    if (access == GridAccess.locked) {
      return 'Terkunci untuk menangkap ikan: ${_policy?.locks[cell.id]?.reason ?? 'Alasan belum dicantumkan'}.';
    }
    if (access == GridAccess.unlocked) {
      return 'Tidak ada lock pada snapshot aktif. Status ini bukan penilaian keselamatan atau izin menangkap ikan.';
    }
    return 'Status lock belum terverifikasi.';
  }

  Future<void> _openDetails(GridCell cell, MarineDataset dataset) =>
      showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: 400,
            height: math.min(MediaQuery.sizeOf(dialogContext).height * .8, 680),
            child: MarineCellDetailSheet(
              gridCell: cell,
              cell: dataset.cells[cell.id],
              coralFeatures: _cellLookup!.featuresFor(cell).coral,
              mangroveFeatures: _cellLookup!.featuresFor(cell).mangrove,
              loadChlorophyllEntries: () => _marine.loadCellChlorophyll(
                cell.id,
                maxEntry: _marine.state.chlorophyllEntryCount,
              ),
              initialChlorophyllEntry: _marine.state.chlorophyllEntry,
              chlorophyllEntryCount: _marine.state.chlorophyllEntryCount,
              chlorophyllPeriods: dataset.chlorophyllPeriods,
              backendData:
                  dataset.origin == MarineDataOrigin.authenticatedBackend,
              policyStatus: _policyStatus(cell),
              popup: true,
              onClose: () => Navigator.of(dialogContext).pop(),
            ),
          ),
        ),
      );

  @override
  void dispose() {
    _marine.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: ReefishColors.canvas,
    body: SafeArea(
      child: Column(
        children: [
          SizedBox(
            height: 64,
            child: Row(
              children: [
                const SizedBox(width: 28),
                _BackButton(onPressed: widget.onBack),
                const SizedBox(width: 12),
                const Text(
                  'Peta Laut',
                  style: TextStyle(
                    color: ReefishColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.map ??
                    widget.mapBuilder?.call(_inspectPoint) ??
                    JourneyDashboardMap(
                      homePort: widget.homePort,
                      center: widget.center,
                      plannedPoint: widget.plannedPoint,
                      rounded: false,
                      onGridTap: _inspectPoint,
                    ),
                if (_activeCell case final cell?)
                  Positioned.fill(
                    child: BlocBuilder<MarineMapCubit, MarineMapState>(
                      bloc: _marine,
                      builder: (context, marine) =>
                          _buildCellPopup(cell, marine),
                    ),
                  ),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 18,
                  child: _MapWeatherFooter(insights: widget.insights),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildCellPopup(GridCell cell, MarineMapState marine) {
    final size = MediaQuery.sizeOf(context);
    final width = math.min(320.0, size.width - 24).toDouble();
    final height = math.min(320.0, size.height - 150).toDouble();
    final dataset = marine.dataset;
    if (dataset != null) _prepareDataset(dataset);
    final child = dataset == null
        ? _LoadingCellPopup(
            error: marine.error,
            onRetry: _marine.retryBase,
            onClose: _closePopup,
          )
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 5, 14, 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    dataset.origin == MarineDataOrigin.authenticatedBackend
                        ? 'API · periode ${dataset.period ?? 'tidak tersedia'} · waktu pengamatan tidak diketahui'
                        : 'Paket offline · waktu data tidak diketahui',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ReefishColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: MarineCellSummaryPopup(
                  key: ValueKey(cell.id),
                  gridCell: cell,
                  cell: dataset.cells[cell.id],
                  coralCount: _cellLookup!.featuresFor(cell).coral.length,
                  mangroveCount: _cellLookup!.featuresFor(cell).mangrove.length,
                  loadChlorophyllEntries: () =>
                      _marine.loadCellChlorophyllEntry(
                        cell.id,
                        _marine.state.chlorophyllEntry,
                      ),
                  initialChlorophyllEntry: _marine.state.chlorophyllEntry,
                  chlorophyllPeriodLabel: _selectedChlorophyllPeriod(marine),
                  access: _accessFor(cell),
                  policyStatus: _policyStatus(cell),
                  onClose: _closePopup,
                  onDetails: () => _openDetails(cell, dataset),
                ),
              ),
            ],
          );
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Material(
          color: Colors.white,
          elevation: 10,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    );
  }

  String? _selectedChlorophyllPeriod(MarineMapState state) {
    final dataset = state.dataset;
    if (dataset?.origin != MarineDataOrigin.authenticatedBackend ||
        dataset!.chlorophyllPeriods.length < state.chlorophyllEntry) {
      return null;
    }
    return dataset.chlorophyllPeriods[state.chlorophyllEntry - 1];
  }
}

class _LoadingCellPopup extends StatelessWidget {
  const _LoadingCellPopup({
    required this.error,
    required this.onRetry,
    required this.onClose,
  });

  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: IconButton(
          key: const Key('marine-summary-close'),
          tooltip: 'Tutup ringkasan petak',
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ),
      Expanded(
        child: Center(
          child: error == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Data parameter belum tersedia.'),
                    TextButton(
                      onPressed: onRetry,
                      child: const Text('Coba lagi'),
                    ),
                  ],
                ),
        ),
      ),
    ],
  );
}

/// Full recommendation detail page. The point and all metrics come from the
/// recommendation response; missing values are never inferred from the map.
class JourneyRecommendationDetailScreen extends StatelessWidget {
  const JourneyRecommendationDetailScreen({
    required this.recommendation,
    this.insights,
    this.homePort,
    this.onBack,
    this.onStartJourney,
    this.onProfile,
    this.map,
    this.now,
    super.key,
  });

  final JourneyRecommendation recommendation;
  final JourneyInsights? insights;
  final JourneyLatLng? homePort;
  final VoidCallback? onBack;
  final VoidCallback? onStartJourney;
  final VoidCallback? onProfile;
  final Widget? map;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    DateTime currentTime() => now?.call() ?? DateTime.now();
    final usable = insights?.recommendationsUsableAt(currentTime()) ?? false;
    final catchValue = _recommendationCatch(recommendation);
    final viewport = MediaQuery.sizeOf(context);
    final mapHeight = math.min(
      210.0,
      math.min(viewport.width * .55, viewport.height * .25),
    );
    return Scaffold(
      backgroundColor: ReefishColors.canvas,
      bottomNavigationBar: ReefBottomNavigation(
        active: ReefTab.home,
        onHome: onBack ?? () => Navigator.of(context).maybePop(),
        onProfile: onProfile,
        onSail: onStartJourney == null
            ? null
            : () {
                if (insights?.recommendationsUsableAt(currentTime()) ?? false) {
                  onStartJourney!();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Rekomendasi kedaluwarsa. Muat rekomendasi terbaru.',
                      ),
                    ),
                  );
                }
              },
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              height: 80,
              child: Row(
                children: [
                  const SizedBox(width: 24),
                  _BackButton(onPressed: onBack),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Detail rekomendasi',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ReefishColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 2, 24, 16),
                children: [
                  Text(
                    _recommendationType(recommendation.type),
                    style: const TextStyle(
                      color: ReefishColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _recommendationCoordinates(recommendation.point),
                    style: const TextStyle(
                      color: ReefishColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  if (!usable)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Rekomendasi kedaluwarsa atau waktu berlakunya belum tersedia.',
                        style: TextStyle(
                          color: ReefishColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: mapHeight,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          map ??
                              JourneyDashboardMap(
                                homePort: homePort,
                                center: recommendation.point,
                                plannedPoint: recommendation.point,
                              ),
                          Positioned(
                            right: 12,
                            top: 12,
                            child: Material(
                              color: ReefishColors.textPrimary,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => Navigator.of(context).push<void>(
                                  MaterialPageRoute<void>(
                                    builder: (_) => JourneyFullMapScreen(
                                      homePort: homePort,
                                      center: recommendation.point,
                                      plannedPoint: recommendation.point,
                                      insights: insights,
                                    ),
                                  ),
                                ),
                                child: const SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Center(
                                    child: Icon(
                                      Icons.open_in_full,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _NoticeCard(
                    title: 'Area direkomendasikan',
                    body: 'Periksa lokasi dan batas area sebelum berangkat.',
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          label: 'Potensi tangkapan',
                          value: catchValue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          label: 'Estimasi BBM',
                          value: _formatNumber(
                            recommendation.predictedFuelLiters,
                            'L',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Rekomendasi adalah perkiraan. Cek cuaca dan batas area sebelum melaut.',
                    style: TextStyle(
                      color: ReefishColors.textSecondary,
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const SizedBox(height: 4),
                  Text(
                    insights?.isFallback == true
                        ? 'Sumber: estimasi heuristik'
                        : 'Sumber: layanan rekomendasi',
                    style: const TextStyle(
                      color: ReefishColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  if (recommendation.reason != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      recommendation.reason!,
                      style: const TextStyle(
                        color: ReefishColors.textPrimary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                  _DetailRow(
                    label: 'Waktu berangkat',
                    value: recommendation.departureTime ?? '—',
                  ),
                  _DetailRow(
                    label: 'Waktu kembali',
                    value: recommendation.returnTime ?? '—',
                  ),
                  if (insights?.generatedAt != null)
                    _DetailRow(
                      label: 'Dibuat',
                      value: _dateTime(insights!.generatedAt),
                    ),
                  if (insights?.validUntil != null)
                    _DetailRow(
                      label: 'Berlaku hingga: ',
                      value: _dateTime(insights!.validUntil),
                    ),
                  if (recommendation.confidence != null)
                    _DetailRow(
                      label: 'Keyakinan model',
                      value:
                          '${(recommendation.confidence! * 100).toStringAsFixed(0)}%',
                    ),
                  _DetailRow(
                    label: 'Jarak dari pelabuhan',
                    value: _formatNumber(
                      recommendation.distanceFromPortKm,
                      'km',
                    ),
                  ),
                  if (recommendation.weatherSummary case final weather?) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Cuaca pada rekomendasi',
                      style: TextStyle(
                        color: ReefishColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    _DetailRow(
                      label: 'Angin',
                      value: _formatNumber(weather.windSpeedMs, 'm/dtk'),
                    ),
                    _DetailRow(
                      label: 'Gelombang',
                      value: _formatNumber(weather.waveHeightM, 'm'),
                    ),
                    _DetailRow(label: 'Risiko', value: weather.risk ?? '—'),
                  ],
                  if (insights?.weatherFetchedAt != null)
                    _DetailRow(
                      label: 'Cuaca pelabuhan dimuat',
                      value: _dateTime(insights!.weatherFetchedAt),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 33),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: !usable || onStartJourney == null
                      ? null
                      : () {
                          if (!(insights?.recommendationsUsableAt(
                                currentTime(),
                              ) ??
                              false)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Rekomendasi kedaluwarsa. Muat rekomendasi terbaru.',
                                ),
                              ),
                            );
                            return;
                          }
                          onStartJourney!();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ReefishColors.primaryAction,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(usable ? 'Mulai Perjalanan' : 'Tidak berlaku'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapWeatherFooter extends StatelessWidget {
  const _MapWeatherFooter({required this.insights});

  final JourneyInsights? insights;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: ReefishColors.canvas.withValues(alpha: .94),
          borderRadius: BorderRadius.circular(40),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: JourneyWeatherStrip(weather: insights?.weather),
        ),
      ),
      const SizedBox(height: 4),
      DecoratedBox(
        decoration: BoxDecoration(
          color: ReefishColors.canvas.withValues(alpha: .92),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: JourneyWeatherAttribution(insights: insights, compact: true),
        ),
      ),
    ],
  );
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Kembali',
    button: true,
    child: Material(
      color: const Color(0xFFD8896A),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed ?? () => Navigator.of(context).maybePop(),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Center(
            child: SvgPicture.asset(
              'assets/icons/login-AkarIconsArrowLeft-b559ec96-131a-4c84-b0d4-8c5f220aab8d.svg',
              width: 22,
              height: 22,
            ),
          ),
        ),
      ),
    ),
  );
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 80),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: ReefishColors.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: ReefishColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: const TextStyle(
            color: ReefishColors.textPrimary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 76),
    padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: ReefishColors.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: ReefishColors.textSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: ReefishColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: ReefishColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: ReefishColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

String _recommendationType(String type) => switch (type) {
  'fuel_saving' => 'Efisiensi BBM',
  'catch_max' => 'Peningkatan Tangkapan',
  'balanced' => 'Seimbang',
  'habitual' => 'Kebiasaan Anda',
  _ => 'Rekomendasi',
};

String _recommendationCatch(JourneyRecommendation recommendation) {
  final range = recommendation.catchRangeKg;
  if (range != null) return '${range[0]}–${range[1]} kg';
  return _formatNumber(recommendation.predictedCatchKg, 'kg');
}

String _recommendationCoordinates(JourneyLatLng? point) {
  if (point == null) return 'Lokasi belum tersedia';
  final latHemisphere = point.lat < 0 ? 'S' : 'N';
  final lngHemisphere = point.lng < 0 ? 'W' : 'E';
  return '${point.lat.abs().toStringAsFixed(4)}° $latHemisphere, ${point.lng.abs().toStringAsFixed(4)}° $lngHemisphere';
}

String _formatNumber(double? value, String suffix) {
  if (value == null) return '—';
  final shown = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$shown $suffix';
}

String _dateTime(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
