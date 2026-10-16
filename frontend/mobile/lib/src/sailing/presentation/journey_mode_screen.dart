import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/reef_fish_theme.dart';
import '../../journey/presentation/widgets/osm_attribution.dart';

enum JourneyMode { tracked, manual }

/// Presents the two ways a fisher can record a trip over the supplied map.
class JourneyModeScreen extends StatefulWidget {
  const JourneyModeScreen({
    required this.map,
    required this.onContinue,
    required this.onCancel,
    this.initialMode,
    super.key,
  });

  final Widget map;
  final ValueChanged<JourneyMode> onContinue;
  final VoidCallback onCancel;
  final JourneyMode? initialMode;

  @override
  State<JourneyModeScreen> createState() => _JourneyModeScreenState();
}

class _JourneyModeScreenState extends State<JourneyModeScreen> {
  late JourneyMode? _selected = widget.initialMode;

  @override
  void didUpdateWidget(covariant JourneyModeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialMode != widget.initialMode) {
      _selected = widget.initialMode;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ReefishColors.canvas,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxSheetHeight = constraints.maxHeight * .82;
          final sheetHeight = math.min(521.0, maxSheetHeight);
          return Stack(
            fit: StackFit.expand,
            children: [
              widget.map,
              Positioned(
                left: 24,
                right: 24,
                top: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 32),
                    child: Row(
                      children: [
                        Tooltip(
                          message: 'Kembali',
                          child: InkWell(
                            key: const ValueKey('journey-mode-back'),
                            customBorder: const CircleBorder(),
                            onTap: widget.onCancel,
                            child: SvgPicture.asset(
                              'assets/icons/login-AkarIconsArrowLeft-b559ec96-131a-4c84-b0d4-8c5f220aab8d.svg',
                              width: 40,
                              height: 40,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              color: Color(0xAA102F3A),
                              shape: BoxShape.circle,
                            ),
                            child: Transform.scale(
                              scale: 1.6,
                              child: Image.asset(
                                'assets/journey/compass.png',
                                width: 40,
                                height: 40,
                                fit: BoxFit.contain,
                                color: Colors.white,
                                colorBlendMode: BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                bottom: sheetHeight + 6,
                child: const OsmAttribution(),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: sheetHeight,
                  child: Container(
                    key: const ValueKey('journey-mode-sheet'),
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      minimum: const EdgeInsets.only(bottom: 18),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
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
                                      color: ReefishColors.border,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                const Text(
                                  'Pilih cara mencatat perjalanan',
                                  style: TextStyle(
                                    color: ReefishColors.textPrimary,
                                    fontSize: 23,
                                    height: 30 / 23,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -.35,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Catat perjalanan dengan atau tanpa pemantauan lokasi langsung.',
                                  style: TextStyle(
                                    color: ReefishColors.textSecondary,
                                    fontSize: 14,
                                    height: 22 / 14,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                _ModeCard(
                                  key: const ValueKey('journey-mode-tracked'),
                                  title: 'Pantau langsung',
                                  description:
                                      'Lokasi dicatat selama perjalanan.',
                                  selected: _selected == JourneyMode.tracked,
                                  onTap: () => setState(
                                    () => _selected = JourneyMode.tracked,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _ModeCard(
                                  key: const ValueKey('journey-mode-manual'),
                                  title: 'Tanpa pemantauan',
                                  description:
                                      'Tambahkan titik dan hasil tangkapan manual.',
                                  selected: _selected == JourneyMode.manual,
                                  onTap: () => setState(
                                    () => _selected = JourneyMode.manual,
                                  ),
                                ),
                                const SizedBox(height: 48),
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: FilledButton(
                                    key: const ValueKey(
                                      'journey-mode-continue',
                                    ),
                                    onPressed: _selected == null
                                        ? null
                                        : () => widget.onContinue(_selected!),
                                    style: FilledButton.styleFrom(
                                      backgroundColor:
                                          ReefishColors.primaryAction,
                                      disabledBackgroundColor: const Color(
                                        0xFFEEF1EC,
                                      ),
                                      disabledForegroundColor:
                                          ReefishColors.textSecondary,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      textStyle: const TextStyle(
                                        fontFamily: 'DM Sans',
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    child: Text(
                                      _selected == null
                                          ? 'Pilih salah satu mode'
                                          : 'Lanjutkan',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  height: 40,
                                  child: TextButton(
                                    key: const ValueKey('journey-mode-cancel'),
                                    onPressed: widget.onCancel,
                                    style: TextButton.styleFrom(
                                      foregroundColor:
                                          ReefishColors.textSecondary,
                                      textStyle: const TextStyle(
                                        fontFamily: 'DM Sans',
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    child: const Text('Batal'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? ReefishColors.primaryAction
        : ReefishColors.border;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      label: '$title. $description',
      child: Material(
        color: selected ? ReefishColors.field : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: ValueKey('journey-mode-card-${title.hashCode}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            constraints: const BoxConstraints(minHeight: 92),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: borderColor, width: selected ? 2 : 1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Center(
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected
                            ? ReefishColors.primaryAction
                            : Colors.white,
                        border: Border.all(
                          color: selected
                              ? ReefishColors.primaryAction
                              : ReefishColors.textSecondary,
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: ReefishColors.textPrimary,
                          fontSize: 16,
                          height: 22 / 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: const TextStyle(
                          color: ReefishColors.textSecondary,
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
    );
  }
}
