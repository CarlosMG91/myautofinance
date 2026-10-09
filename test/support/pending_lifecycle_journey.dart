import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/import_factory.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/app/navigation/app_routes.dart';
import 'package:myautofinance/app/navigation/import_route.dart';
import 'package:myautofinance/core/config/app_config.dart';
import 'package:myautofinance/features/importing/data/sha256_import_fingerprint.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/importing/presentation/import_history_screen.dart';
import 'package:myautofinance/features/importing/presentation/import_review_screen.dart';
import 'package:myautofinance/features/movements/presentation/pending_movement_controller.dart';
import 'package:myautofinance/features/movements/presentation/pending_movement_screen.dart';

import 'pending_reference_fixture.dart';
import 'synthetic_import_adapter.dart';

/// Composición real, SQLite desechable y núcleo EP-012. El adaptador de prueba
/// solo interpreta bytes sintéticos; no hay lectores EP-013/014 en el guion.
Future<void> pendingLifecycleJourney(
  WidgetTester tester,
  Directory directory, {
  required bool desktop,
}) async {
  var installation = LocalBackupSession(
    supportDirectory: () async => directory,
  );
  final fixture = PendingReferenceFixture();
  Future<T> io<T>(Future<T> Function() action) async {
    Object? error;
    StackTrace? trace;
    final value = await tester.runAsync(() async {
      try {
        return await action().timeout(const Duration(seconds: 45));
      } catch (caught, stack) {
        error = caught;
        trace = stack;
        return null;
      }
    });
    if (error != null) Error.throwWithStackTrace(error!, trace!);
    return value as T;
  }

  Future<void> settle() async {
    for (var turn = 0; turn < 300; turn++) {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump(const Duration(milliseconds: 50));
      final pending = find.byType(PendingMovementScreen);
      final busy =
          pending.evaluate().isNotEmpty &&
          (tester
                  .widget<PendingMovementScreen>(pending.last)
                  .controller
                  .loading ||
              tester
                  .widget<PendingMovementScreen>(pending.last)
                  .controller
                  .sending);
      if (turn >= 5 &&
          !busy &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.textContaining('Cargando').evaluate().isEmpty &&
          find.text('Consultando SQLite…').evaluate().isEmpty) {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        return;
      }
    }
    fail('La operación de categorización SQLite no terminó.');
  }

  Future<void> tap(Finder target) async {
    await settle();
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(target));
    await settle();
  }

  Future<void> press(String label) => tap(find.text(label).last);
  NavigatorState nav() =>
      tester.state<NavigatorState>(find.byType(Navigator).first);
  PendingMovementController pending() => tester
      .widget<PendingMovementScreen>(find.byType(PendingMovementScreen))
      .controller;
  Future<Map<String, Object?>> image() =>
      io(() async => fixture.image(await installation.store.open()));
  Future<void> mount() async {
    expect(await io(installation.open), isTrue);
    await tester.pumpWidget(
      AutofinanceApp(
        config: const AppConfig(environment: AppEnvironment.test),
        localSession: installation,
      ),
    );
    await settle();
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await io(installation.store.close);
    installation.controller.dispose();
    await io(installation.categoryInvalidation.close);
  }

  Future<void> route(String path, {Object? arguments}) async {
    nav().pushNamedAndRemoveUntil(path, (_) => false, arguments: arguments);
    await settle();
  }

  Future<void> chooseCategory(String path) async {
    await press(path);
    await press('Seleccionar');
  }

  void count(int total) => expect(
    find.text('Total pendiente del ámbito filtrado: $total movimientos'),
    findsOneWidget,
    reason:
        'total=${pending().page?.totalCount}, '
        'error=${pending().error}, sending=${pending().sending}, '
        'operation=${pending().operationActive}',
  );

  try {
    await io(() async => fixture.seed(await installation.store.open()));
    final ids = fixture.ids;
    final original = await image();
    final revision = await io(
      () async =>
          (await (await installation.store.open()).readState()).revision,
    );
    await mount();
    const origin = '${AppRoutes.actualSpending}?a=2020&m=02';
    await route(origin);
    await tap(find.byTooltip('Gestión'));
    await press('Pendientes de categorizar');
    count(5);
    expect(pending().query.from, isNull);
    expect(
      pending().page!.records.map((r) => r.id),
      isNot(contains(ids['r07'])),
    );
    expect(pending().page!.records.first.id, ids['r01']);

    // Selector y confirmación reales: cancelar no escribe ni cambia revisión.
    await tap(find.text('Categorizar Café Plaza').first);
    await chooseCategory('Hogar / Alimentación');
    expect(find.text('Confirmar asignación · 1 movimiento'), findsOneWidget);
    expect(find.textContaining(ids['r01']!), findsWidgets);
    await press('Cancelar');
    expect(await image(), original);
    count(5);
    await tap(find.text('Categorizar Café Plaza').first);
    await chooseCategory('Hogar / Alimentación');
    await press('Guardar categoría');
    count(4);
    expect(pending().selected, isEmpty);
    expect(
      pending().page!.records.map((r) => r.id),
      isNot(contains(ids['r01'])),
    );
    expect(
      fixture.preserved(
        await image(),
        allowed: [ids['r01']!, ids['r02']!, ids['r03']!],
      ),
      fixture.preserved(
        original,
        allowed: [ids['r01']!, ids['r02']!, ids['r03']!],
      ),
    );
    nav().pop();
    await settle();
    expect(
      ModalRoute.of(tester.element(find.text('Real anual')))!.settings.name,
      origin,
    );

    // Acceso contextual desde historial; el contador es actual, no el de alta.
    await route('${AppRoutes.importBatches}/${ids['l1']}');
    expect(find.text('Pendientes de categorizar: 2'), findsOneWidget);
    final historyState = tester.state(find.byType(ImportHistoryScreen));
    await press('Revisar pendientes del lote');
    count(2);
    expect(pending().query.batchId, ids['l1']);
    await press('Seleccionar página visible (2)');
    final selected = pending().selected.toSet();
    expect(selected, {ids['r02'], ids['r03']});
    final field = find.widgetWithText(TextField, 'Buscar por concepto');
    await tester.ensureVisible(field);
    await tester.enterText(field, 'cafe');
    await tester.pump();
    expect(pending().selected, isEmpty);
    expect(pending().canAssign, isFalse);
    await press('Aplicar filtros');
    count(2);
    await press('Seleccionar página visible (2)');
    await press('Asignar categoría (2)');
    await chooseCategory('Hogar');
    expect(find.text('Confirmar asignación · 2 movimientos'), findsOneWidget);
    for (final id in selected) {
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining(id),
        ),
        findsOneWidget,
      );
    }
    final beforeBatch = await image();
    await press('Cancelar');
    expect(await image(), beforeBatch);
    expect(pending().selected, selected);
    await press('Asignar categoría (2)');
    await chooseCategory('Hogar');
    await press('Guardar categoría');
    count(0);
    expect(pending().selected, isEmpty);
    expect(pending().query.batchId, ids['l1']);
    expect(pending().query.concept, 'cafe');
    nav().pop();
    await settle();
    expect(tester.state(find.byType(ImportHistoryScreen)), same(historyState));
    expect(find.text('Pendientes de categorizar: 0'), findsOneWidget);
    await press(desktop ? 'Ver origen 2' : 'Fila 2 · REAL');
    expect(find.text('Procedencia de fila'), findsOneWidget);
    expect(
      find.text('importe: original repetido sin normalizar'),
      findsOneWidget,
    );
    await press('Abrir registro actual');
    expect(find.text('Detalle de movimiento'), findsOneWidget);
    nav().pop();
    await settle();

    final assigned = await image();
    expect(
      fixture.preserved(
        assigned,
        allowed: [ids['r01']!, ids['r02']!, ids['r03']!],
      ),
      fixture.preserved(
        original,
        allowed: [ids['r01']!, ids['r02']!, ids['r03']!],
      ),
    );
    await io(() async {
      final db = await installation.store.open();
      expect((await db.readState()).revision, revision + 2);
      final history = createImportServices(db).history;
      for (final entry in [('l1', 'c-hogar'), ('l2', 'c-alimentacion')]) {
        final rows = (await history.listRows(ids[entry.$1]!)).items;
        for (final row in rows.where((r) => r.currentMovement != null)) {
          final key = fixture.key(row.currentMovement!.id);
          expect(row.original, isNotNull);
          expect(row.currentMovement!.importRowId, row.id);
          expect(row.currentMovement!.batchId, ids[entry.$1]);
          expect(row.currentMovement!.sourceOrdinal, row.sourceOrdinal);
          expect(row.currentMovement!.data.categoryId, switch (key) {
            'r01' || 'r06' => ids['c-alimentacion'],
            'r02' || 'r03' => ids['c-hogar'],
            _ => null,
          });
        }
      }
    });

    // Cerrar y abrir otra sesión sobre el mismo archivo comprueba persistencia.
    await close();
    installation = LocalBackupSession(supportDirectory: () async => directory);
    await mount();
    expect(await image(), assigned);
    await route(AppRoutes.pendingMovements);
    count(2);
    expect(pending().page!.records.map((r) => r.id).toSet(), {
      ids['r04'],
      ids['r05'],
    });
    await route('${AppRoutes.pendingMovements}?lote=${ids['l1']}');
    count(0);

    // Mismos bytes, nombre distinto: resultado EP-012, categoría y procedencia intactas.
    final repeated = ImportFile.fromBytes(
      bytes: fixture.files['l1']!.bytes,
      fingerprint: const Sha256ImportFingerprint(),
      source: ImportSource.historicalCsv,
      originalName: 'renombrado-sintetico.json',
    );
    await io(() async {
      final services = createImportServices(await installation.store.open());
      final session = ImportSession(
        file: repeated,
        interpretation: await const SyntheticImportAdapter(
          ImportSource.historicalCsv,
        ).interpret(repeated),
      );
      final review = await services.previewer.preview(
        session,
        bindings: ImportReferenceBindings(
          accounts: {
            for (final key in ['a1', 'a2'])
              ImportAccountReference.named(key): ids[key]!,
          },
          categories: {
            ImportCategoryReference(['Hogar']): ids['c-hogar']!,
          },
        ),
      );
      expect(review.canRequestConfirmation, isTrue);
      final result = await services.confirmer.confirm(
        ImportConfirmationRequest(
          review: review,
          reviewedOverlapKeys: review.overlaps.map((o) => o.key).toSet(),
        ),
      );
      expect(result, isA<ImportAlreadyImported>());
      expect((result as ImportAlreadyImported).batch.id, ids['l1']);
    });
    await route(
      AppRoutes.importReview,
      arguments: ImportReviewLaunch(
        file: repeated,
        adapter: const SyntheticImportAdapter(ImportSource.historicalCsv),
        origin: origin,
      ),
    );
    // La entrada sintética EP-012 requiere la confirmación explícita del lote;
    // solo el selector CSV de producción reconoce el archivo al seleccionarlo.
    final importController = tester
        .widget<ImportReviewScreen>(find.byType(ImportReviewScreen))
        .controller;
    await io(
      () => importController.refresh(
        bindings: ImportReferenceBindings(
          accounts: {
            for (final key in ['a1', 'a2'])
              ImportAccountReference.named(key): ids[key]!,
          },
          categories: {
            ImportCategoryReference(['Hogar']): ids['c-hogar']!,
          },
        ),
      ),
    );
    for (final overlap in importController.review!.overlaps) {
      importController.markOverlap(overlap.key, true);
    }
    expect(importController.canConfirm, isTrue);
    await press('Confirmar lote completo');
    await press('Importar todo');
    expect(find.text('Ya importado'), findsOneWidget);
    expect(await image(), assigned);
    expect(find.text('Pendientes de categorizar: 0'), findsOneWidget);
    await press('Revisar pendientes del lote');
    count(0);
    nav().pop();
    await settle();
    expect(find.text('Ya importado'), findsOneWidget);
    expect(await image(), assigned);
  } finally {
    await close();
  }
}
