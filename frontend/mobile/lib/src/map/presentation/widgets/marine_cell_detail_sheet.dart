import 'package:flutter/material.dart';

import '../../../theme/reef_fish_theme.dart';
import '../../domain/geo_point.dart';
import '../../domain/grid_cell.dart';
import '../../domain/marine_data.dart';

/// Metadata for a tapped 500 m grid cell. All available parameters are shown
/// regardless of which map overlays are enabled.
class MarineCellDetailSheet extends StatefulWidget {
  const MarineCellDetailSheet({
    required this.gridCell,
    required this.cell,
    required this.coralFeatures,
    required this.mangroveFeatures,
    required this.loadChlorophyllEntries,
    required this.policyStatus,
    this.initialChlorophyllEntry = 1,
    this.onInspectEntry,
    this.popup = false,
    this.onClose,
    super.key,
  }) : assert(initialChlorophyllEntry >= 1 && initialChlorophyllEntry <= 24);

  final GridCell gridCell;
  final MarineCell? cell;
  final List<MarineAreaFeature> coralFeatures;
  final List<MarineAreaFeature> mangroveFeatures;
  final Future<Map<int, double?>> Function() loadChlorophyllEntries;
  final int initialChlorophyllEntry;
  final String policyStatus;
  final ValueChanged<int>? onInspectEntry;
  final bool popup;
  final VoidCallback? onClose;

  @override
  State<MarineCellDetailSheet> createState() => _MarineCellDetailSheetState();
}

class _MarineCellDetailSheetState extends State<MarineCellDetailSheet> {
  late int _selectedEntry;
  Map<int, double?>? _chlorophyll;
  Object? _chlorophyllError;
  bool _loading = false;
  int _requestToken = 0;

  @override
  void initState() {
    super.initState();
    _selectedEntry = widget.initialChlorophyllEntry;
    if (widget.cell != null) _loadChlorophyll();
  }

  @override
  void didUpdateWidget(covariant MarineCellDetailSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cell?.cellId != widget.cell?.cellId) {
      _chlorophyll = null;
      _chlorophyllError = null;
      if (widget.cell != null) _loadChlorophyll();
    }
  }

  Future<void> _loadChlorophyll() async {
    if (widget.cell == null) return;
    final token = ++_requestToken;
    setState(() {
      _loading = true;
      _chlorophyllError = null;
    });
    try {
      final values = await widget.loadChlorophyllEntries();
      if (!mounted || token != _requestToken) return;
      setState(() {
        _chlorophyll = values;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _chlorophyllError = error;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _requestToken++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * .88;
    final cell = widget.cell;
    final content = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Material(
        color: Colors.white,
        borderRadius: widget.popup
            ? BorderRadius.circular(14)
            : const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: ListView(
                key: const Key('marine-cell-details-scroll'),
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                children: [
                  _summary(cell),
                  const SizedBox(height: 14),
                  _metadataBlock('Identitas petak', [
                    _row('ID petak', widget.gridCell.id),
                    _row('Kode petak', widget.gridCell.code),
                    _row(
                      'Koordinat pusat',
                      _coordinate(widget.gridCell.center),
                    ),
                    _row('Grid', '500 m · EPSG:32749'),
                    _row('Kebijakan akses', widget.policyStatus),
                  ]),
                  if (cell == null) ...[
                    const SizedBox(height: 12),
                    const _Notice('Tidak ada data untuk petak ini.'),
                    const SizedBox(height: 8),
                    const Text(
                      'Nilai tidak tersedia; nilai kosong tidak ditafsirkan sebagai nol atau sebagai ketiadaan objek.',
                      style: _captionStyle,
                    ),
                    const SizedBox(height: 16),
                    const Text('Parameter laut', style: _sectionStyle),
                    _parameterUnavailable('Ikan', 'potensi_ikan.csv', '1–100'),
                    _parameterUnavailable(
                      'Suhu laut (nilai)',
                      'suhu_laut.csv',
                      '27.964–30.391',
                    ),
                    _parameterUnavailable(
                      'Kedalaman',
                      'kedalaman_laut.csv',
                      '18–5000',
                    ),
                    _chlorophyllUnavailable(),
                  ] else ...[
                    const SizedBox(height: 16),
                    _metadataBlock('Pengamatan petak', [
                      _row('ID data', cell.cellId),
                      _row('Koordinat data', _coordinate(cell.point)),
                    ]),
                    const SizedBox(height: 16),
                    const Text('Parameter laut', style: _sectionStyle),
                    const SizedBox(height: 6),
                    _parameter('Ikan', cell.fish, '1–100', 'potensi_ikan.csv'),
                    _parameter(
                      'Suhu laut (nilai)',
                      cell.temperature,
                      '27.964–30.391',
                      'suhu_laut.csv',
                    ),
                    _parameter(
                      'Kedalaman',
                      cell.depth,
                      '18–5000',
                      'kedalaman_laut.csv',
                    ),
                    _chlorophyllSection(),
                  ],
                  const SizedBox(height: 16),
                  _areaSection(
                    'Coral (kode sumber)',
                    widget.coralFeatures,
                    isCoral: true,
                  ),
                  const SizedBox(height: 14),
                  _areaSection('Mangrove', widget.mangroveFeatures),
                  const SizedBox(height: 12),
                  const _Notice(
                    'Data dan fitur yang tercantum adalah referensi sumber. Ini bukan penilaian kesehatan, keamanan, legalitas, atau cakupan seluruh petak.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return widget.popup ? content : SafeArea(top: false, child: content);
  }

  Widget _header(BuildContext context) => Container(
    width: double.infinity,
    color: widget.popup ? Colors.white : ReefishColors.primaryAction,
    padding: widget.popup
        ? const EdgeInsets.fromLTRB(12, 2, 4, 2)
        : const EdgeInsets.fromLTRB(18, 12, 10, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Detail petak',
                style: TextStyle(
                  color: widget.popup
                      ? ReefishColors.primaryAction
                      : Colors.white,
                  fontSize: widget.popup ? 16 : 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Tutup detail petak',
              onPressed: () {
                if (widget.onClose case final callback?) {
                  callback();
                } else {
                  Navigator.of(context).maybePop();
                }
              },
              color: widget.popup ? ReefishColors.primaryAction : Colors.white,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        Text(
          '${widget.gridCell.code} · petak 500 m',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: widget.popup ? ReefishColors.textSecondary : Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );

  Widget _metadataBlock(String title, List<Widget> rows) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: _sectionStyle),
      const SizedBox(height: 6),
      ...rows,
    ],
  );

  Widget _summary(MarineCell? cell) {
    final chlorophyllValue = _chlorophyll?[_selectedEntry];
    final chlorophyllText = _loading
        ? 'Memuat…'
        : _chlorophyllError != null
        ? 'Gagal dimuat'
        : _chlorophyll == null || chlorophyllValue == null
        ? 'Tidak tersedia'
        : _number(chlorophyllValue);
    return _categoryCard(
      key: const Key('marine-parameter-summary'),
      label: 'Ringkasan parameter',
      content: [
        _summaryRow(
          'Ikan',
          cell == null ? 'Tidak tersedia' : _number(cell.fish),
        ),
        _summaryRow(
          'Suhu laut (nilai)',
          cell == null ? 'Tidak tersedia' : _number(cell.temperature),
        ),
        _summaryRow(
          'Kedalaman',
          cell == null ? 'Tidak tersedia' : _number(cell.depth),
        ),
        _summaryRow('Klorofil-a · urutan $_selectedEntry', chlorophyllText),
        _summaryRow(
          'Coral · fitur sumber beririsan',
          '${widget.coralFeatures.length} rekaman',
        ),
        _summaryRow(
          'Mangrove · fitur sumber beririsan',
          '${widget.mangroveFeatures.length} rekaman',
        ),
        const _Caption(
          'Satuan dan waktu pengamatan belum diketahui. Jumlah fitur adalah rekaman sumber yang beririsan, bukan cakupan petak atau klaim ketiadaan.',
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: _bodyStyle)),
        const SizedBox(width: 10),
        Flexible(
          child: Text(value, textAlign: TextAlign.end, style: _bodyStyle),
        ),
      ],
    ),
  );

  Widget _row(String key, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 128, child: Text(key, style: _captionStyle)),
        const SizedBox(width: 8),
        Expanded(child: SelectableText(value, style: _bodyStyle)),
      ],
    ),
  );

  Widget _parameter(
    String label,
    double value,
    String range,
    String filename,
  ) => _categoryCard(
    key: ValueKey('marine-category-$label'),
    label: label,
    content: [
      _row('Nilai', _number(value)),
      _row('Rentang visualisasi', range),
      _sourceUnknown(filename),
    ],
  );

  Widget _parameterUnavailable(String label, String filename, String range) =>
      _categoryCard(
        key: ValueKey('marine-category-$label'),
        label: label,
        content: [
          _row('Nilai', 'Tidak tersedia'),
          _row('Rentang visualisasi', range),
          _sourceUnknown(filename),
        ],
      );

  Widget _chlorophyllUnavailable() => _categoryCard(
    key: const ValueKey('marine-category-Klorofil-a'),
    label: 'Klorofil-a',
    content: [
      _row('Nilai', 'Tidak tersedia'),
      _row('Rentang visualisasi', '0.0998–5.1405'),
      const _Caption('Urutan ekspor, bukan waktu pengamatan.'),
      _sourceUnknown(_chlorophyllFilename(_selectedEntry)),
      const _Caption(
        'Urutan 1–24 tidak dimuat karena data CSV petak tidak tersedia.',
      ),
    ],
  );

  Widget _chlorophyllSection() {
    final value = _chlorophyll?[_selectedEntry];
    return _categoryCard(
      key: const ValueKey('marine-category-Klorofil-a'),
      label: 'Klorofil-a',
      content: [
        _row('Urutan ekspor', '$_selectedEntry dari 24'),
        _row('Nilai', value == null ? 'Tidak tersedia' : _number(value)),
        const _Caption('Urutan ekspor, bukan waktu pengamatan.'),
        _sourceUnknown(_chlorophyllFilename(_selectedEntry)),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('Memuat 24 urutan…'),
              ],
            ),
          ),
        if (_chlorophyllError != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  'Gagal memuat data: $_chlorophyllError',
                  style: _errorStyle,
                ),
              ),
              TextButton(
                onPressed: _loadChlorophyll,
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        if (_chlorophyll == null && !_loading && _chlorophyllError == null)
          const _Caption('Nilai belum dimuat.'),
        if (_chlorophyll != null)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(left: 8, bottom: 8),
            title: const Text('Semua urutan ekspor (1–24)', style: _bodyStyle),
            children: [
              for (var entry = 1; entry <= 24; entry++)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Urutan $entry'),
                  subtitle: Text(
                    _chlorophyll!.containsKey(entry)
                        ? (_chlorophyll![entry] == null
                              ? 'Tidak tersedia'
                              : _number(_chlorophyll![entry]!))
                        : 'Tidak tersedia',
                  ),
                  leading: SizedBox(
                    width: 110,
                    child: Text(
                      _chlorophyllFilename(entry),
                      style: _captionStyle,
                    ),
                  ),
                  trailing: entry == _selectedEntry
                      ? const Icon(
                          Icons.check,
                          color: ReefishColors.primaryAction,
                        )
                      : null,
                  onTap: () {
                    setState(() => _selectedEntry = entry);
                    widget.onInspectEntry?.call(entry);
                  },
                ),
            ],
          ),
      ],
    );
  }

  Widget _areaSection(
    String title,
    List<MarineAreaFeature> features, {
    bool isCoral = false,
  }) {
    final cards = <Widget>[];
    if (features.isEmpty) {
      cards.add(
        const _Caption(
          'Tidak ada fitur sumber yang tercatat beririsan untuk petak ini. Ini tidak menyatakan ketiadaan objek.',
        ),
      );
    } else {
      for (final feature in features) {
        final entries = feature.properties.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        cards.addAll([
          _row('ID fitur', feature.id),
          for (final entry in entries)
            _row(
              _propertyLabel(entry.key, isCoral),
              _propertyValue(entry.key, entry.value, isCoral),
            ),
          if (!isCoral)
            const _Caption(
              'Nilai luas merujuk ke seluruh poligon, bukan cakupan di dalam petak.',
            ),
          const _Caption(
            'Penyedia aktual, satuan, dan waktu: belum diketahui.',
          ),
          if (feature != features.last) const Divider(height: 16),
        ]);
      }
    }
    return _categoryCard(
      key: ValueKey('marine-category-$title'),
      label: title,
      content: cards,
    );
  }

  Widget _categoryCard({
    Key? key,
    required String label,
    required List<Widget> content,
  }) => Container(
    key: key,
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: ReefishColors.canvas,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: ReefishColors.border),
    ),
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _cardTitleStyle),
          const SizedBox(height: 5),
          ...content,
        ],
      ),
    ),
  );

  Widget _sourceUnknown(String filename) => _Caption(
    'Berkas: $filename · penyedia aktual, satuan, dan waktu: belum diketahui.',
  );

  String _propertyLabel(String key, bool isCoral) {
    if (isCoral && (key == 'code' || key == 'value')) {
      return 'Kode sumber (mentah)';
    }
    if (key == 'source_feature_index') {
      return 'Indeks fitur sumber';
    }
    if (key == 'gridcode') {
      return 'Kode grid sumber';
    }
    if (key.toLowerCase().contains('area')) {
      return '$key (luas poligon)';
    }
    if (key.toLowerCase() == 'year') {
      return 'Tahun sumber';
    }
    return key.replaceAll('_', ' ');
  }

  String _propertyValue(String key, Object? value, bool isCoral) {
    if (isCoral && (key == 'code' || key == 'value') && value != null) {
      return '${value.toString()} · makna kode belum diketahui';
    }
    return _readable(value);
  }

  String _coordinate(GeoPoint point) =>
      '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';

  String _number(double value) => value.toString();
}

String _chlorophyllFilename(int entry) =>
    'klorofil_a/blok_${entry.toString().padLeft(2, '0')}.csv';

String _readable(Object? value) {
  if (value == null) {
    return 'Tidak tersedia';
  }
  if (value is num || value is String || value is bool) {
    return value.toString();
  }
  if (value is List) {
    return value.map(_readable).join(', ');
  }
  if (value is Map) {
    return value.entries
        .map((entry) => '${entry.key}: ${_readable(entry.value)}')
        .join(' · ');
  }
  return value.toString();
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: ReefishColors.field,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text, style: _bodyStyle),
  );
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Text(text, style: _captionStyle),
  );
}

const _sectionStyle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w700,
  color: ReefishColors.textPrimary,
);
const _cardTitleStyle = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w600,
  color: ReefishColors.primaryAction,
);
const _bodyStyle = TextStyle(fontSize: 14, color: ReefishColors.textPrimary);
const _captionStyle = TextStyle(
  fontSize: 12,
  color: ReefishColors.textSecondary,
);
const _errorStyle = TextStyle(fontSize: 13, color: Color(0xFF9D332B));
