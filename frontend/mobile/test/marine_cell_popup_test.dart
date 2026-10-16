import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/map/domain/geo_point.dart';
import 'package:reefish_mobile/src/map/domain/grid_cell.dart';
import 'package:reefish_mobile/src/map/domain/marine_data.dart';
import 'package:reefish_mobile/src/map/presentation/widgets/marine_cell_detail_sheet.dart';

const _grid = GridCell(
  row: 18134,
  col: 1370,
  id: 'tp-id-utm49s-500m:v2:rp18134:cp1370',
  code: 'TP1-popup-cell',
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

Widget _popup({
  required MarineCell cell,
  required Future<Map<int, double?>> Function() load,
  VoidCallback? onClose,
}) => MaterialApp(
  home: MediaQuery(
    data: const MediaQueryData(
      size: Size(360, 640),
      textScaler: TextScaler.linear(1.3),
    ),
    child: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 328,
          height: 200,
          child: MarineCellDetailSheet(
            gridCell: _grid,
            cell: cell,
            coralFeatures: const [],
            mangroveFeatures: const [],
            loadChlorophyllEntries: load,
            policyStatus: 'Terbuka',
            popup: true,
            onClose: onClose,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('popup fits its bounds and scrolls through all metadata', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _popup(
        cell: _cell('cell-a'),
        load: () async => {
          for (var entry = 1; entry <= 24; entry++) entry: entry.toDouble(),
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(MarineCellDetailSheet)),
      const Size(328, 200),
    );
    expect(find.text('TP1-popup-cell · petak 500 m'), findsOneWidget);
    expect(find.text('Ringkasan parameter'), findsOneWidget);
    expect(find.text('Identitas petak'), findsNothing);
    for (
      var attempt = 0;
      attempt < 20 &&
          find.text('Semua urutan ekspor (1–24)').evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(
        find.byKey(const Key('marine-cell-details-scroll')),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
    }
    await tester.pumpAndSettle();
    expect(find.text('Semua urutan ekspor (1–24)'), findsOneWidget);
    await tester.ensureVisible(find.text('Semua urutan ekspor (1–24)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Semua urutan ekspor (1–24)'));
    await tester.pumpAndSettle();
    expect(find.text('Urutan 24'), findsOneWidget);
    for (
      var attempt = 0;
      attempt < 20 && find.text('Mangrove').evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(
        find.byKey(const Key('marine-cell-details-scroll')),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
    }
    expect(find.text('Mangrove'), findsOneWidget);
    for (
      var attempt = 0;
      attempt < 20 &&
          find.textContaining('bukan penilaian kesehatan').evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(
        find.byKey(const Key('marine-cell-details-scroll')),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('bukan penilaian kesehatan'), findsOneWidget);
  });

  testWidgets('close callback runs without popping the containing route', (
    tester,
  ) async {
    var closed = false;
    await tester.pumpWidget(
      _popup(
        cell: _cell('cell-a'),
        load: () async => const {},
        onClose: () => closed = true,
      ),
    );
    await tester.tap(find.byTooltip('Tutup detail petak'));
    await tester.pump();
    expect(closed, isTrue);
    expect(find.byType(MarineCellDetailSheet), findsOneWidget);
  });

  testWidgets('late chlorophyll result for prior cell is ignored', (
    tester,
  ) async {
    final oldLoad = Completer<Map<int, double?>>();
    MarineCell current = _cell('cell-a');
    Widget build() => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(360, 640)),
        child: Scaffold(
          body: SizedBox(
            width: 328,
            height: 200,
            child: MarineCellDetailSheet(
              gridCell: _grid,
              cell: current,
              coralFeatures: const [],
              mangroveFeatures: const [],
              loadChlorophyllEntries: () => current.cellId == 'cell-a'
                  ? oldLoad.future
                  : Future.value({1: 8.0}),
              policyStatus: 'Terbuka',
              popup: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(build());
    current = _cell('cell-b');
    await tester.pumpWidget(build());
    await tester.pump();
    oldLoad.complete({1: 3.0});
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('marine-cell-details-scroll')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    expect(find.text('8.0'), findsOneWidget);
    expect(find.text('3.0'), findsNothing);
  });
}
