import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/budget_factory.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/import_factory.dart';
import 'package:myautofinance/app/monthly_status_query_factory.dart';
import 'package:myautofinance/app/movement_list_factory.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/app/pending_movement_factory.dart';
import 'package:myautofinance/app/wealth_management_factory.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movement_widgets.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/movements/presentation/movement_list_screen.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

import 'recovery_reference.dart';

typedef RedesignCapture = Future<void> Function(String name);

/// Recorrido público compartido por host y dispositivos. El store usa solo la
/// carpeta temporal del llamador; no abre la instalación ni compone OAuth.
Future<Map<String, Object>> redesignJourney(
  WidgetTester tester,
  Directory directory, {
  required Size size,
  required double scale,
  required GlobalKey captureKey,
  RedesignCapture? capture,
  bool largeDataset = false,
}) async {
  final store = LocalDatabaseStore(supportDirectory: () async => directory);
  final invalidation = CategoryReadInvalidation();
  final session = NavigationSession(
    initialContext: NavigationContext(
      destination: SessionDestination.home,
      period: NavigationPeriod(2026, 1),
    ),
  );
  Future<T> io<T>(Future<T> Function() action) async =>
      (await tester.runAsync(action)) as T;
  final db = await io(store.open);
  final account = await io(() => seedRecoveryReference(db));
  final categories = createCategoryManagement(
    database: db,
    invalidation: invalidation,
  );
  final nodes = await io(categories.list);
  final ocio = nodes.singleWhere((c) => c.path == 'Ocio').node.id;
  final food = nodes.singleWhere((c) => c.path == 'Alimentación').node.id;
  final before = await io(db.readState);
  final budgets = await io(
    () => SqliteBudgetRepository(db).list(BudgetMonth(2026, 1)),
  );
  final metrics = <String, Object>{
    'width': size.width,
    'height': size.height,
    'textScale': scale,
  };

  Future<void> settle({Finder? until}) async {
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump(const Duration(milliseconds: 50));
      final lists = find.byType(MovementListScreen);
      final listReady =
          lists.evaluate().isEmpty ||
          !tester.widget<MovementListScreen>(lists).controller.loading;
      if (i >= 5 &&
          listReady &&
          (until == null || until.evaluate().isNotEmpty) &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        return;
      }
    }
    fail('La UI integrada no terminó de leer SQLite.');
  }

  Future<void> tap(Finder finder) async {
    if (find.byType(SnackBar).evaluate().isNotEmpty) {
      await tester.drag(find.byType(SnackBar).first, const Offset(0, 150));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(finder));
    await settle();
  }

  Future<void> press(String text) async {
    debugPrint('MA-TSK-217 acción: $text');
    await tap(find.text(text).last);
  }

  Future<void> back() async {
    await tester.binding.handlePopRoute();
    await settle();
  }

  Future<void> snap(String name) async {
    await settle();
    if (capture != null) {
      await capture(name);
      // Al 200 % el shell coloca periodo/navegación dentro del scroll.
      // Conservar ese viewport y acreditar también el contenido de producto.
      if (scale == 2) {
        final shells = find.byType(AfShell);
        if (shells.evaluate().isNotEmpty) {
          final shell = tester.widget<AfShell>(shells.last);
          await tester.ensureVisible(find.byWidget(shell.page.body));
          await settle();
        }
        await capture('$name-contenido');
      }
    }
  }

  Finder summary(String label) =>
      find.byWidgetPredicate((w) => w is AfSummaryCard && w.label == label);
  void amount(int cents) => expect(
    tester
        .widget<AfSummaryCard>(summary('Resultado real del mes'))
        .amount
        .cents,
    cents,
  );
  Future<void> destination(SessionDestination value) async {
    debugPrint('MA-TSK-217 destino: ${value.name}');
    if ({
      SessionDestination.actual,
      SessionDestination.indicators,
      SessionDestination.diagnostics,
    }.contains(value)) {
      final analysis = find.byKey(const ValueKey('destination-analysis'));
      await tap(
        analysis.evaluate().isNotEmpty
            ? analysis
            : find.byKey(const ValueKey('destination-more')),
      );
      await press(switch (value) {
        SessionDestination.actual => 'Real anual',
        SessionDestination.indicators => 'Indicadores',
        _ => 'Diagnóstico de coherencia',
      });
    } else {
      await tap(find.byKey(ValueKey('destination-${value.name}')));
    }
  }

  try {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: AutofinanceApp(
            navigationSession: session,
            monthlyStatus: () async => createMonthlyStatusQuery(
              database: db,
              invalidation: invalidation,
            ),
            wealth: () async => createWealthManagement(database: db),
            categories: () async => categories,
            budgets: () async => createBudgetSource(db, invalidation),
            movements: () async => createMovementListSource(db, invalidation),
            pendingMovements: () async =>
                createPendingMovementSource(db, invalidation),
            imports: () async =>
                createImportServices(db, onConfirmed: invalidation.invalidate),
          ),
        ),
      ),
    );
    await settle();
    amount(122975);
    expect(find.text('14.000,00'), findsOneWidget);
    expect(
      MediaQuery.textScalerOf(tester.element(summary('Resultado real del mes')))
          .scale(16),
      16 * scale,
    );
    await snap('inicio');
    await tap(find.byKey(ValueKey('$food:expandir')));
    await tap(find.byKey(const ValueKey('home-detail')));
    await snap('estado-detalle');
    await tap(find.byKey(ValueKey('$ocio:real')));
    final list = tester
        .widget<MovementListScreen>(find.byType(MovementListScreen))
        .controller;
    expect(list.page!.records, hasLength(2));
    expect(list.page!.subtotalCents, -2000);
    await press('Abrir Café');
    await press('Editar');
    final field = find.widgetWithText(TextFormField, 'Importe firmado (EUR)');
    await tester.ensureVisible(field);
    await tester.enterText(field, '-9,00');
    await settle();
    // Back conserva borrador y datos hasta una acción de guardado explícita.
    await back();
    expect(find.text('Hay cambios sin guardar'), findsOneWidget);
    await press('Seguir editando');
    expect(tester.widget<TextFormField>(field).controller!.text, '-9,00');
    expect((await io(db.readState)).revision, before.revision);
    await snap('movimiento-borrador');
    await press('Guardar movimiento');
    await settle(until: find.byType(MovementListScreen));
    expect(list.page!.subtotalCents, -1900);
    await back();
    await back();
    expect(session.context.destination, SessionDestination.home);
    expect(session.period.year, 2026);
    expect(session.period.month, 1);
    expect(
      find.byKey(
        ValueKey(
          'home-category:${nodes.singleWhere((c) => c.path == 'Alimentación / Supermercado').node.id}',
        ),
      ),
      findsOneWidget,
    );
    amount(123075);
    expect(find.text('14.000,00'), findsOneWidget);
    expect(
      (await io(() => SqliteBudgetRepository(db).list(BudgetMonth(2026, 1))))
          .map((b) => b.data.amountCents),
      budgets.map((b) => b.data.amountCents),
    );
    await snap('inicio-retorno');
    await press('Corregir foto');
    final photo = find.byKey(ValueKey('photo-value-$account'));
    await tester.ensureVisible(photo);
    await tester.enterText(photo, '0,00');
    await settle();
    await press('Guardar foto');
    await settle(until: summary('Resultado real del mes'));
    amount(123075);
    expect(find.text('8.000,00'), findsOneWidget);
    final explicitState = await io(db.readState);
    await destination(SessionDestination.budget);
    await snap('presupuesto');
    await press('Ver detalle');
    await snap('presupuesto-detalle');
    await press('Volver al resumen');
    await destination(SessionDestination.wealth);
    await snap('patrimonio');
    await press('Ver detalle');
    await snap('patrimonio-detalle');
    await destination(SessionDestination.home);
    await press('Importar CSV');
    await snap('importar');
    await back();
    await press('Categorizar pendientes');
    await snap('categorizar-vacio');
    await back();
    await destination(SessionDestination.actual);
    metrics['realUnavailable'] = find
        .text('Sin contenido de producto · Diseño pendiente')
        .evaluate()
        .isNotEmpty;
    await snap('real-pendiente');
    await destination(SessionDestination.indicators);
    metrics['indicatorsUnavailable'] = find
        .text('Sin contenido de producto · Diseño pendiente')
        .evaluate()
        .isNotEmpty;
    await snap('indicadores-pendiente');
    await destination(SessionDestination.diagnostics);
    metrics['diagnosticsUnavailable'] = find
        .textContaining('pendiente de la interfaz de EP-025')
        .evaluate()
        .isNotEmpty;
    await snap('diagnostico-pendiente');
    await destination(SessionDestination.home);
    amount(123075);
    final written = await io(db.readState);
    expect(written.revision, explicitState.revision);
    await session.selectPeriod(NavigationPeriod(2026, 2));
    await settle();
    amount(109990);
    expect(find.text('Sin dato: falta foto patrimonial.'), findsOneWidget);
    await snap('inicio-sin-foto');
    expect((await io(db.readState)).revision, written.revision);

    if (largeDataset) {
      await io(
        () => SqliteImportBatchRepository(db).create(
          sha256: 'e' * 64,
          source: ImportSource.historicalCsv,
          originalName: 'sintetico-5000.csv',
          contractVersion: '1',
          movements: [
            for (var i = 0; i < 5000; i++)
              ImportedMovement(
                i + 2,
                MovementInput(
                  accountId: account,
                  valueDate: ValueDate(2026, 2, 15),
                  concept: 'Carga sintética $i',
                  amountCents: i.isEven ? 100 : -100,
                ),
              ),
          ],
          budgets: [],
        ),
      );
      final clock = Stopwatch()..start();
      await destination(SessionDestination.movements);
      clock.stop();
      final screen = tester.widget<MovementListScreen>(
        find.byType(MovementListScreen),
      );
      expect(screen.controller.page!.totalCount, 5004);
      expect(screen.controller.page!.subtotalCents, 109990);
      expect(screen.controller.page!.records, hasLength(100));
      expect(
        find.byType(MovementActivityRow).evaluate().length,
        lessThanOrEqualTo(100),
      );
      await tester.sendKeyEvent(
        LogicalKeyboardKey.tab,
        physicalKey: PhysicalKeyboardKey.tab,
      );
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, isNotNull);
      await snap('movimientos-5004');
      metrics['largeLoadMilliseconds'] = clock.elapsedMilliseconds;
      metrics['renderedRecords'] = screen.controller.page!.records.length;
    }
    metrics['financialWrites'] =
        'Movimiento -10 a -9 EUR; foto principal 6000 a 0 EUR';
    metrics['pendingOwners'] = ['EP-022', 'EP-023', 'EP-024', 'EP-025'];
    await tester.pumpWidget(const SizedBox.shrink());
    await io(store.close);
    final reopened = await io(store.open);
    final records = await io(
      () => SqliteMovementRepository(reopened).readMonth(2026, 1),
    );
    expect(
      records
          .where((r) => r.data.concept == 'Café')
          .map((r) => r.data.amountCents),
      unorderedEquals([-1000, -900]),
    );
    metrics['reopened'] = true;
    return metrics;
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
    await invalidation.close();
    await io(store.close);
    await tester.binding.setSurfaceSize(null);
  }
}
