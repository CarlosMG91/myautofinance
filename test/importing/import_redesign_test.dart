import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/csv_import_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/import_factory.dart';
import 'package:myautofinance/app/regional.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/importing/presentation/import_controller.dart';
import 'package:myautofinance/features/importing/presentation/import_history_screen.dart';
import 'package:myautofinance/features/importing/presentation/import_review_screen.dart';
import 'package:myautofinance/features/importing/presentation/import_widgets.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

import '../ui/kit_test.dart' show loadAfFonts;
import 'csv_import_flow_test.dart'
    show QueueCsvSelector, csv, validCsv, header, resolveCsv;

void main() {
  setUpAll(loadAfFonts);
  late LocalDatabase db;
  late ImportServices services;
  late ImportController controller;
  late QueueCsvSelector selector;
  final captureKey = GlobalKey();
  setUp(() {
    db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    services = createImportServices(db);
    selector = QueueCsvSelector();
    controller = createCsvImportController(
      () async => services,
      selector: selector,
    );
  });
  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
    if (!controller.busy) await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> tap(
    WidgetTester tester,
    String label, {
    bool keyboard = false,
  }) async {
    final finder = find.text(label).last;
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 100));
    if (keyboard) {
      Focus.of(tester.element(finder)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    } else {
      await tester.runAsync(() => tester.tap(finder));
    }
    await settle(tester);
  }

  Future<void> boot(
    WidgetTester tester,
    Widget child,
    double width,
    double scale,
  ) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AfTheme.light(),
        locale: AppRegional.locale,
        supportedLocales: AppRegional.supportedLocales,
        localizationsDelegates: AppRegional.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(key: captureKey, child: child),
      ),
    );
    await settle(tester);
  }

  Widget review() => ImportReviewScreen(
    controller: controller,
    onReturn: () {},
    onHistory: () {},
    onBatch: (_) {},
    onPeriod: (_, _) {},
  );

  Future<void> capture(WidgetTester tester, String name) async {
    if (Platform.environment['IMPORT_REDESIGN_CAPTURE'] != '1') return;
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = await Directory('docs/ep-026/importaciones-capturas')
          .create(recursive: true);
      await File('${directory.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final (width, scale, label) in [
    (1440.0, 1.0, 'windows'),
    (360.0, 1.0, 'android'),
    (320.0, 2.0, 'texto-200'),
  ]) {
    testWidgets('Resumen, detalle, confirmación y repetición con kit: $label', (
      tester,
    ) async {
      await boot(tester, review(), width, scale);
      await capture(tester, '$label-seleccion');
      selector.add(csv(validCsv));
      await tap(tester, 'Seleccionar CSV');
      expect(find.byType(DataTable), findsNothing);
      expect(find.textContaining('Resuelve las cuentas'), findsOneWidget);
      expect(find.text('−40,00 €'), findsOneWidget);
      expect((await services.history.listBatches()).items, isEmpty);
      await tester.runAsync(() => resolveCsv(controller));
      await settle(tester);
      await tester.ensureVisible(find.text('REAL'));
      await capture(tester, '$label-resumen');
      await tap(tester, 'Ver detalle de filas');
      if (width == 1440) {
        expect(find.byType(DataTable), findsOneWidget);
      } else {
        expect(find.text('Cuenta: Cuenta · alta preparada'), findsOneWidget);
        expect(find.text('Categoría: Sin clasificar'), findsOneWidget);
      }
      await tap(tester, 'Originales 2');
      expect(find.text('concepto: Café'), findsOneWidget);
      await tap(tester, 'Cerrar');
      await tap(tester, 'Confirmar lote completo');
      await tap(tester, 'Seguir revisando');
      expect((await services.history.listBatches()).items, isEmpty);
      expect((await db.readState()).revision, 0);
      await tap(tester, 'Confirmar lote completo');
      await tap(tester, 'Importar todo', keyboard: width == 1440);
      expect(controller.phase, ImportPhase.imported);
      final batch = (controller.result as ImportConfirmed).batch;
      expect(batch.movementCount, 1);
      expect(batch.budgetCount, 1);
      await tester.ensureVisible(find.text('Importación completada'));
      await capture(tester, '$label-resultado');
      final revision = (await db.readState()).revision;
      selector.add(csv(validCsv, 'renombrado.csv'));
      await tap(tester, 'Volver a cargar CSV');
      await tap(tester, 'Descartar y cargar');
      expect(find.textContaining('Cero altas'), findsOneWidget);
      expect((await db.readState()).revision, revision);
      expect((await services.history.listBatches()).items.length, 1);
      final semantics = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantics.dispose();
    });

    testWidgets('Historial compacto y metadatos bajo demanda: $label', (
      tester,
    ) async {
      selector.add(csv(validCsv));
      await tester.runAsync(() async {
        await controller.selectCsv(approveReplacement: () async => true);
        await resolveCsv(controller);
        await controller.confirm();
      });
      final batch = (controller.result as ImportConfirmed).batch;
      String? opened;
      Widget history({String? id}) => ImportHistoryScreen(
        load: () async => services,
        onReturn: () {},
        onBatch: (id) => opened = id,
        onRow: (_) {},
        onRecord: (_) async {},
        batchId: id,
      );
      await boot(tester, history(), width, scale);
      expect(find.textContaining('SHA-256:'), findsNothing);
      await capture(tester, '$label-historial');
      await tap(tester, 'Ver detalle del lote');
      expect(opened, batch.id);
      await tester.pumpWidget(const SizedBox.shrink());
      await boot(tester, history(id: batch.id), width, scale);
      expect(find.text('SHA-256: ${batch.sha256}'), findsOneWidget);
      expect(find.text('REAL: 1 · PRESUPUESTO: 1'), findsOneWidget);
      await capture(tester, '$label-lote');
    });
  }

  testWidgets('Errores completos visibles con detalle cerrado y texto 200%', (
    tester,
  ) async {
    selector.add(csv('$header\n2026-02-30;Inválido;-2.00;REAL;;;;Cuenta;\n'));
    await boot(tester, review(), 320, 2);
    await tap(tester, 'Seleccionar CSV');
    expect(
      find.text('El lote contiene errores. No se puede confirmar.'),
      findsOneWidget,
    );
    expect(find.textContaining('Fila 2 · fecha:'), findsOneWidget);
    expect(find.byType(ImportRowsView), findsNothing);
    expect(controller.canConfirm, isFalse);
    expect((await services.history.listBatches()).items, isEmpty);
    await tester.ensureVisible(
      find.text('El lote contiene errores. No se puede confirmar.'),
    );
    await capture(tester, 'texto-200-error');
    await tap(tester, 'Volver al origen');
    await tap(tester, 'Descartar sesión');
    expect((await services.history.listBatches()).items, isEmpty);
  });

  testWidgets('Historial distingue fallo de vacío y permite reintentar', (
    tester,
  ) async {
    var attempts = 0;
    var returned = false;
    await boot(
      tester,
      ImportHistoryScreen(
        load: () async {
          if (attempts++ == 0) throw StateError('fallo sintético');
          return services;
        },
        onReturn: () => returned = true,
        onBatch: (_) {},
        onRow: (_) {},
        onRecord: (_) async {},
      ),
      320,
      2,
    );
    expect(
      find.textContaining('No se pudo consultar el historial'),
      findsOneWidget,
    );
    expect(find.text('Sin lotes confirmados.'), findsNothing);
    await tap(tester, 'Reintentar');
    expect(find.text('Sin lotes confirmados.'), findsOneWidget);
    expect(
      find.textContaining('No se pudo consultar el historial'),
      findsNothing,
    );
    await tap(tester, 'Volver');
    expect(returned, isTrue);
    expect((await db.readState()).revision, 0);
  });

  testWidgets(
    'Asignación con kit a 200% conserva el original y cancelar no escribe',
    (tester) async {
      selector.add(csv(validCsv));
      await boot(tester, review(), 320, 2);
      await tap(tester, 'Seleccionar CSV');
      await tap(tester, 'Resolver cuenta: Cuenta');
      expect(find.text('Cuenta original: Cuenta'), findsOneWidget);
      await tap(tester, 'Preparar nueva referencia');
      expect(find.byType(AfFormField), findsNWidgets(3));
      expect(find.text('Nombre · obligatorio'), findsOneWidget);
      expect(
        find.text('Deja el campo vacío si no tiene fecha de fin.'),
        findsOneWidget,
      );
      await tap(tester, 'Cancelar');
      expect(controller.canConfirm, isFalse);
      expect(controller.review!.bindings.newAccounts, isEmpty);
      expect((await services.history.listBatches()).items, isEmpty);
      expect((await db.readState()).revision, 0);
      await tap(tester, 'Historial de lotes');
      expect(controller.session, isNotNull);
    },
  );
}
