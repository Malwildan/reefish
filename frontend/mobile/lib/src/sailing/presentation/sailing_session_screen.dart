import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/reef_fish_theme.dart';
import '../../journey/presentation/widgets/osm_attribution.dart';
import '../application/sailing_bloc.dart';
import '../domain/sailing_session.dart';

/// Map-backed foreground sailing UI for one durable sailing session.
///
/// Departure is always marked by the fisher. Marking a fishing location is
/// delegated to the parent so that it can validate and lock the chosen point.
class SailingSessionScreen extends StatefulWidget {
  const SailingSessionScreen({
    required this.bloc,
    required this.mapBuilder,
    required this.onMarkFishing,
    required this.onResumeTracking,
    required this.onCompleted,
    required this.onBack,
    super.key,
  });

  final SailingBloc bloc;
  final Widget Function(SailingSession?) mapBuilder;
  final Future<void> Function() onMarkFishing;
  final Future<void> Function() onResumeTracking;
  final ValueChanged<SailingSession> onCompleted;
  final VoidCallback onBack;

  @override
  State<SailingSessionScreen> createState() => _SailingSessionScreenState();
}

class _SailingSessionScreenState extends State<SailingSessionScreen> {
  String? _deliveredCompletionId;
  bool _stopDialogOpen = false;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _deliverCompleted(widget.bloc.state.session);
    });
  }

  @override
  void didUpdateWidget(covariant SailingSessionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bloc != widget.bloc) {
      _deliveredCompletionId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _deliverCompleted(widget.bloc.state.session);
      });
    }
  }

  void _deliverCompleted(SailingSession? session) {
    if (session == null || session.phase != SailingPhase.completed) return;
    if (_deliveredCompletionId == session.clientTripId) return;
    _deliveredCompletionId = session.clientTripId;
    widget.onCompleted(session);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _actionError = null);
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _actionError = _friendlyError(error));
    }
  }

  Future<void> _requestStop() async {
    if (_stopDialogOpen) return;
    _stopDialogOpen = true;
    final shouldStop = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) =>
          _StopConfirmationDialog(elapsed: _elapsed(widget.bloc.state.session)),
    );
    _stopDialogOpen = false;
    if (shouldStop == true && mounted) {
      await _run(widget.bloc.finishSailing);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ReefishColors.canvas,
      body: BlocConsumer<SailingBloc, SailingState>(
        bloc: widget.bloc,
        listenWhen: (previous, current) =>
            previous.session?.phase != current.session?.phase ||
            previous.session?.clientTripId != current.session?.clientTripId,
        listener: (context, state) => _deliverCompleted(state.session),
        builder: (context, state) {
          final session = state.session;
          final phase = state.phase;
          final presentation = _PhasePresentation.forPhase(
            phase,
            _elapsed(session),
          );
          return LayoutBuilder(
            builder: (context, constraints) {
              final horizontalInset = math.min(
                24.0,
                math.max(16.0, (constraints.maxWidth - 382) / 2),
              );
              return Stack(
                fit: StackFit.expand,
                children: [
                  widget.mapBuilder(session),
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalInset,
                        32,
                        horizontalInset,
                        0,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _RoundMapAction(
                            tooltip: 'Kembali',
                            color: const Color(0xFFE58F73),
                            onPressed: widget.onBack,
                            child: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.only(top: 2, right: 12),
                            child: DecoratedBox(
                              decoration: const BoxDecoration(
                                color: Color(0xAA102F3A),
                                shape: BoxShape.circle,
                              ),
                              child: Transform.scale(
                                scale: 1.6,
                                child: Image.asset(
                                  'assets/journey/compass.png',
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.contain,
                                  color: Colors.white,
                                  colorBlendMode: BlendMode.srcIn,
                                ),
                              ),
                            ),
                          ),
                          _RoundMapAction(
                            tooltip: 'Pengumuman',
                            color: ReefishColors.primaryAction,
                            onPressed: null,
                            child: SvgPicture.asset(
                              'assets/journey/notifications.svg',
                              width: 22,
                              height: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: _PhasePanel(
                      presentation: presentation,
                      phase: phase,
                      busy: state.busy,
                      locationStatus: state.locationStatus,
                      error: _actionError ?? state.error,
                      onMarkDeparted: () => _run(widget.bloc.markDeparted),
                      onMarkFishing: () => _run(widget.onMarkFishing),
                      onFinish: () => _run(widget.bloc.finishSailing),
                      onBack: widget.onBack,
                      onStop: _requestStop,
                      onResumeTracking: () => _run(widget.onResumeTracking),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _PhasePresentation {
  const _PhasePresentation({
    required this.title,
    required this.description,
    required this.color,
    required this.handleColor,
    required this.actionLabel,
  });

  final String title;
  final String description;
  final Color color;
  final Color handleColor;
  final String actionLabel;

  static _PhasePresentation forPhase(
    SailingPhaseView phase,
    String elapsed,
  ) => switch (phase) {
    SailingPhaseView.idle => const _PhasePresentation(
      title: 'Perjalanan belum dimulai',
      description: 'Mulai perjalanan dari titik keberangkatan.',
      color: ReefishColors.canvas,
      handleColor: ReefishColors.primaryAction,
      actionLabel: 'Kembali',
    ),
    SailingPhaseView.atDeparture => const _PhasePresentation(
      title: 'Kamu Masih di Daratan!',
      description:
          'Ketuk Tandai berangkat setelah kamu benar-benar mulai melaut.',
      color: Color(0xFFA05245),
      handleColor: Color(0xFFF2E7E2),
      actionLabel: 'Tandai berangkat',
    ),
    SailingPhaseView.transit => const _PhasePresentation(
      title: 'Menuju Titik Penangkapan',
      description:
          'Lokasi direkam saat aplikasi digunakan. Konfirmasi sendiri titik penangkapan ikan.',
      color: ReefishColors.info,
      handleColor: Color(0xFFD6EAF1),
      actionLabel: 'Tandai titik penangkapan',
    ),
    SailingPhaseView.fishing => _PhasePresentation(
      title: 'Sedang Menangkap Ikan',
      description:
          'Lokasi dicatat saat aplikasi digunakan.\nPerjalanan berlangsung $elapsed.',
      color: const Color(0xFFDDEBF2),
      handleColor: ReefishColors.brand,
      actionLabel: 'Selesai',
    ),
    SailingPhaseView.completed => const _PhasePresentation(
      title: 'Perjalanan selesai',
      description: 'Perjalanan tersimpan di perangkat dan siap dilengkapi.',
      color: Color(0xFFDDEBF2),
      handleColor: ReefishColors.brand,
      actionLabel: 'Kembali',
    ),
  };
}

class _PhasePanel extends StatelessWidget {
  const _PhasePanel({
    required this.presentation,
    required this.phase,
    required this.busy,
    required this.locationStatus,
    required this.error,
    required this.onMarkDeparted,
    required this.onMarkFishing,
    required this.onFinish,
    required this.onBack,
    required this.onStop,
    required this.onResumeTracking,
  });

  final _PhasePresentation presentation;
  final SailingPhaseView phase;
  final bool busy;
  final SailingLocationStatus locationStatus;
  final String? error;
  final VoidCallback onMarkDeparted;
  final VoidCallback onMarkFishing;
  final VoidCallback onFinish;
  final VoidCallback onBack;
  final VoidCallback onStop;
  final VoidCallback onResumeTracking;

  bool get _hasPrimaryAction =>
      phase == SailingPhaseView.atDeparture ||
      phase == SailingPhaseView.transit ||
      phase == SailingPhaseView.fishing;

  VoidCallback? get _primaryAction => switch (phase) {
    SailingPhaseView.atDeparture => onMarkDeparted,
    SailingPhaseView.transit => onMarkFishing,
    SailingPhaseView.fishing => onFinish,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: false,
      minimum: const EdgeInsets.only(bottom: 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final media = MediaQuery.of(context);
          final inset = math.min(
            24.0,
            math.max(16.0, (media.size.width - 382) / 2),
          );
          return Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: presentation.color,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                inset,
                14,
                inset,
                20 + media.padding.bottom,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 56,
                          height: 5,
                          decoration: BoxDecoration(
                            color: presentation.handleColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (phase == SailingPhaseView.fishing) ...[
                        SvgPicture.asset(
                          'assets/icons/login-ReefishMarkColorAtoll-fc2ecd40-eb81-448f-a0b0-ab29c7974c23.svg',
                          width: 50,
                          height: 42,
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        presentation.title,
                        style: TextStyle(
                          color: _hasDarkPanel(phase)
                              ? Colors.white
                              : ReefishColors.textPrimary,
                          fontSize: 22,
                          height: 29 / 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        presentation.description,
                        style: TextStyle(
                          color: _hasDarkPanel(phase)
                              ? Colors.white
                              : ReefishColors.textPrimary,
                          fontSize: 14,
                          height: 22 / 14,
                        ),
                      ),
                      if (locationStatus != SailingLocationStatus.available &&
                          phase != SailingPhaseView.completed &&
                          phase != SailingPhaseView.idle) ...[
                        const SizedBox(height: 10),
                        _LocationStatusNotice(
                          status: locationStatus,
                          onResume: onResumeTracking,
                          busy: busy,
                        ),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          error!,
                          key: const ValueKey('sailing-error'),
                          style: TextStyle(
                            color: _hasDarkPanel(phase)
                                ? Colors.white
                                : const Color(0xFF8E352B),
                            fontSize: 13,
                            height: 19 / 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (_hasPrimaryAction) ...[
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton(
                            key: const ValueKey('sailing-primary-action'),
                            onPressed: busy ? null : _primaryAction,
                            style: FilledButton.styleFrom(
                              backgroundColor: phase == SailingPhaseView.fishing
                                  ? ReefishColors.reef
                                  : const Color(0xFFFFEDEC),
                              foregroundColor: phase == SailingPhaseView.fishing
                                  ? Colors.white
                                  : const Color(0xFF9F3F34),
                              disabledBackgroundColor: const Color(0xFFBBC8C7),
                              shape: const StadiumBorder(),
                              elevation: 2,
                              textStyle: const TextStyle(
                                fontFamily: 'DM Sans',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            child: Text(presentation.actionLabel),
                          ),
                        ),
                      ],
                      if (phase == SailingPhaseView.atDeparture ||
                          phase == SailingPhaseView.transit) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 40,
                          child: TextButton(
                            key: const ValueKey('sailing-stop'),
                            onPressed: busy ? null : onStop,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              textStyle: const TextStyle(
                                fontFamily: 'DM Sans',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            child: const Text('Berhenti'),
                          ),
                        ),
                      ],
                      if (phase == SailingPhaseView.completed)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: onBack,
                              child: Text(presentation.actionLabel),
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: OsmAttribution(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

bool _hasDarkPanel(SailingPhaseView phase) =>
    phase == SailingPhaseView.atDeparture || phase == SailingPhaseView.transit;

class _LocationStatusNotice extends StatelessWidget {
  const _LocationStatusNotice({
    required this.status,
    required this.onResume,
    required this.busy,
  });

  final SailingLocationStatus status;
  final VoidCallback onResume;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final message = switch (status) {
      SailingLocationStatus.permissionRequired =>
        'Izin lokasi diperlukan untuk mencatat posisi saat aplikasi digunakan.',
      SailingLocationStatus.lost =>
        'Lokasi terputus. Perjalanan belum selesai dan posisi belum dicatat.',
      SailingLocationStatus.paused =>
        'Pencatatan lokasi dijeda. Aktifkan lagi saat kamu siap.',
      SailingLocationStatus.available => '',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(
              color: ReefishColors.textPrimary,
              fontSize: 12,
              height: 18 / 12,
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: busy ? null : onResume,
              child: const Text('Aktifkan lokasi'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StopConfirmationDialog extends StatelessWidget {
  const _StopConfirmationDialog({required this.elapsed});

  final String elapsed;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFD9ECE8),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: ReefishColors.brand, width: 2),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Apakah Kamu Yakin Ingin Berhenti?',
                      style: TextStyle(
                        color: ReefishColors.textPrimary,
                        fontSize: 16,
                        height: 24 / 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('sailing-stop-dismiss'),
                  tooltip: 'Tutup',
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('sailing-stop-continue'),
              onPressed: () => Navigator.of(context).pop(false),
              style: FilledButton.styleFrom(
                backgroundColor: ReefishColors.primaryAction,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                minimumSize: const Size.fromHeight(46),
                visualDensity: VisualDensity.standard,
              ),
              child: const Text('Tetap Berlayar'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              key: const ValueKey('sailing-stop-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              style: OutlinedButton.styleFrom(
                backgroundColor: const Color(0xFFFFEDEC),
                foregroundColor: const Color(0xFF9F3F34),
                side: const BorderSide(color: Color(0xFFDF8E7A)),
                shape: const StadiumBorder(),
                minimumSize: const Size.fromHeight(46),
                visualDensity: VisualDensity.standard,
              ),
              child: const Text('Berhenti'),
            ),
            const SizedBox(height: 14),
            Text(
              'Waktu berjalan $elapsed',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ReefishColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundMapAction extends StatelessWidget {
  const _RoundMapAction({
    required this.tooltip,
    required this.color,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final Color color;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Tooltip(
            message: tooltip,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

String _elapsed(SailingSession? session) {
  if (session == null) return '0 menit';
  final seconds = DateTime.now().difference(session.startedAt).inSeconds;
  final elapsed = Duration(seconds: math.max(0, seconds));
  final hours = elapsed.inHours;
  final minutes = elapsed.inMinutes.remainder(60);
  final remainder = elapsed.inSeconds.remainder(60);
  if (hours > 0) return '$hours jam $minutes menit';
  if (minutes > 0) {
    return '$minutes menit ${remainder.toString().padLeft(2, '0')} detik';
  }
  return '${remainder.clamp(0, 59)} detik';
}

String _friendlyError(Object error) =>
    error.toString().replaceFirst('Bad state: ', '');
