import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/reef_fish_theme.dart';
import '../../domain/grid_cell.dart';
import '../../domain/grid_policy.dart';
import '../../domain/marine_data.dart';

/// Compact map popup with a short summary. Complete source metadata belongs in
/// the details view opened by [onDetails].
class MarineCellSummaryPopup extends StatefulWidget {
  const MarineCellSummaryPopup({
    required this.gridCell,
    required this.cell,
    required this.coralCount,
    required this.mangroveCount,
    required this.loadChlorophyllEntries,
    required this.access,
    required this.policyStatus,
    required this.onClose,
    required this.onDetails,
    this.initialChlorophyllEntry = 1,
    super.key,
  }) : assert(initialChlorophyllEntry >= 1 && initialChlorophyllEntry <= 24);

  final GridCell gridCell;
  final MarineCell? cell;
  final int coralCount;
  final int mangroveCount;
  final Future<Map<int, double?>> Function() loadChlorophyllEntries;
  final GridAccess access;
  final String policyStatus;
  final VoidCallback onClose;
  final VoidCallback onDetails;
  final int initialChlorophyllEntry;

  @override
  State<MarineCellSummaryPopup> createState() => _MarineCellSummaryPopupState();
}

class _MarineCellSummaryPopupState extends State<MarineCellSummaryPopup> {
  Map<int, double?>? _chlorophyllEntries;
  Object? _chlorophyllError;
  bool _loadingChlorophyll = false;
  int _requestToken = 0;

  @override
  void initState() {
    super.initState();
    _loadChlorophyll();
  }

  @override
  void didUpdateWidget(covariant MarineCellSummaryPopup oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged =
        oldWidget.cell?.cellId != widget.cell?.cellId ||
        oldWidget.gridCell.id != widget.gridCell.id ||
        oldWidget.initialChlorophyllEntry != widget.initialChlorophyllEntry;
    if (sourceChanged) {
      _chlorophyllEntries = null;
      _chlorophyllError = null;
      _loadingChlorophyll = false;
      _requestToken++;
      _loadChlorophyll();
    }
  }

  Future<void> _loadChlorophyll() async {
    if (widget.cell == null) {
      _requestToken++;
      return;
    }
    final token = ++_requestToken;
    setState(() {
      _loadingChlorophyll = true;
      _chlorophyllError = null;
    });
    try {
      final entries = await widget.loadChlorophyllEntries();
      if (!mounted || token != _requestToken) return;
      setState(() {
        _chlorophyllEntries = entries;
        _loadingChlorophyll = false;
      });
    } catch (error) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _chlorophyllError = error;
        _loadingChlorophyll = false;
      });
    }
  }

  @override
  void dispose() {
    _requestToken++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = math.min(320.0, constraints.maxWidth);
      final height = math.min(
        320.0,
        constraints.maxHeight.isFinite ? constraints.maxHeight : 320.0,
      );
      return SizedBox(
        width: width,
        height: height,
        child: Material(
          color: Colors.white,
          elevation: 8,
          shadowColor: ReefishColors.textPrimary.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _header(),
              Expanded(
                child: SingleChildScrollView(
                  key: const Key('marine-cell-summary-scroll'),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _metricsGrid(),
                      const SizedBox(height: 4),
                      if (widget.cell == null ||
                          (_chlorophyllEntries != null &&
                              _chlorophyllEntries![widget
                                      .initialChlorophyllEntry] ==
                                  null)) ...[
                        const Text(
                          '— berarti nilai tidak tersedia, bukan 0.',
                          key: Key('marine-summary-unavailable-note'),
                          style: TextStyle(
                            color: ReefishColors.textSecondary,
                            fontSize: 11,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 5),
                      ],
                      const Text(
                        'Nilai sumber · satuan & waktu belum tersedia.',
                        key: Key('marine-summary-source-caption'),
                        style: TextStyle(
                          color: ReefishColors.textSecondary,
                          fontSize: 11,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _footer(),
            ],
          ),
        ),
      );
    },
  );

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 9, 6, 1),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Petak R${widget.gridCell.row} · C${widget.gridCell.col}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ReefishColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 1),
              const Text(
                '500 m',
                style: TextStyle(
                  color: ReefishColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            key: const Key('marine-summary-close'),
            tooltip: 'Tutup ringkasan petak',
            onPressed: widget.onClose,
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.close, size: 20),
            color: ReefishColors.textSecondary,
          ),
        ),
      ],
    ),
  );

  Widget _metricsGrid() {
    final selected = widget.cell;
    final chlorophyllValue =
        _chlorophyllEntries?[widget.initialChlorophyllEntry];
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _metric('Ikan', selected?.fish)),
            const _MetricDivider(),
            Expanded(child: _metric('Suhu laut', selected?.temperature)),
          ],
        ),
        const _RowDivider(),
        Row(
          children: [
            Expanded(child: _metric('Kedalaman', selected?.depth)),
            const _MetricDivider(),
            Expanded(
              child: _metric(
                'Klorofil',
                chlorophyllValue,
                loading: _loadingChlorophyll,
                error: _chlorophyllError != null,
                onRetry: _chlorophyllError == null ? null : _loadChlorophyll,
              ),
            ),
          ],
        ),
        const _RowDivider(),
        Row(
          children: [
            Expanded(child: _countMetric('Coral', widget.coralCount)),
            const _MetricDivider(),
            Expanded(child: _countMetric('Mangrove', widget.mangroveCount)),
          ],
        ),
      ],
    );
  }

  Widget _metric(
    String label,
    double? value, {
    bool loading = false,
    bool error = false,
    VoidCallback? onRetry,
  }) {
    final unavailable = value == null;
    final text = unavailable ? '—' : value.toString();
    return Semantics(
      container: true,
      label: unavailable ? '$label tidak tersedia' : '$label $text',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ReefishColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Flexible(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: unavailable
                          ? ReefishColors.textSecondary
                          : ReefishColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ),
                if (loading) ...[
                  const SizedBox(width: 6),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.7),
                  ),
                ],
                if (onRetry != null)
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: IconButton(
                      key: const Key('marine-summary-chlorophyll-retry'),
                      tooltip: 'Coba muat klorofil lagi',
                      visualDensity: VisualDensity.compact,
                      onPressed: onRetry,
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.refresh, size: 17),
                      color: ReefishColors.primaryAction,
                    ),
                  ),
              ],
            ),
            if (error)
              const Text(
                'Gagal dimuat',
                style: TextStyle(
                  color: ReefishColors.signupAccent,
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _countMetric(String label, int count) => Semantics(
    container: true,
    label: '$label $count rekaman',
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: ReefishColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$count rekaman',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: ReefishColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _footer() {
    final (status, color) = switch (widget.access) {
      GridAccess.unlocked => ('Tanpa lock', ReefishColors.reef),
      GridAccess.locked => ('Terkunci', ReefishColors.signupAccent),
      GridAccess.unknown => ('Belum diverifikasi', ReefishColors.textSecondary),
    };
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: ReefishColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: widget.policyStatus,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  container: true,
                  label: 'Akses mancing: $status. ${widget.policyStatus}',
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 148),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 132, minWidth: 44),
            child: SizedBox(
              height: 44,
              child: TextButton.icon(
                key: const Key('marine-summary-details'),
                onPressed: widget.onDetails,
                style: TextButton.styleFrom(
                  foregroundColor: ReefishColors.primaryAction,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  minimumSize: const Size(44, 44),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.chevron_right, size: 20),
                label: const Text(
                  'Detail data',
                  maxLines: 1,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 46, color: ReefishColors.border);
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, thickness: 1, color: ReefishColors.border);
}
