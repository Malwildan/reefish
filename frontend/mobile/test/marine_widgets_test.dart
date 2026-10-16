import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reefish_mobile/src/map/domain/geo_point.dart';
import 'package:reefish_mobile/src/map/domain/grid_cell.dart';
import 'package:reefish_mobile/src/map/domain/marine_data.dart';
import 'package:reefish_mobile/src/map/presentation/widgets/marine_cell_detail_sheet.dart';
import 'package:reefish_mobile/src/map/presentation/widgets/marine_layer_sheet.dart';

const _gridCell = GridCell(
  row: 18134,
  col: 1370,
  id: 'tp-id-utm49s-500m:v2:rp18134:cp1370',
  code: 'TP1-test-cell',
  polygon: [],
  center: GeoPoint(latitude: -8.433, longitude: 112.683),
);

const _marineCell = MarineCell(
  gridX: 1,
  gridY: 2,
  point: GeoPoint(latitude: -8.4331, longitude: 112.6831),
  fish: 44,
  temperature: 29.12,
  depth: 870,
  cellId: 'tp-id-utm49s-500m:v2:rp18134:cp1370',
);

Widget _host(Widget child, {double textScale = 1}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(360, 640),
      textScaler: TextScaler.linear(textScale),
    ),
    child: Scaffold(body: child),
  ),
);

void _sizeViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 640);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'layer controls keep grid independent and expose scalar choices',
    (tester) async {
      _sizeViewport(tester);
      MarineScalarLayer? selected;
      bool? gridValue;
      await tester.pumpWidget(
        _host(
          MarineLayerSheet(
            scalarLayer: MarineScalarLayer.none,
            showCoral: false,
            showMangrove: false,
            showGrid: true,
            opacity: .6,
            chlorophyllEntry: 1,
            chlorophyllLoading: false,
            error: null,
            onScalarChanged: (value) => selected = value,
            onCoralChanged: (_) {},
            onMangroveChanged: (_) {},
            onGridChanged: (value) => gridValue = value,
            onOpacityChanged: (_) {},
            onChlorophyllEntryChanged: (_) {},
            onRetry: () {},
          ),
        ),
      );

      await tester.scrollUntilVisible(
        find.text('Ikan'),
        -240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Ikan'), findsOneWidget);
      expect(find.text('Suhu laut (nilai)'), findsOneWidget);
      expect(find.text('Kedalaman'), findsOneWidget);
      expect(find.text('Klorofil-a'), findsOneWidget);
      expect(find.text('Grid 500 m'), findsOneWidget);
      await tester.tap(find.text('Ikan').first);
      expect(selected, MarineScalarLayer.fish);
      await tester.tap(find.text('Grid 500 m'));
      expect(gridValue, isFalse);
    },
  );

  testWidgets(
    'cell detail always shows all parameter categories and source metadata',
    (tester) async {
      _sizeViewport(tester);
      await tester.pumpWidget(
        _host(
          MarineCellDetailSheet(
            gridCell: _gridCell,
            cell: _marineCell,
            coralFeatures: const [
              MarineAreaFeature(
                id: 'coral-1',
                polygons: [],
                properties: {'value': 1, 'source_feature_index': 7},
              ),
            ],
            mangroveFeatures: const [
              MarineAreaFeature(
                id: 'mangrove-1',
                polygons: [],
                properties: {'year': 2023, 'gridcode': 2, 'area_ha': 4.5},
              ),
            ],
            loadChlorophyllEntries: () async => {1: 1.23, 2: null},
            policyStatus: 'belum diketahui',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const Key('marine-cell-details-scroll')),
        const Offset(0, -280),
      );
      await tester.pumpAndSettle();
      final summary = find.byKey(const Key('marine-parameter-summary'));
      expect(summary, findsOneWidget);
      for (final label in [
        'Ikan',
        'Suhu laut (nilai)',
        'Kedalaman',
        'Klorofil-a · urutan 1',
        'Coral · fitur sumber beririsan',
        'Mangrove · fitur sumber beririsan',
      ]) {
        expect(
          find.descendant(of: summary, matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(of: summary, matching: find.text('44.0')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summary, matching: find.text('29.12')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summary, matching: find.text('870.0')),
        findsOneWidget,
      );
      for (
        var i = 0;
        i < 10 &&
            find.text('1 · makna kode belum diketahui').evaluate().isEmpty;
        i++
      ) {
        await tester.drag(
          find.byKey(const Key('marine-cell-details-scroll')),
          const Offset(0, -280),
        );
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('1 · makna kode belum diketahui'));
      await tester.pump();
      expect(find.text('1 · makna kode belum diketahui'), findsOneWidget);
      expect(find.text('Indeks fitur sumber'), findsOneWidget);
      expect(find.text('Tahun sumber'), findsOneWidget);
      expect(find.textContaining('seluruh poligon'), findsOneWidget);
      expect(find.textContaining('belum diketahui'), findsWidgets);
    },
  );

  testWidgets(
    'missing cell does not request chlorophyll or invent zero values',
    (tester) async {
      _sizeViewport(tester);
      var calls = 0;
      await tester.pumpWidget(
        _host(
          MarineCellDetailSheet(
            gridCell: _gridCell,
            cell: null,
            coralFeatures: const [
              MarineAreaFeature(
                id: 'coral-no-csv',
                polygons: [],
                properties: {'value': 7},
              ),
            ],
            mangroveFeatures: const [],
            loadChlorophyllEntries: () async {
              calls++;
              return {};
            },
            policyStatus: 'status diketahui',
          ),
        ),
      );
      await tester.pump();
      expect(calls, 0);
      final summary = find.byKey(const Key('marine-parameter-summary'));
      for (final label in [
        'Ikan',
        'Suhu laut (nilai)',
        'Kedalaman',
        'Klorofil-a · urutan 1',
        'Coral · fitur sumber beririsan',
        'Mangrove · fitur sumber beririsan',
      ]) {
        expect(
          find.descendant(of: summary, matching: find.text(label)),
          findsOneWidget,
        );
      }
      for (
        var i = 0;
        i < 8 &&
            find.text('Tidak ada data untuk petak ini.').evaluate().isEmpty;
        i++
      ) {
        await tester.drag(
          find.byKey(const Key('marine-cell-details-scroll')),
          const Offset(0, -240),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('Tidak ada data untuk petak ini.'), findsOneWidget);
      for (
        var i = 0;
        i < 10 &&
            find.text('7 · makna kode belum diketahui').evaluate().isEmpty;
        i++
      ) {
        await tester.drag(
          find.byKey(const Key('marine-cell-details-scroll')),
          const Offset(0, -280),
        );
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('7 · makna kode belum diketahui'));
      await tester.pump();
      expect(find.text('Coral (kode sumber)'), findsOneWidget);
      expect(find.text('7 · makna kode belum diketahui'), findsOneWidget);
      expect(calls, 0);
    },
  );

  testWidgets(
    'chlorophyll fetch can retry after an error and all 24 entries expand',
    (tester) async {
      _sizeViewport(tester);
      var calls = 0;
      await tester.pumpWidget(
        _host(
          MarineCellDetailSheet(
            gridCell: _gridCell,
            cell: _marineCell,
            coralFeatures: const [],
            mangroveFeatures: const [],
            loadChlorophyllEntries: () async {
              calls++;
              if (calls == 1) throw StateError('offline');
              return {for (var i = 1; i <= 24; i++) i: i.toDouble()};
            },
            policyStatus: 'akses belum diketahui',
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 6 && find.text('Coba lagi').evaluate().isEmpty; i++) {
        await tester.drag(
          find.byKey(const Key('marine-cell-details-scroll')),
          const Offset(0, -320),
        );
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('offline'), findsOneWidget);
      await tester.ensureVisible(find.text('Coba lagi'));
      await tester.pump();
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      for (
        var i = 0;
        i < 6 && find.text('Semua urutan ekspor (1–24)').evaluate().isEmpty;
        i++
      ) {
        await tester.drag(
          find.byKey(const Key('marine-cell-details-scroll')),
          const Offset(0, -360),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('Semua urutan ekspor (1–24)'), findsOneWidget);
      await tester.ensureVisible(find.text('Semua urutan ekspor (1–24)'));
      await tester.pump();
      await tester.tap(find.text('Semua urutan ekspor (1–24)'));
      await tester.pumpAndSettle();
      expect(find.text('Urutan 1'), findsOneWidget);
      await tester.drag(
        find.byKey(const Key('marine-cell-details-scroll')),
        const Offset(0, -1400),
      );
      await tester.pumpAndSettle();
      expect(find.text('Urutan 24'), findsOneWidget);
    },
  );

  testWidgets('layer and detail sheets scroll at 360x640 with enlarged text', (
    tester,
  ) async {
    _sizeViewport(tester);
    await tester.pumpWidget(
      _host(
        MarineLayerSheet(
          scalarLayer: MarineScalarLayer.chlorophyll,
          showCoral: true,
          showMangrove: true,
          showGrid: true,
          opacity: .7,
          chlorophyllEntry: 12,
          chlorophyllLoading: true,
          error: 'gagal',
          onScalarChanged: (_) {},
          onCoralChanged: (_) {},
          onMangroveChanged: (_) {},
          onGridChanged: (_) {},
          onOpacityChanged: (_) {},
          onChlorophyllEntryChanged: (_) {},
          onRetry: () {},
          loading: true,
        ),
        textScale: 1.3,
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    for (
      var i = 0;
      i < 8 && find.text('Rentang nilai numerik').evaluate().isEmpty;
      i++
    ) {
      await tester.drag(
        find.byKey(const Key('marine-layer-sheet-scroll')),
        const Offset(0, -300),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Rentang nilai numerik'), findsOneWidget);

    final never = Completer<Map<int, double?>>();
    await tester.pumpWidget(
      _host(
        MarineCellDetailSheet(
          gridCell: _gridCell,
          cell: _marineCell,
          coralFeatures: const [],
          mangroveFeatures: const [],
          loadChlorophyllEntries: () => never.future,
          policyStatus: 'belum diketahui',
        ),
        textScale: 1.3,
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byKey(const Key('marine-cell-details-scroll')),
      const Offset(0, -450),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    never.complete({});
    await tester.pumpAndSettle();
  });
}
