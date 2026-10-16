import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/reef_fish_theme.dart';
import '../data/device_location_service.dart';
import '../data/asset_marine_repository.dart';
import '../data/supabase_marine_repository.dart';
import '../domain/departure_repository.dart';
import '../domain/fishing_point_repository.dart';
import '../domain/geo_point.dart';
import '../domain/grid_cell.dart';
import '../domain/grid_policy.dart';
import '../domain/grid_policy_failure.dart';
import '../domain/grid_policy_repository.dart';
import '../domain/metric_grid_500.dart';
import '../domain/marine_data.dart';
import '../domain/marine_cell_lookup.dart';
import '../domain/marine_repository.dart';
import 'departure_cubit.dart';
import 'marine_map_cubit.dart';
import 'widgets/focus_fish_mark.dart';
import 'widgets/marine_layer_sheet.dart';
import 'widgets/marine_cell_detail_sheet.dart';
import 'widgets/marine_cell_summary_popup.dart';

typedef DepartureMapBuilder =
    Widget Function(BuildContext context, ValueChanged<GeoPoint> onPointPicked);

class DepartureScreen extends StatefulWidget {
  const DepartureScreen({
    required this.gridPolicyRepository,
    required this.departureRepository,
    this.fishingPointRepository,
    this.locationService,
    this.onBack,
    this.onSignIn,
    this.onSaved,
    this.onFishingPointSaved,
    this.mapBuilder,
    this.marineRepository,
    this.tileUrlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    super.key,
  });

  final GridPolicyRepository gridPolicyRepository;
  final DepartureRepository departureRepository;
  final FishingPointRepository? fishingPointRepository;
  final DeviceLocationService? locationService;
  final VoidCallback? onBack;
  final VoidCallback? onSignIn;
  final ValueChanged<DeparturePoint>? onSaved;
  final ValueChanged<FishingPointSelection>? onFishingPointSaved;
  final DepartureMapBuilder? mapBuilder;
  final MarineRepository? marineRepository;
  final String tileUrlTemplate;

  @override
  State<DepartureScreen> createState() => _DepartureScreenState();
}

class _DepartureScreenState extends State<DepartureScreen>
    with WidgetsBindingObserver {
  late final DepartureCubit _cubit;
  DeparturePoint? _lastNotifiedDeparture;
  FishingPointSelection? _lastNotifiedFishing;
  bool _gridPopupVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cubit = DepartureCubit(
      gridPolicyRepository: widget.gridPolicyRepository,
      departureRepository: widget.departureRepository,
      fishingPointRepository: widget.fishingPointRepository,
      locationService:
          widget.locationService ?? const GeolocatorDeviceLocationService(),
    )..initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cubit.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_cubit.state.policyLoading) {
      unawaited(_cubit.refreshPolicy());
    }
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: _cubit,
    child: BlocConsumer<DepartureCubit, DepartureState>(
      listenWhen: (previous, current) =>
          (previous.saved != current.saved && current.saved) ||
          (previous.fishingSaved != current.fishingSaved &&
              current.fishingSaved) ||
          (!current.saved &&
              previous.message != current.message &&
              current.message != null),
      listener: (context, state) {
        if (state.saved) {
          final departure = state.savedDeparture;
          if (departure != null &&
              !identical(departure, _lastNotifiedDeparture)) {
            _lastNotifiedDeparture = departure;
            widget.onSaved?.call(departure);
          }
        }
        if (state.fishingSaved) {
          final selection = state.savedFishingPoint;
          if (selection != null &&
              !identical(selection, _lastNotifiedFishing)) {
            _lastNotifiedFishing = selection;
            widget.onFishingPointSaved?.call(selection);
            if (widget.onFishingPointSaved == null) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(content: Text('Titik penangkapan tersimpan.')),
                );
            }
          }
        } else if (state.message != null &&
            state.message!.contains('belum tersimpan')) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.message!)));
        }
      },
      builder: (context, state) {
        final media = MediaQuery.of(context);
        final maxSheetHeight = math.min(391.0, media.size.height * 0.84);
        final compactHeight = math.min(174.0, media.size.height * 0.34);
        final sheetHeight = _gridPopupVisible
            ? math.min(184.0, media.size.height * 0.30)
            : state.showMap
            ? compactHeight
            : switch (state.step) {
                DepartureFlowStep.departure => maxSheetHeight,
                DepartureFlowStep.confirmation => math.min(
                  268.0,
                  media.size.height * 0.75,
                ),
                DepartureFlowStep.fishing => math.min(
                  state.isError && state.fishingMessage != null ? 390.0 : 350.0,
                  media.size.height * 0.82,
                ),
              };

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            systemNavigationBarColor: ReefishColors.primaryAction,
            systemNavigationBarIconBrightness: Brightness.light,
          ),
          child: Scaffold(
            backgroundColor: const Color(0xFFB7C5C5),
            body: Stack(
              fit: StackFit.expand,
              children: [
                widget.mapBuilder?.call(context, (point) {
                      if (state.step == DepartureFlowStep.fishing) {
                        _cubit.selectFishingPoint(point);
                      } else {
                        _cubit.selectPoint(
                          point,
                          source: DepartureSelectionSource.map,
                        );
                      }
                    }) ??
                    _DepartureMap(
                      marineRepository: widget.marineRepository,
                      tileUrlTemplate: widget.tileUrlTemplate,
                      dimMap: state.step != DepartureFlowStep.confirmation,
                      popupBottomInset: sheetHeight,
                      onPopupVisibilityChanged: (visible) {
                        if (_gridPopupVisible == visible || !mounted) return;
                        setState(() => _gridPopupVisible = visible);
                      },
                      selectedPoint: state.point,
                      fishingPoint: state.step == DepartureFlowStep.fishing
                          ? state.fishingPoint
                          : null,
                      policy: state.policy,
                      policyFailure: state.policyFailure,
                      policyLoading: state.policyLoading,
                      onPointPicked: (point) =>
                          state.step == DepartureFlowStep.fishing
                          ? _cubit.selectFishingPoint(point)
                          : _cubit.selectPoint(
                              point,
                              source: DepartureSelectionSource.map,
                            ),
                    ),
                if (widget.mapBuilder != null &&
                    state.step != DepartureFlowStep.confirmation)
                  const IgnorePointer(
                    child: ColoredBox(color: Color(0x52000000)),
                  ),
                SafeArea(
                  bottom: false,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(25, 19, 24, 0),
                      child: SizedBox(
                        height: 64,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _HeaderButton(
                              semanticLabel: 'Kembali',
                              peachBack: true,
                              child: SvgPicture.asset(
                                'assets/icons/login-AkarIconsArrowLeft-b559ec96-131a-4c84-b0d4-8c5f220aab8d.svg',
                                width: 38,
                                height: 38,
                              ),
                              onPressed: () {
                                if (state.step == DepartureFlowStep.fishing) {
                                  _cubit.backToConfirmation();
                                  return;
                                }
                                if (state.step ==
                                    DepartureFlowStep.confirmation) {
                                  _cubit.editDeparture();
                                  return;
                                }
                                if (widget.onBack != null) {
                                  widget.onBack!();
                                } else {
                                  Navigator.of(context).maybePop();
                                }
                              },
                            ),
                            Row(
                              children: [
                                Image.asset(
                                  'assets/untracked/departure-Image4-760858e9-83a2-4e2b-903b-2e2c8f9def0c.png',
                                  width: 59,
                                  height: 52,
                                  fit: BoxFit.contain,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  bottom: sheetHeight + 6,
                  child: const _Attribution(),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    constraints: BoxConstraints(maxHeight: maxSheetHeight),
                    height: sheetHeight,
                    decoration: const BoxDecoration(
                      color: ReefishColors.primaryAction,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 18,
                          offset: Offset(0, -5),
                        ),
                      ],
                    ),
                    child: _gridPopupVisible
                        ? switch (state.step) {
                            DepartureFlowStep.departure => _DepartureSheet(
                              compact: true,
                              state: state,
                              onCurrentLocation: _cubit.selectCurrentLocation,
                              onShowMap: () => _cubit.setMapVisible(true),
                              // trips need a fishing point too: go there directly, no second confirmation
                              onSave: widget.onFishingPointSaved != null
                                  ? _cubit.saveAndOpenFishingStep
                                  : () => _cubit.save(),
                            ),
                            DepartureFlowStep.confirmation =>
                              _ConfirmationSheet(
                                compact: true,
                                state: state,
                                onEdit: _cubit.editDeparture,
                                onSave: _cubit.saveAndOpenFishingStep,
                                onNext: _cubit.saveAndOpenFishingStep,
                              ),
                            DepartureFlowStep.fishing => _FishingSheet(
                              compact: true,
                              state: state,
                              onSignIn: widget.onSignIn,
                              onBack: _cubit.backToConfirmation,
                              onRefresh: _cubit.refreshPolicy,
                              onComplete: () async {
                                await _cubit.completeFishingSelection();
                              },
                            ),
                          }
                        : state.showMap
                        ? _CompactMapSheet(
                            state: state,
                            onConfirm: () => _cubit.setMapVisible(false),
                          )
                        : switch (state.step) {
                            DepartureFlowStep.departure => _DepartureSheet(
                              state: state,
                              onCurrentLocation: _cubit.selectCurrentLocation,
                              onShowMap: () => _cubit.setMapVisible(true),
                              // trips need a fishing point too: go there directly, no second confirmation
                              onSave: widget.onFishingPointSaved != null
                                  ? _cubit.saveAndOpenFishingStep
                                  : () => _cubit.save(),
                            ),
                            DepartureFlowStep.confirmation =>
                              _ConfirmationSheet(
                                state: state,
                                onEdit: _cubit.editDeparture,
                                onSave: _cubit.saveAndOpenFishingStep,
                                onNext: _cubit.saveAndOpenFishingStep,
                              ),
                            DepartureFlowStep.fishing => _FishingSheet(
                              state: state,
                              onSignIn: widget.onSignIn,
                              onBack: _cubit.backToConfirmation,
                              onRefresh: _cubit.refreshPolicy,
                              onComplete: () async {
                                await _cubit.completeFishingSelection();
                              },
                            ),
                          },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.semanticLabel,
    required this.child,
    required this.onPressed,
    this.peachBack = false,
  });

  final String semanticLabel;
  final Widget child;
  final VoidCallback onPressed;
  final bool peachBack;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    child: Material(
      color: peachBack ? Colors.transparent : ReefishColors.primaryAction,
      shape: peachBack
          ? const CircleBorder()
          : const CircleBorder(side: BorderSide(color: ReefishColors.brand)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: peachBack ? 38 : 40,
          height: peachBack ? 38 : 40,
          child: Center(child: child),
        ),
      ),
    ),
  );
}

class _DepartureSheet extends StatelessWidget {
  const _DepartureSheet({
    required this.state,
    required this.onCurrentLocation,
    required this.onShowMap,
    required this.onSave,
    this.compact = false,
  });

  final DepartureState state;
  final VoidCallback onCurrentLocation;
  final VoidCallback onShowMap;
  final VoidCallback onSave;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHandle(),
            const SizedBox(height: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  state.point == null
                      ? 'Ketuk peta untuk memilih titik keberangkatan.'
                      : 'Titik ${_cellDisplayCode(state.cell!)} · ${_coordinateLabel(state.point!)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 18 / 13,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            _SaveButton(
              enabled: state.canSave,
              busy: state.saving,
              saved: false,
              onPressed: onSave,
            ),
          ],
        ),
      );
    }
    final useScroll =
        media.size.width < 440 ||
        media.size.height < 720 ||
        media.textScaler.scale(14) > 15;
    final content = <Widget>[
      SizedBox(height: useScroll ? 12 : 20),
      const Text(
        'Simpan Titik Keberangkatan',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white,
          fontSize: 24,
          height: 32 / 24,
          letterSpacing: -0.4,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Tandai lokasi awal perjalananmu agar titik keberangkatan tetap tercatat.',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.white, fontSize: 14, height: 22 / 14),
      ),
      const SizedBox(height: 20),
      _CurrentLocationButton(
        busy: state.locating,
        onPressed: onCurrentLocation,
      ),
      const SizedBox(height: 20),
      _MapButton(onPressed: onShowMap),
      if (state.message != null) ...[
        const SizedBox(height: 8),
        _Notice(message: state.message!, isError: state.isError),
      ],
    ];
    final paddedContent = content
        .map(
          (child) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: child,
          ),
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
      child: useScroll
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SheetHandle(),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: paddedContent,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _SaveButton(
                  enabled: state.canSave,
                  busy: state.saving,
                  saved: false,
                  onPressed: onSave,
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SheetHandle(),
                ...paddedContent,
                const Spacer(),
                _SaveButton(
                  enabled: state.canSave,
                  busy: state.saving,
                  saved: false,
                  onPressed: onSave,
                ),
              ],
            ),
    );
  }
}

class _ConfirmationSheet extends StatelessWidget {
  const _ConfirmationSheet({
    required this.state,
    required this.onEdit,
    required this.onSave,
    required this.onNext,
    this.compact = false,
  });

  final DepartureState state;
  final VoidCallback onEdit;
  final VoidCallback onSave;
  final VoidCallback onNext;
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(24, compact ? 10 : 20, 24, compact ? 12 : 40),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SheetHandle(),
        SizedBox(height: compact ? 8 : 20),
        if (compact)
          Row(
            children: [
              Expanded(
                child: Text(
                  state.point == null
                      ? 'Titik keberangkatan belum dipilih.'
                      : 'Titik ${_cellDisplayCode(state.cell!)} · ${_coordinateLabel(state.point!)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 72,
                height: 40,
                child: OutlinedButton(
                  onPressed: onEdit,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFD9ECE8),
                    foregroundColor: const Color(0xFF236A50),
                    side: const BorderSide(color: ReefishColors.reef, width: 2),
                    shape: const StadiumBorder(),
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('Edit'),
                ),
              ),
            ],
          )
        else
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Text(
                          'Tandai lokasi awal perjalananmu agar titik keberangkatan tetap tercatat.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 22 / 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      SizedBox(
                        width: 86,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: onEdit,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFFD9ECE8),
                            foregroundColor: const Color(0xFF236A50),
                            side: const BorderSide(
                              color: ReefishColors.reef,
                              width: 2,
                            ),
                            shape: const StadiumBorder(),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Text(
                            'Edit',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _PointCard(
                    icon: SvgPicture.asset(
                      'assets/untracked/focus-Group1-c48684a5-51c6-4614-9df9-ab73093efce5.svg',
                      width: 26,
                      height: 26,
                    ),
                    title: 'Titik keberangkatan',
                    detail: '',
                    onTap: onNext,
                    label: state.point == null
                        ? 'Titik keberangkatan belum dipilih. Buka pilihan titik ikan'
                        : 'Titik keberangkatan ${_coordinateLabel(state.point!)}. Buka pilihan titik ikan',
                  ),
                  if (state.message != null &&
                      state.message!.contains('belum tersimpan')) ...[
                    const SizedBox(height: 8),
                    _Notice(message: state.message!, isError: state.isError),
                  ],
                ],
              ),
            ),
          ),
        SizedBox(height: compact ? 6 : 8),
        _SaveButton(
          enabled: state.canSave,
          busy: state.saving,
          saved: false,
          onPressed: onSave,
        ),
      ],
    ),
  );
}

class _FishingSheet extends StatelessWidget {
  const _FishingSheet({
    required this.state,
    required this.onBack,
    required this.onComplete,
    required this.onRefresh,
    this.compact = false,
    this.onSignIn,
  });

  final DepartureState state;
  final VoidCallback onBack;
  final VoidCallback onComplete;
  final VoidCallback onRefresh;
  final VoidCallback? onSignIn;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final access = state.fishingAccessAt(DateTime.now());
    final canComplete = state.canCompleteFishingAt(DateTime.now());
    final needsSignIn =
        state.policyFailure?.code ==
        GridPolicyFailureCode.authenticationRequired;
    final notConfigured =
        state.policyFailure?.code == GridPolicyFailureCode.notConfigured;
    final retryStatus =
        state.fishingPoint != null &&
        // a locked cell is final for this point: the fisher picks another cell, no reload
        (access == GridAccess.unknown || state.isError);
    if (compact) {
      final status =
          state.fishingMessage ??
          (state.policyLoading
              ? 'Memuat status petak…'
              : state.fishingPoint == null
              ? 'Ketuk peta untuk memilih titik ikan.'
              : access == GridAccess.locked
              ? 'Petak terkunci untuk menangkap ikan.'
              : access == GridAccess.unlocked
              ? 'Status petak terverifikasi.'
              : 'Status petak belum terverifikasi.');
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHandle(),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                '${state.fishingPoint == null ? 'Pilih titik ikan pada peta.' : _coordinateLabel(state.fishingPoint!)}  ·  $status',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            const SizedBox(height: 6),
            _SaveButton(
              enabled:
                  !state.policyLoading &&
                  !notConfigured &&
                  (needsSignIn ? onSignIn != null : canComplete || retryStatus),
              busy: state.fishingSaving || state.policyLoading,
              saved: false,
              onPressed: needsSignIn
                  ? (onSignIn ?? onRefresh)
                  : retryStatus
                  ? onRefresh
                  : onComplete,
              label: needsSignIn
                  ? 'Masuk untuk verifikasi'
                  : notConfigured
                  ? 'Layanan belum terhubung'
                  : retryStatus
                  ? 'Muat ulang status'
                  : 'Selesai',
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 19, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SheetHandle(),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: FocusFishMark(variant: FocusFishMarkVariant.sheet),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Tempatkan titik ikan?',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      height: 32 / 24,
                      letterSpacing: -0.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tandai lokasi penangkapanmu.',
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 22 / 14,
                    ),
                  ),
                  const SizedBox(height: 13),
                  _PointCard(
                    icon: SvgPicture.asset(
                      'assets/untracked/focus-Group1-c48684a5-51c6-4614-9df9-ab73093efce5.svg',
                      width: 26,
                      height: 26,
                    ),
                    title: state.fishingPoint == null
                        ? 'Pilih titik pada peta'
                        : 'Titik penangkapan',
                    detail: state.fishingPoint == null
                        ? 'Ketuk peta untuk memilih lokasi'
                        : _coordinateLabel(state.fishingPoint!),
                    onTap: () {},
                    label: 'Titik penangkapan terpilih',
                    error:
                        access != GridAccess.unlocked &&
                        state.fishingPoint != null,
                    height: 60,
                    radius: 20,
                  ),
                  if (state.fishingMessage != null) ...[
                    const SizedBox(height: 7),
                    Text(
                      state.fishingMessage!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        height: 18 / 12,
                      ),
                    ),
                  ],
                  if (state.policyLoading) ...[
                    const SizedBox(height: 5),
                    const Text(
                      'Memuat status petak…',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _SaveButton(
            enabled:
                !state.policyLoading &&
                !notConfigured &&
                (needsSignIn ? onSignIn != null : canComplete || retryStatus),
            busy: state.fishingSaving || state.policyLoading,
            saved: false,
            onPressed: needsSignIn
                ? (onSignIn ?? onRefresh)
                : retryStatus
                ? onRefresh
                : onComplete,
            label: needsSignIn
                ? 'Masuk untuk verifikasi'
                : notConfigured
                ? 'Layanan belum terhubung'
                : retryStatus
                ? 'Muat ulang status'
                : 'Selesai',
          ),
        ],
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 56,
      height: 5,
      decoration: const BoxDecoration(
        color: ReefishColors.border,
        borderRadius: BorderRadius.all(Radius.circular(3)),
      ),
    ),
  );
}

class _PointCard extends StatelessWidget {
  const _PointCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    required this.label,
    this.error = false,
    this.height = 48,
    this.radius = 12,
  });
  final Widget icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
  final String label;
  final bool error;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Material(
      color: error ? const Color(0xFFFFE5DE) : const Color(0xFFD9ECE8),
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                icon,
                const SizedBox(width: 14),
                Expanded(
                  child: detail.isEmpty
                      ? Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ReefishColors.textPrimary,
                            fontSize: 16,
                            height: 24 / 16,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: ReefishColors.textPrimary,
                                fontSize: 16,
                                height: 24 / 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: error
                                    ? const Color(0xFF8A3122)
                                    : ReefishColors.textPrimary,
                                fontSize: 12,
                                height: 18 / 12,
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _CompactMapSheet extends StatelessWidget {
  const _CompactMapSheet({required this.state, required this.onConfirm});

  final DepartureState state;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
    child: Column(
      children: [
        Container(
          width: 56,
          height: 5,
          decoration: const BoxDecoration(
            color: ReefishColors.border,
            borderRadius: BorderRadius.all(Radius.circular(3)),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              state.point == null
                  ? 'Ketuk peta untuk memilih titik keberangkatan.'
                  : 'Titik ${_cellDisplayCode(state.cell!)} dipilih · ${_coordinateLabel(state.point!)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 22 / 14,
              ),
            ),
          ),
        ),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton(
            onPressed: onConfirm,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: ReefishColors.border, width: 2),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(state.point == null ? 'Kembali' : 'Gunakan titik ini'),
          ),
        ),
      ],
    ),
  );
}

class _CurrentLocationButton extends StatelessWidget {
  const _CurrentLocationButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Material(
      color: const Color(0xFFD9ECE8),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: busy ? null : onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                SvgPicture.asset(
                  'assets/untracked/departure-Ellipse1-abd5ed8d-6e8c-4658-a84a-039f374441e4.svg',
                  width: 17,
                  height: 17,
                ),
              const SizedBox(width: 14),
              const Flexible(
                child: Text(
                  'Pilih Lokasi Saat Ini',
                  maxLines: 2,
                  style: TextStyle(
                    color: ReefishColors.textPrimary,
                    fontSize: 16,
                    height: 24 / 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: ReefishColors.border, width: 2),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 22),
      ),
      child: Row(
        children: [
          SvgPicture.asset(
            'assets/untracked/departure-Maps-211b016c-4c68-4d20-a8d9-034a15aa2518.svg',
            width: 24,
            height: 24,
          ),
          const SizedBox(width: 14),
          const Flexible(
            child: Text(
              'Lihat Peta',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.enabled,
    required this.busy,
    required this.saved,
    required this.onPressed,
    this.label,
  });

  final bool enabled;
  final bool busy;
  final bool saved;
  final VoidCallback onPressed;
  final String? label;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 48,
    child: ElevatedButton(
      onPressed: enabled && !busy ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: ReefishColors.reef,
        disabledBackgroundColor: ReefishColors.reef.withValues(alpha: 0.55),
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
        elevation: 4,
      ),
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : Text(
              label ?? (saved ? 'Tersimpan' : 'Simpan'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.isError});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isError ? Icons.info_outline : Icons.check_circle_outline,
          size: 18,
          color: Colors.white,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              height: 18 / 12,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(4),
    ),
    child: InkWell(
      onTap: () => launchUrl(
        Uri.https('www.openstreetmap.org', '/copyright'),
        mode: LaunchMode.externalApplication,
      ),
      borderRadius: BorderRadius.circular(4),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          '© OpenStreetMap contributors',
          style: TextStyle(color: Color(0xFF202A2A), fontSize: 12),
        ),
      ),
    ),
  );
}

class _DepartureMap extends StatefulWidget {
  const _DepartureMap({
    this.marineRepository,
    required this.tileUrlTemplate,
    required this.dimMap,
    required this.popupBottomInset,
    required this.selectedPoint,
    required this.fishingPoint,
    required this.policy,
    required this.policyLoading,
    this.policyFailure,
    required this.onPointPicked,
    required this.onPopupVisibilityChanged,
  });

  final String tileUrlTemplate;
  final bool dimMap;
  final double popupBottomInset;
  final MarineRepository? marineRepository;
  final GeoPoint? selectedPoint;
  final GeoPoint? fishingPoint;
  final GridPolicySnapshot? policy;
  final bool policyLoading;
  final GridPolicyFailure? policyFailure;
  final ValueChanged<GeoPoint> onPointPicked;
  final ValueChanged<bool> onPopupVisibilityChanged;

  @override
  State<_DepartureMap> createState() => _DepartureMapState();
}

class _DepartureMapState extends State<_DepartureMap> {
  final _mapController = MapController();
  late final MarineMapCubit _marine;
  final _grid = MetricGrid500(
    initialBounds: const GeoBounds(
      west: 112.25,
      south: -9.15,
      east: 113.1,
      north: -8.35,
    ),
  );
  GridViewport? _viewport;
  bool _tileError = false;
  Timer? _viewportTimer;
  bool _mapReady = false;
  GridCell? _activeCell;
  MarineDataset? _preparedDataset;
  MarineCellLookup? _cellLookup;
  final Map<MarineAreaFeature, List<List<List<LatLng>>>> _areaCoordinates = {};
  double? _areaLayerOpacity;
  Widget? _coralLayer;
  Widget? _mangroveLayer;

  void _prepareDataset(MarineDataset dataset) {
    if (identical(_preparedDataset, dataset)) return;
    _preparedDataset = dataset;
    _cellLookup = MarineCellLookup(dataset);
    _areaCoordinates.clear();
    _areaLayerOpacity = null;
    _coralLayer = null;
    _mangroveLayer = null;
  }

  @override
  void initState() {
    super.initState();
    _marine = MarineMapCubit(
      repository: widget.marineRepository ?? _defaultMarineRepository(),
    )..initialize();
  }

  MarineRepository _defaultMarineRepository() {
    try {
      return SupabaseMarineRepository(client: Supabase.instance.client);
    } catch (_) {
      return AssetMarineRepository();
    }
  }

  void _updateViewport(MapCamera camera) {
    _viewportTimer?.cancel();
    _viewportTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      _setViewport(camera);
    });
  }

  void _setViewport(MapCamera camera) {
    final bounds = camera.visibleBounds;
    final result = _grid.enumerateViewport(
      GeoBounds(
        west: bounds.west,
        south: bounds.south,
        east: bounds.east,
        north: bounds.north,
      ),
      maxCells: 600,
    );
    if (mounted) setState(() => _viewport = result);
  }

  void _onMapReady() {
    _mapReady = true;
    _updateViewport(_mapController.camera);
    _centerSelectedIfOutside();
  }

  void _centerSelectedIfOutside() {
    final selected = widget.selectedPoint;
    if (!_mapReady || selected == null) return;
    final camera = _mapController.camera;
    final latLng = LatLng(selected.latitude, selected.longitude);
    if (!camera.visibleBounds.contains(latLng)) {
      _mapController.move(latLng, camera.zoom);
    }
  }

  @override
  void didUpdateWidget(covariant _DepartureMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPoint = oldWidget.selectedPoint;
    final newPoint = widget.selectedPoint;
    if (oldPoint?.latitude != newPoint?.latitude ||
        oldPoint?.longitude != newPoint?.longitude) {
      _centerSelectedIfOutside();
    }
  }

  @override
  void dispose() {
    _marine.close();
    _viewportTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<MarineMapCubit, MarineMapState>(
    bloc: _marine,
    builder: (context, marine) => Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: const LatLng(-8.447, 112.683),
            initialZoom: 14,
            minZoom: 8,
            maxZoom: 18,
            cameraConstraint: CameraConstraint.containCenter(
              bounds: LatLngBounds(
                LatLng(_grid.initialBounds.south, _grid.initialBounds.west),
                LatLng(_grid.initialBounds.north, _grid.initialBounds.east),
              ),
            ),
            onTap: (_, point) => _inspectPoint(
              GeoPoint(latitude: point.latitude, longitude: point.longitude),
            ),
            onMapReady: _onMapReady,
            onPositionChanged: (camera, _) => _updateViewport(camera),
          ),
          children: [
            TileLayer(
              urlTemplate: widget.tileUrlTemplate,
              userAgentPackageName: 'com.reefish.mobile',
              maxNativeZoom: 19,
              maxZoom: 20,
              keepBuffer: 0,
              panBuffer: 0,
              tileDisplay: const TileDisplay.fadeIn(
                duration: Duration(milliseconds: 90),
              ),
              errorTileCallback: (_, __, ___) {
                if (mounted && !_tileError) setState(() => _tileError = true);
              },
            ),
            ..._marineAreaLayers(marine),
            if (_viewport != null) _gridLayer(_viewport!, marine),
            if (_viewport?.exceeded == true && marine.showGrid)
              _outerBoundsLayer(),
            if (widget.selectedPoint case final departure?)
              if (widget.fishingPoint case final fishing?)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [
                        LatLng(departure.latitude, departure.longitude),
                        LatLng(fishing.latitude, fishing.longitude),
                      ],
                      color: Colors.white,
                      strokeWidth: 2,
                      pattern: StrokePattern.dashed(segments: [6, 5]),
                    ),
                  ],
                ),
            if (widget.selectedPoint case final point?)
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(point.latitude, point.longitude),
                    width: 22,
                    height: 22,
                    child: Transform.rotate(
                      angle: math.pi / 2,
                      child: SvgPicture.asset(
                        'assets/untracked/departure-DeparturePoint-7cc962e9-4df6-4ce7-bba1-7962c098fae5.svg',
                        width: 22,
                        height: 22,
                      ),
                    ),
                  ),
                ],
              ),
            if (widget.fishingPoint case final point?)
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(point.latitude, point.longitude),
                    width: 45.333,
                    height: 34,
                    child: const FocusFishMark(
                      variant: FocusFishMarkVariant.map,
                    ),
                  ),
                ],
              ),
            if (_tileError)
              const Positioned(
                top: 132,
                left: 0,
                right: 0,
                child: Align(
                  child: _MapHint(message: 'Peta dasar belum termuat'),
                ),
              ),
          ],
        ),
        if (widget.dimMap)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: _activeCell == null
                    ? const Color(0x52000000)
                    : const Color(0x26000000),
              ),
            ),
          ),
        if (_activeCell == null)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 120,
            left: 16,
            child: FilledButton.icon(
              onPressed: _openLayers,
              icon: const Icon(Icons.layers_outlined, size: 20),
              label: const Text('Lapisan peta'),
              style: FilledButton.styleFrom(
                backgroundColor: ReefishColors.primaryAction,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        if (marine.loading || marine.error != null)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 174,
            left: 16,
            right: 16,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _MapHint(
                message: marine.loading
                    ? 'Memuat data parameter…'
                    : 'Data parameter belum dimuat. Buka Lapisan peta untuk mencoba lagi.',
              ),
            ),
          ),
        if (marine.dataset != null && !marine.loading && marine.error == null)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 174,
            left: 16,
            right: 16,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _MapHint(message: _marineDataStatus(marine)),
            ),
          ),
        if (_activeCell case final cell?)
          Positioned.fill(
            child: KeyedSubtree(
              key: ValueKey('marine-cell-popup-${cell.id}'),
              child: _buildCellPopup(context, cell, marine),
            ),
          ),
      ],
    ),
  );

  Future<void> _openLayers() async {
    _clearCellPopup();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxWidth: 430,
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (context) => BlocBuilder<MarineMapCubit, MarineMapState>(
        bloc: _marine,
        builder: (context, state) => MarineLayerSheet(
          scalarLayer: state.scalarLayer,
          showCoral: state.showCoral,
          showMangrove: state.showMangrove,
          showGrid: state.showGrid,
          opacity: state.opacity,
          chlorophyllEntry: state.chlorophyllEntry,
          chlorophyllEntryCount: state.chlorophyllEntryCount,
          chlorophyllPeriodLabel: _selectedChlorophyllPeriod(state),
          chlorophyllLoading: state.chlorophyllLoading,
          loading: state.loading,
          error: state.error ?? state.chlorophyllError,
          onScalarChanged: _marine.setScalarLayer,
          onCoralChanged: _marine.setShowCoral,
          onMangroveChanged: _marine.setShowMangrove,
          onGridChanged: _marine.setShowGrid,
          onOpacityChanged: _marine.setOpacity,
          onChlorophyllEntryChanged: _marine.setChlorophyllEntry,
          onRetry: () {
            if (_marine.state.error != null) {
              _marine.retryBase();
            } else {
              _marine.retryChlorophyll();
            }
          },
        ),
      ),
    );
  }

  String? _selectedChlorophyllPeriod(MarineMapState state) {
    final dataset = state.dataset;
    if (dataset?.origin != MarineDataOrigin.authenticatedBackend ||
        state.chlorophyllEntry > dataset!.chlorophyllPeriods.length) {
      return null;
    }
    return dataset.chlorophyllPeriods[state.chlorophyllEntry - 1];
  }

  String _marineDataStatus(MarineMapState state) {
    final dataset = state.dataset!;
    if (dataset.origin == MarineDataOrigin.bundledSnapshot) {
      return 'Data bawaan aplikasi (offline)';
    }
    final period = state.scalarLayer == MarineScalarLayer.chlorophyll
        ? _selectedChlorophyllPeriod(state)
        : dataset.period;
    return period == null ? 'Data laut' : 'Data laut · periode $period';
  }

  Future<void> _inspectPoint(GeoPoint point) async {
    widget.onPointPicked(point);
    if (!_grid.initialBounds.contains(point)) {
      _clearCellPopup();
      return;
    }
    final cell = _grid.resolve(point);
    final wasVisible = _activeCell != null;
    setState(() => _activeCell = cell);
    if (!wasVisible) widget.onPopupVisibilityChanged(true);
  }

  Widget _buildCellPopup(
    BuildContext context,
    GridCell cell,
    MarineMapState marine,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      final media = MediaQuery.of(context);
      // Leave room for the OSM attribution and the popup's pointer below it.
      final bottomLimit = size.height - widget.popupBottomInset - 48.0;
      final preferredTop = media.padding.top + 104.0;
      final topLimit = bottomLimit - preferredTop < 160.0
          ? media.padding.top + 80.0
          : preferredTop;
      final availableHeight = math.max(0.0, bottomLimit - topLimit).toDouble();
      if (availableHeight < 80 || size.width < 48 || !_mapReady) {
        return const SizedBox.shrink();
      }
      final width = math.min(320.0, size.width - 24.0).toDouble();
      final height = math.min(296.0, availableHeight).toDouble();
      final anchor = _mapController.camera.latLngToScreenOffset(
        LatLng(cell.center.latitude, cell.center.longitude),
      );
      final anchorX = anchor.dx.clamp(8.0, size.width - 8.0).toDouble();
      final anchorY = anchor.dy.clamp(topLimit, bottomLimit).toDouble();
      final left = (anchorX - width / 2)
          .clamp(12.0, size.width - width - 12.0)
          .toDouble();
      final above = anchorY > topLimit + height / 2;
      final top = above
          ? (anchorY - height - 12.0)
                .clamp(topLimit, bottomLimit - height)
                .toDouble()
          : (anchorY + 12.0).clamp(topLimit, bottomLimit - height).toDouble();
      final rawPointerX = anchorX - left;
      final pointerX = rawPointerX.clamp(18.0, width - 30.0).toDouble();
      final anchorOnMap =
          anchor.dx >= 8 &&
          anchor.dx <= size.width - 8 &&
          anchor.dy >= topLimit &&
          anchor.dy <= bottomLimit;
      final pointerEdgeY = above ? top + height + 6 : top - 6;
      final showPointer =
          anchorOnMap &&
          (rawPointerX - pointerX).abs() < 1 &&
          (pointerEdgeY - anchorY).abs() <= 18;
      final dataset = marine.dataset;
      if (dataset != null) _prepareDataset(dataset);
      final features = dataset == null ? null : _cellLookup!.featuresFor(cell);
      final policyAccess =
          widget.policy?.accessFor(cell.id, DateTime.now()) ??
          GridAccess.unknown;
      final access = policyAccess == GridAccess.locked
          ? GridAccess.locked
          : widget.policyFailure != null || widget.policyLoading
          ? GridAccess.unknown
          : policyAccess;
      final detail = dataset == null
          ? _CellDataStatusPopup(
              loading: marine.loading,
              error: marine.error,
              onRetry: _marine.retryBase,
              onClose: _closeCellPopup,
            )
          : MarineCellSummaryPopup(
              key: ValueKey(cell.id),
              gridCell: cell,
              cell: dataset.cells[cell.id],
              coralCount: features!.coral.length,
              mangroveCount: features.mangrove.length,
              loadChlorophyllEntries: () => _marine.loadCellChlorophyllEntry(
                cell.id,
                marine.chlorophyllEntry,
              ),
              initialChlorophyllEntry: marine.chlorophyllEntry,
              chlorophyllPeriodLabel: _selectedChlorophyllPeriod(marine),
              access: access,
              policyStatus: _cellSummaryPolicyStatus(access),
              onClose: _closeCellPopup,
              onDetails: () => _openCellDetails(cell, dataset),
            );
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: left,
            top: top,
            width: width,
            height: height,
            child: Material(
              color: Colors.white,
              elevation: 10,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: detail,
            ),
          ),
          if (showPointer)
            Positioned(
              left: left + pointerX - 9,
              top: above ? top + height : top - 12,
              child: CustomPaint(
                size: const Size(18, 12),
                painter: _PopupPointerPainter(pointsUp: !above),
              ),
            ),
        ],
      );
    },
  );

  String _cellPolicyStatus(GridCell cell) {
    final access =
        widget.policy?.accessFor(cell.id, DateTime.now()) ?? GridAccess.unknown;
    return widget.policyFailure?.userMessage ??
        switch (access) {
          GridAccess.locked =>
            'Terkunci untuk menangkap ikan: '
                '${widget.policy?.locks[cell.id]?.reason ?? 'Alasan belum dicantumkan'}. '
                'Titik keberangkatan tetap dapat dicatat.',
          GridAccess.unlocked =>
            'Tidak ada lock admin pada snapshot yang masih berlaku. '
                'Status ini bukan penilaian keselamatan atau izin menangkap ikan.',
          GridAccess.unknown =>
            'Status lock admin belum terverifikasi. '
                'Titik keberangkatan tetap dapat dicatat.',
        };
  }

  String _cellSummaryPolicyStatus(GridAccess access) {
    if (access == GridAccess.locked) return 'Terkunci untuk menangkap ikan';
    if (widget.policyLoading) return 'Memverifikasi status petak…';
    if (widget.policyFailure != null) {
      return widget.policyFailure!.userMessage;
    }
    if (access == GridAccess.unlocked) {
      return 'Tidak ada lock pada snapshot aktif';
    }
    if (widget.policy != null && !widget.policy!.isFreshAt(DateTime.now())) {
      return 'Status petak sudah kedaluwarsa. Muat ulang status.';
    }
    return 'Status lock belum terverifikasi';
  }

  Future<void> _openCellDetails(GridCell cell, MarineDataset dataset) =>
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
              policyStatus: _cellPolicyStatus(cell),
              popup: true,
              onClose: () => Navigator.of(dialogContext).pop(),
            ),
          ),
        ),
      );

  void _closeCellPopup() {
    _clearCellPopup();
  }

  void _clearCellPopup() {
    if (_activeCell == null) return;
    setState(() => _activeCell = null);
    widget.onPopupVisibilityChanged(false);
  }

  Widget _outerBoundsLayer() {
    final bounds = _grid.initialBounds;
    final points = [
      LatLng(bounds.south, bounds.west),
      LatLng(bounds.south, bounds.east),
      LatLng(bounds.north, bounds.east),
      LatLng(bounds.north, bounds.west),
      LatLng(bounds.south, bounds.west),
    ];
    return Semantics(
      container: true,
      label: 'Batas area grid · 500 m',
      child: IgnorePointer(
        child: PolylineLayer(
          polylines: [
            Polyline(
              points: points,
              color: const Color(0xFF087F78),
              strokeWidth: 2,
              pattern: StrokePattern.dashed(segments: [6, 5]),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _marineAreaLayers(MarineMapState state) {
    final dataset = state.dataset;
    if (dataset == null) return const [];
    _prepareDataset(dataset);
    if (_areaLayerOpacity != state.opacity) {
      _areaLayerOpacity = state.opacity;
      _coralLayer = null;
      _mangroveLayer = null;
    }
    Widget render(
      List<MarineAreaFeature> features,
      Color color, {
      bool coral = false,
    }) {
      final polygons = <Polygon>[];
      for (final feature in features) {
        if (coral && feature.properties['value'] != 1) continue;
        final coordinates = _areaCoordinates.putIfAbsent(
          feature,
          () => feature.polygons
              .map(
                (polygon) => polygon
                    .map(
                      (ring) => ring
                          .map(
                            (point) => LatLng(point.latitude, point.longitude),
                          )
                          .toList(growable: false),
                    )
                    .toList(growable: false),
              )
              .toList(growable: false),
        );
        for (final rings in coordinates) {
          if (rings.isEmpty) continue;
          polygons.add(
            Polygon(
              points: rings.first,
              holePointsList: rings.skip(1).toList(growable: false),
              color: color.withValues(alpha: state.opacity),
              borderColor: color,
              borderStrokeWidth: 0.7,
            ),
          );
        }
      }
      return IgnorePointer(
        child: PolygonLayer(
          polygons: polygons,
          simplificationTolerance: 0,
          drawInSingleWorld: true,
        ),
      );
    }

    return [
      if (state.showCoral)
        _coralLayer ??= render(
          dataset.coral,
          const Color(0xFFF28E2B),
          coral: true,
        ),
      if (state.showMangrove)
        _mangroveLayer ??= render(dataset.mangrove, const Color(0xFF238443)),
    ];
  }

  Color _marineCellColor(MarineCell cell, MarineMapState state) {
    final (value, min, max, low, high) = switch (state.scalarLayer) {
      MarineScalarLayer.none => (
        null,
        0.0,
        1.0,
        Colors.transparent,
        Colors.transparent,
      ),
      MarineScalarLayer.fish => (
        cell.fish,
        1.0,
        100.0,
        const Color(0xFFFFFFCC),
        const Color(0xFF006837),
      ),
      MarineScalarLayer.temperature => (
        cell.temperature,
        27.964,
        30.391,
        const Color(0xFF2166AC),
        const Color(0xFFB2182B),
      ),
      MarineScalarLayer.depth => (
        cell.depth,
        18.0,
        5000.0,
        const Color(0xFFDEEBF7),
        const Color(0xFF08306B),
      ),
      MarineScalarLayer.chlorophyll => (
        state.chlorophyllValues[cell.cellId],
        0.0998,
        5.1405,
        const Color(0xFFFFFFCC),
        const Color(0xFF004529),
      ),
    };
    if (value == null) return Colors.transparent;
    return Color.lerp(
      low,
      high,
      ((value - min) / (max - min)).clamp(0, 1),
    )!.withValues(alpha: state.opacity);
  }

  Widget _gridLayer(GridViewport viewport, MarineMapState marine) {
    final polygons = <Polygon>[];
    final markers = <Marker>[];
    final at = DateTime.now();
    for (final cell in viewport.cells) {
      final access =
          widget.policy?.accessFor(cell.id, at) ?? GridAccess.unknown;
      final sample = marine.dataset?.cells[cell.id];
      final points = cell.polygon
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList(growable: false);
      final fill = sample == null
          ? Colors.transparent
          : _marineCellColor(sample, marine);
      final border = switch (access) {
        GridAccess.unlocked => const Color(0xC0188E8B),
        GridAccess.locked => const Color(0xC0D58F76),
        GridAccess.unknown => const Color(0xB0188E8B),
      };
      final isSelected = _activeCell?.id == cell.id;
      if (marine.showGrid ||
          fill != Colors.transparent ||
          access == GridAccess.locked ||
          isSelected) {
        polygons.add(
          Polygon(
            points: points,
            color: fill,
            borderColor: isSelected ? ReefishColors.brand : border,
            borderStrokeWidth: isSelected
                ? 2.6
                : access == GridAccess.locked
                ? 2
                : marine.showGrid
                ? 0.7
                : 0,
          ),
        );
      }
      if (access == GridAccess.locked) {
        markers.add(
          Marker(
            point: LatLng(cell.center.latitude, cell.center.longitude),
            width: 15,
            height: 15,
            child: const Icon(
              Icons.lock_rounded,
              size: 13,
              color: Color(0xFFD58F76),
            ),
          ),
        );
      }
    }
    return Stack(
      children: [
        PolygonLayer(polygons: polygons),
        MarkerLayer(markers: markers),
        if (viewport.exceeded)
          const Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(top: 124),
              child: _MapHint(
                message: 'Perbesar peta untuk melihat petak 500 m.',
              ),
            ),
          ),
      ],
    );
  }
}

class _MapHint extends StatelessWidget {
  const _MapHint({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Text(message, style: const TextStyle(fontSize: 12)),
    ),
  );
}

class _CellDataStatusPopup extends StatelessWidget {
  const _CellDataStatusPopup({
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onClose,
  });

  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Detail petak, ${loading ? 'memuat data' : 'data gagal dimuat'}',
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Detail petak',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Tutup detail petak',
                constraints: const BoxConstraints.tightFor(
                  width: 48,
                  height: 48,
                ),
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 4),
              child: loading
                  ? const SizedBox(
                      height: 72,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          error == null
                              ? 'Data parameter belum dapat dimuat.'
                              : 'Data parameter belum dapat dimuat: $error',
                          style: const TextStyle(fontSize: 13),
                        ),
                        TextButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Coba lagi'),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PopupPointerPainter extends CustomPainter {
  const _PopupPointerPainter({required this.pointsUp});

  final bool pointsUp;

  @override
  void paint(Canvas canvas, Size size) {
    final path = ui.Path()
      ..moveTo(0, pointsUp ? size.height : 0)
      ..lineTo(size.width / 2, pointsUp ? 0 : size.height)
      ..lineTo(size.width, pointsUp ? size.height : 0)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _PopupPointerPainter oldDelegate) =>
      oldDelegate.pointsUp != pointsUp;
}

String _coordinateLabel(GeoPoint point) =>
    '${point.latitude.abs().toStringAsFixed(4)}° ${point.latitude < 0 ? 'S' : 'N'}, '
    '${point.longitude.abs().toStringAsFixed(4)}° ${point.longitude < 0 ? 'W' : 'E'}';

String _cellDisplayCode(GridCell cell) => '49S-R${cell.row}-C${cell.col}';
