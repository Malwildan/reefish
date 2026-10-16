import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/map/domain/geo_point.dart';
import 'package:reefish_mobile/src/map/domain/grid_cell.dart';
import 'package:reefish_mobile/src/map/domain/grid_policy.dart';
import 'package:reefish_mobile/src/map/domain/marine_data.dart';
import 'package:reefish_mobile/src/map/presentation/widgets/marine_cell_summary_popup.dart';
import 'package:reefish_mobile/src/theme/reef_fish_theme.dart';

const _grid = GridCell(
  row: 18134,
  col: 1370,
  id: 'internal-long-grid-id',
  code: 'internal-long-grid-code',
  polygon: [],
  center: GeoPoint(latitude: -8.433, longitude: 112.683),
);

MarineCell _cell(String id) => MarineCell(
  gridX: 1,
  gridY: 2,
  point: const GeoPoint(latitude: -8.4331, longitude: 112.6831),
  fish: id == 'cell-a' ? 44 : 52,
  temperature: 29.12,
  depth: 870,
  cellId: id,
);

Widget _host({
  required Widget child,
  Size size = const Size(360, 640),
  double textScale = 1,
  double popupWidth = 320,
  double popupHeight = 320,
}) => MaterialApp(
  theme: ReefishTheme.light,
  home: MediaQuery(
    data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: popupWidth, height: popupHeight, child: child),
      ),
    ),
  ),
);

MarineCellSummaryPopup _popup({
  MarineCell? cell,
  Future<Map<int, double?>> Function()? load,
  VoidCallback? onClose,
  VoidCallback? onDetails,
  GridCell gridCell = _grid,
}) => MarineCellSummaryPopup(
  gridCell: gridCell,
  cell: cell,
  coralCount: 2,
  mangroveCount: 1,
  loadChlorophyllEntries: load ?? () async => {1: 4.2},
  access: GridAccess.unknown,
  policyStatus: 'Status kebijakan lengkap',
  onClose: onClose ?? () {},
  onDetails: onDetails ?? () {},
);

Finder _semanticsLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

void main() {
  testWidgets('compact popup keeps six metrics reachable at narrow bounds', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        size: const Size(320, 600),
        textScale: 1.3,
        popupWidth: 288,
        popupHeight: 250,
        child: _popup(cell: _cell('cell-a')),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(MarineCellSummaryPopup)),
      const Size(288, 250),
    );
    expect(find.text('Petak R18134 · C1370'), findsOneWidget);
    expect(find.text('internal-long-grid-id'), findsNothing);
    expect(find.text('500 m'), findsOneWidget);
    expect(
      find.text('Nilai sumber · satuan & waktu belum tersedia.'),
      findsOneWidget,
    );
    expect(find.text('Detail data'), findsOneWidget);

    for (final label in [
      'Ikan',
      'Suhu laut',
      'Kedalaman',
      'Klorofil',
      'Coral',
      'Mangrove',
    ]) {
      final finder = find.text(label);
      if (finder.evaluate().isEmpty ||
          !tester
              .getRect(finder.first)
              .overlaps(
                tester.getRect(
                  find.byKey(const Key('marine-cell-summary-scroll')),
                ),
              )) {
        await tester.ensureVisible(finder.first);
        await tester.pumpAndSettle();
      }
      expect(finder, findsOneWidget);
    }
    expect(find.text('2 rekaman'), findsOneWidget);
    expect(find.text('1 rekaman'), findsOneWidget);
  });

  testWidgets('close and details use callbacks without route navigation', (
    tester,
  ) async {
    var closed = false;
    var details = false;
    await tester.pumpWidget(
      _host(
        child: _popup(
          cell: _cell('cell-a'),
          onClose: () => closed = true,
          onDetails: () => details = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const Key('marine-summary-close'))).width,
      44,
    );
    await tester.tap(find.byKey(const Key('marine-summary-close')));
    await tester.tap(find.byKey(const Key('marine-summary-details')));
    expect(closed, isTrue);
    expect(details, isTrue);
    expect(find.byType(MarineCellSummaryPopup), findsOneWidget);
  });

  testWidgets(
    'late chlorophyll result is ignored after selected cell becomes null',
    (tester) async {
      final pending = Completer<Map<int, double?>>();
      MarineCell? current = _cell('cell-a');
      Widget build() => _host(
        child: _popup(cell: current, load: () => pending.future),
      );
      await tester.pumpWidget(build());
      current = null;
      await tester.pumpWidget(build());
      await tester.pump();
      pending.complete({1: 987.6});
      await tester.pumpAndSettle();

      expect(find.text('987.6'), findsNothing);
      expect(find.text('—'), findsNWidgets(4));
      expect(_semanticsLabel('Ikan tidak tersedia'), findsOneWidget);
    },
  );

  testWidgets(
    'chlorophyll load error can retry and missing values stay unavailable',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        _host(
          child: _popup(
            cell: _cell('cell-a'),
            load: () async {
              attempts++;
              if (attempts == 1) throw StateError('offline');
              return {1: null};
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Gagal dimuat'), findsOneWidget);
      expect(find.text('0.0'), findsNothing);
      await tester.tap(
        find.byKey(const Key('marine-summary-chlorophyll-retry')),
      );
      await tester.pumpAndSettle();

      expect(attempts, 2);
      expect(find.text('Gagal dimuat'), findsNothing);
      expect(_semanticsLabel('Klorofil tidak tersedia'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    },
  );

  testWidgets('missing marine cell does not fabricate numeric metrics', (
    tester,
  ) async {
    await tester.pumpWidget(_host(child: _popup()));
    await tester.pumpAndSettle();

    expect(find.text('—'), findsNWidgets(4));
    expect(_semanticsLabel('Ikan tidak tersedia'), findsOneWidget);
    expect(_semanticsLabel('Suhu laut tidak tersedia'), findsOneWidget);
    expect(_semanticsLabel('Kedalaman tidak tersedia'), findsOneWidget);
    expect(find.text('2 rekaman'), findsOneWidget);
    expect(find.text('1 rekaman'), findsOneWidget);
    expect(find.text('0 rekaman'), findsNothing);
  });
}
