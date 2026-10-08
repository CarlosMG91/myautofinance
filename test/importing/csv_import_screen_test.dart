import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/csv_import_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/import_factory.dart';
import 'package:myautofinance/app/navigation/app_routes.dart';
import 'package:myautofinance/app/regional.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/importing/presentation/import_controller.dart';
import 'package:myautofinance/features/importing/presentation/import_review_screen.dart';

import 'csv_import_flow_test.dart'
    show QueueCsvSelector, csv, header, validCsv, resolveCsv;

void main() {
  late LocalDatabase db;
  late ImportServices services;
  late QueueCsvSelector selector;
  late ImportController c;
  final capture = GlobalKey();
  setUpAll(() async {
    final font = File('C:/Windows/Fonts/segoeui.ttf');
    if (await font.exists()) {
      await (FontLoader(
        'Segoe UI',
      )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
    }
  });
  setUp(() {
    db = LocalDatabase(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys=ON'),
      ),
    );
    services = createImportServices(db);
    selector = QueueCsvSelector();
    c = createCsvImportController(() async => services, selector: selector);
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump(const Duration(milliseconds: 40));
    }
    if (!c.busy) await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  Future<void> tap(WidgetTester t, String text) async {
    await t.ensureVisible(find.text(text).last);
    await t.pump(const Duration(milliseconds: 100));
    await t.runAsync(() => t.tap(find.text(text).last));
    await settle(t);
  }

  Future<void> boot(WidgetTester t, double width, {double scale = 1}) async {
    t.view.physicalSize = Size(width, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        locale: AppRegional.locale,
        supportedLocales: AppRegional.supportedLocales,
        localizationsDelegates: AppRegional.delegates,
        theme: ThemeData(fontFamily: 'Segoe UI'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: capture,
          child: ImportReviewScreen(
            controller: c,
            onReturn: () {},
            onHistory: () {},
            onBatch: (_) {},
            onPeriod: (_, _) {},
          ),
        ),
      ),
    );
    await settle(t);
  }

  for (final width in [320.0, 412.0, 1440.0]) {
    testWidgets('CSV selección → revisión → SQLite a $width', (t) async {
      await boot(t, width);
      selector.add(csv(validCsv));
      await tap(t, 'Seleccionar CSV');
      expect(
        find.textContaining('REAL: 1 · original −2,50 € · interno −2,50 €'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'PRESUPUESTO: 1 · original +40,00 € · interno −40,00 €',
        ),
        findsOneWidget,
      );
      expect(c.canConfirm, isFalse);
      await t.runAsync(() => resolveCsv(c));
      await settle(t);
      expect(c.canConfirm, isTrue);
      if (width == 1440) {
        expect(find.byType(DataTable), findsOneWidget);
      } else {
        expect(find.byType(DataTable), findsNothing);
      }
      await tap(t, 'Confirmar lote completo');
      await tap(t, 'Importar todo');
      expect(find.text('Importado'), findsOneWidget);
      selector.add(csv(validCsv, 'mismos-bytes.csv'));
      await tap(t, 'Volver a cargar CSV');
      await tap(t, 'Descartar y cargar');
      expect(find.text('Ya importado'), findsOneWidget);
      expect(find.textContaining('Cero altas'), findsOneWidget);
      await t.runAsync(() async {
        final image =
            await (capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('.tools/ma-tsk-120-$width.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }

  testWidgets(
    'Todos los diagnósticos accesibles, 200%, cero totales parciales y recarga desde origen',
    (t) async {
      await boot(t, 320, scale: 2);
      selector.add(
        csv(
          '$header\n${List.generate(60, (i) => '2026-02-30;;0.00;REAL;;;;;').join('\n')}\n',
        ),
      );
      await tap(t, 'Seleccionar CSV');
      expect(c.canConfirm, isFalse);
      expect(
        find.text('REAL: conteo y totales CSV/interno no disponibles.'),
        findsOneWidget,
      );
      expect(find.textContaining('Fila 61 · fecha:'), findsOneWidget);
      await t.ensureVisible(find.textContaining('Fila 61 · fecha:'));
      await settle(t);
      expect(find.textContaining('línea física 61'), findsWidgets);
      selector.add(const LocalCsvCancelled());
      await tap(t, 'Volver a cargar CSV');
      expect(c.phase, ImportPhase.error);
      selector.add(csv(validCsv));
      await tap(t, 'Volver a cargar CSV');
      await tap(t, 'Conservar revisión');
      expect(c.phase, ImportPhase.error);
      selector.add(csv(validCsv));
      await tap(t, 'Volver a cargar CSV');
      await tap(t, 'Descartar y cargar');
      expect(c.phase, ImportPhase.review);
      await tap(t, 'Volver al origen');
      expect(find.text('¿Descartar la revisión?'), findsOneWidget);
      await tap(t, 'Seguir revisando');
      expect(c.session, isNotNull);
      await tap(t, 'Volver al origen');
      await tap(t, 'Descartar sesión');
      expect(c.session, isNull);
    },
  );

  testWidgets(
    'Gestión en producción activa CSV, conserva origen y periodo; XLS deshabilitado',
    (t) async {
      const channel = MethodChannel('autofinance/local_csv');
      var selections = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'select');
            expect(call.arguments, isNull);
            selections++;
            final selected = csv(validCsv);
            return {'name': selected.name, 'bytes': selected.bytes};
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await t.pumpWidget(AutofinanceApp(imports: () async => services));
      await settle(t);
      final nav = Navigator.of(t.element(find.byType(Scaffold)));
      nav.pushNamed('/real?a=2026&m=01');
      await settle(t);
      await tap(t, 'Gestión');
      final xls = t.widget<PopupMenuItem<String>>(
        find.widgetWithText(PopupMenuItem<String>, 'Importar XLS'),
      );
      expect(xls.enabled, isFalse);
      await tap(t, 'Importar CSV');
      expect(
        find.textContaining('Volver a Real anual, enero de 2026'),
        findsOneWidget,
      );
      await tap(t, 'Seleccionar CSV');
      expect(find.text('Revisión'), findsOneWidget);
      expect(selections, 1);
      await tap(t, 'Volver a Real anual, enero de 2026');
      await tap(t, 'Descartar sesión');
      expect(
        ModalRoute.of(t.element(find.byType(Scaffold)))!.settings.name,
        '/real?a=2026&m=01',
      );
      expect(
        (await t.runAsync(() => services.history.listBatches()))!.items,
        isEmpty,
      );
      expect(AppRoutes.importCsv, '/importaciones/csv');
    },
  );
}
