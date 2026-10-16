import 'package:flutter/material.dart';

import '../../../theme/reef_fish_theme.dart';
import '../../domain/marine_data.dart';

/// Controls for the marine overlays shown on the map.
///
/// Embed this in a scroll-controlled modal bottom sheet to keep the map
/// visible while exposing all layer settings.
class MarineLayerSheet extends StatelessWidget {
  const MarineLayerSheet({
    required this.scalarLayer,
    required this.showCoral,
    required this.showMangrove,
    required this.showGrid,
    required this.opacity,
    required this.chlorophyllEntry,
    this.chlorophyllEntryCount = 24,
    this.chlorophyllPeriodLabel,
    required this.chlorophyllLoading,
    required this.error,
    required this.onScalarChanged,
    required this.onCoralChanged,
    required this.onMangroveChanged,
    required this.onGridChanged,
    required this.onOpacityChanged,
    required this.onChlorophyllEntryChanged,
    required this.onRetry,
    this.loading = false,
    super.key,
  }) : assert(opacity >= 0 && opacity <= 1),
       assert(chlorophyllEntry >= 1),
       assert(chlorophyllEntryCount >= 0);

  final MarineScalarLayer scalarLayer;
  final bool showCoral;
  final bool showMangrove;
  final bool showGrid;
  final double opacity;
  final int chlorophyllEntry;
  final int chlorophyllEntryCount;
  final String? chlorophyllPeriodLabel;
  final bool chlorophyllLoading;
  final String? error;
  final ValueChanged<MarineScalarLayer> onScalarChanged;
  final ValueChanged<bool> onCoralChanged;
  final ValueChanged<bool> onMangroveChanged;
  final ValueChanged<bool> onGridChanged;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<int> onChlorophyllEntryChanged;
  final VoidCallback onRetry;
  final bool loading;

  static const _scalars = <(MarineScalarLayer, String)>[
    (MarineScalarLayer.none, 'Nonaktif'),
    (MarineScalarLayer.fish, 'Ikan'),
    (MarineScalarLayer.temperature, 'Suhu laut (nilai)'),
    (MarineScalarLayer.depth, 'Kedalaman'),
    (MarineScalarLayer.chlorophyll, 'Klorofil-a'),
  ];

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * .8;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: ListView(
            key: const Key('marine-layer-sheet-scroll'),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            shrinkWrap: true,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ReefishColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Lapisan peta', style: _titleStyle),
              const SizedBox(height: 4),
              const Text(
                'Satu lapisan numerik dapat aktif pada satu waktu.',
                style: _bodyStyle,
              ),
              const SizedBox(height: 12),
              RadioGroup<MarineScalarLayer>(
                groupValue: scalarLayer,
                onChanged: (value) {
                  if (value != null) onScalarChanged(value);
                },
                child: Column(
                  children: [
                    for (final (layer, label) in _scalars)
                      RadioListTile<MarineScalarLayer>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: Text(label),
                        value: layer,
                        activeColor: ReefishColors.primaryAction,
                      ),
                  ],
                ),
              ),
              if (scalarLayer == MarineScalarLayer.chlorophyll) ...[
                const SizedBox(height: 4),
                if (chlorophyllEntryCount == 0)
                  const Text(
                    'Periode klorofil-a tidak tersedia.',
                    style: _bodyStyle,
                  )
                else if (chlorophyllEntryCount == 1)
                  Text(
                    'Periode klorofil-a: ${chlorophyllPeriodLabel ?? 'tidak diketahui'}',
                    style: _bodyStyle,
                  )
                else ...[
                  Text(
                    chlorophyllPeriodLabel == null
                        ? 'Urutan ekspor klorofil-a: $chlorophyllEntry dari $chlorophyllEntryCount'
                        : 'Periode klorofil-a: $chlorophyllPeriodLabel',
                    style: _bodyStyle,
                  ),
                  if (chlorophyllPeriodLabel == null)
                    const Text(
                      'Urutan ekspor, bukan waktu pengamatan.',
                      style: _captionStyle,
                    ),
                  Slider(
                    key: const Key('chlorophyll-entry-slider'),
                    value: chlorophyllEntry.toDouble(),
                    min: 1,
                    max: chlorophyllEntryCount.toDouble(),
                    divisions: chlorophyllEntryCount - 1,
                    label: chlorophyllPeriodLabel ?? '$chlorophyllEntry',
                    onChanged: (value) =>
                        onChlorophyllEntryChanged(value.round()),
                  ),
                ],
                if (chlorophyllLoading || loading)
                  const _InlineStatus(label: 'Memuat data klorofil-a…'),
              ],
              if ((chlorophyllLoading || loading) &&
                  scalarLayer != MarineScalarLayer.chlorophyll)
                const _InlineStatus(label: 'Memuat lapisan…'),
              if (error != null) _ErrorRetry(error: error!, onRetry: onRetry),
              const Divider(height: 24),
              const Text('Lapisan kategori', style: _sectionStyle),
              _switch('Coral (kode sumber)', showCoral, onCoralChanged),
              _switch('Mangrove', showMangrove, onMangroveChanged),
              _switch('Grid 500 m', showGrid, onGridChanged),
              const SizedBox(height: 12),
              Text(
                'Opasitas overlay ${(opacity * 100).round()}%',
                style: _sectionStyle,
              ),
              Slider(
                key: const Key('marine-opacity-slider'),
                value: opacity,
                min: 0,
                max: 1,
                divisions: 20,
                onChanged: onOpacityChanged,
              ),
              const SizedBox(height: 6),
              const Text('Rentang nilai numerik', style: _sectionStyle),
              const SizedBox(height: 8),
              _legend('Ikan', '1–100', const [
                Color(0xFFFFFFCC),
                Color(0xFF006837),
              ]),
              _legend('Suhu laut (nilai)', '27.964–30.391', const [
                Color(0xFF2166AC),
                Color(0xFFB2182B),
              ]),
              _legend('Kedalaman', '18–5000', const [
                Color(0xFFDEEBF7),
                Color(0xFF08306B),
              ]),
              _legend('Klorofil-a', '0.0998–5.1405', const [
                Color(0xFFFFFFCC),
                Color(0xFF004529),
              ]),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _switch(String title, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(title),
        value: value,
        activeTrackColor: ReefishColors.primaryAction,
        onChanged: onChanged,
      );

  Widget _legend(String label, String range, List<Color> colors) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(child: Text(label, style: _bodyStyle)),
        Text(range, style: _captionStyle),
        const SizedBox(width: 10),
        Container(
          width: 54,
          height: 10,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(colors: colors),
          ),
        ),
      ],
    ),
  );
}

class _InlineStatus extends StatelessWidget {
  const _InlineStatus({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: _bodyStyle)),
      ],
    ),
  );
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Text(error, style: const TextStyle(color: Color(0xFF9D332B))),
      ),
      TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
    ],
  );
}

const _titleStyle = TextStyle(
  fontSize: 21,
  fontWeight: FontWeight.w700,
  color: ReefishColors.textPrimary,
);
const _sectionStyle = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w600,
  color: ReefishColors.textPrimary,
);
const _bodyStyle = TextStyle(fontSize: 14, color: ReefishColors.textPrimary);
const _captionStyle = TextStyle(
  fontSize: 12,
  color: ReefishColors.textSecondary,
);
