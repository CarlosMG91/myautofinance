import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/app/navigation/movement_links.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/movements/presentation/movement_list_controller.dart';
import 'package:myautofinance/features/movements/presentation/movement_list_screen.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

/// Guion común de host y Windows/Android nativos. Solo usa una carpeta sintética
/// suministrada por el runner y la composición/persistencia reales de la app.
Future<void> movementLifecycleJourney(
  WidgetTester tester,
  Directory directory,
) async {
  var session = LocalBackupSession(supportDirectory: () async => directory);
  Future<T> io<T>(Future<T> Function() action) async {
    Object? error;
    StackTrace? trace;
    final value = await tester.runAsync(() async {
      try {
        return await action();
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
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      final loading =
          find.textContaining('Cargando').evaluate().isNotEmpty ||
          find.textContaining('Guardando').evaluate().isNotEmpty ||
          (find.byType(MovementListScreen).evaluate().isNotEmpty &&
              tester
                  .widget<MovementListScreen>(find.byType(MovementListScreen))
                  .controller
                  .loading);
      if (turn >= 5 && !loading) {
        expect(tester.takeException(), isNull);
        return;
      }
    }
    fail('La operación de movimientos SQLite no terminó.');
  }

  Future<void> tap(String label) async {
    await settle();
    debugPrint('Recorrido movimientos: $label');
    final buttons = find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    final target = buttons.evaluate().isNotEmpty
        ? buttons.last
        : find.text(label).evaluate().isNotEmpty
        ? find.text(label).last
        : find.byTooltip(label);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    if (buttons.evaluate().isNotEmpty) {
      expect(tester.widget<ButtonStyleButton>(target).enabled, isTrue);
    }
    await tester.runAsync(() => tester.tap(target));
    await settle();
  }

  Future<void> enter(String label, String value) async {
    // Volver del detalle puede iniciar una relectura desde su Future de ruta.
    // Esperar antes de introducir texto evita escribir en un control deshabilitado.
    await settle();
    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).enabled, isNot(false));
    await tester.enterText(field, value);
    expect(tester.widget<TextField>(field).controller!.text, value);
    await tester.pump();
  }

  Future<void> choose<T>(String label, String value) async {
    final dropdown = find.byWidgetPredicate(
      (w) => w is DropdownButtonFormField<T> && w.decoration.labelText == label,
    );
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(value).last);
    await settle();
  }

  NavigatorState navigator() =>
      tester.state<NavigatorState>(find.byType(Navigator).first);
  MovementListController list() => tester
      .widget<MovementListScreen>(find.byType(MovementListScreen))
      .controller;
  Future<Map<String, Object?>> snapshot({bool protectedOnly = false}) =>
      io(() async {
        final db = await session.store.open();
        return {
          for (final table in [
            'budgets',
            'wealth_snapshots',
            'wealth_values',
            if (!protectedOnly) ...[
              'movements',
              'import_batches',
              'import_rows',
              'database_state',
              'categories',
              'accounts',
              'account_liquidity_periods',
            ],
          ])
            table:
                (await db.customSelect('SELECT * FROM $table ORDER BY 1').get())
                    .map((r) => r.data)
                    .toList(),
        };
      });
  Future<int> revision() =>
      io(() async => (await (await session.store.open()).readState()).revision);
  Future<MovementRecord?> get(String id) => io(
    () async => SqliteMovementRepository(await session.store.open()).get(id),
  );
  Future<void> open(String id) async {
    await settle();
    final records = list().page!.records;
    final record = records.singleWhere((r) => r.id == id);
    final matches = records
        .where((r) => r.data.concept == record.data.concept)
        .toList();
    final button = find
        .text('Abrir ${record.data.concept}')
        .at(matches.indexOf(record));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await settle();
  }

  final march = MovementListQuery(
    from: ValueDate(2026, 3, 1),
    until: ValueDate(2026, 4, 1),
  );
  late String a1, a2, root, child, leaf, destination;
  late MovementInput imported;
  late List<MovementRecord> originals;
  final fingerprint = '9' * 64;
  Future<void> repeatImport() => io(() async {
    final db = await session.store.open();
    final repository = SqliteImportBatchRepository(db);
    expect(await repository.getByFingerprint(fingerprint), isNotNull);
    await expectLater(
      repository.create(
        sha256: fingerprint,
        source: ImportSource.historicalCsv,
        originalName: 'otro-nombre-sintetico.csv',
        contractVersion: '1',
        movements: [
          ImportedMovement(2, imported),
          ImportedMovement(3, imported),
        ],
      ),
      throwsA(isA<MovementFailure>()),
    );
  });

  try {
    await io(() async {
      final db = await session.store.open();
      final accounts = SqliteAccountRepository(db);
      a1 = (await accounts.create(
        name: 'Principal sintética',
        kind: AccountKind.account,
        activeFrom: Month(2026, 1),
        liquidity: Liquidity.liquid,
      )).id;
      a2 = (await accounts.create(
        name: 'Cerrada sintética',
        kind: AccountKind.account,
        activeFrom: Month(2026, 1),
        activeThrough: Month(2026, 3),
        liquidity: Liquidity.liquid,
      )).id;
      final categories = SqliteCategoryRepository(db);
      root = (await categories.create(name: 'Ocio sintético')).id;
      child = (await categories.create(
        name: 'Café sintético',
        parentId: root,
      )).id;
      leaf = (await categories.create(
        name: 'Terraza sintética',
        parentId: child,
      )).id;
      destination = (await categories.create(name: 'Destino sintético')).id;
      imported = MovementInput(
        accountId: a1,
        valueDate: ValueDate(2026, 3, 31),
        concept: 'Café',
        amountCents: 1250,
        categoryId: child,
        discretion: 'regalo',
      );
      await SqliteImportBatchRepository(db).create(
        sha256: fingerprint,
        source: ImportSource.historicalCsv,
        originalName: 'sintetico-095.csv',
        contractVersion: '1',
        movements: [
          ImportedMovement(2, imported),
          ImportedMovement(3, imported),
        ],
      );
      final repo = SqliteMovementRepository(db);
      originals = await repo.readYear(2026);
      expect(originals.length, 2);
      expect(originals.map((r) => r.id).toSet().length, 2);
      expect(originals.map((r) => r.importRowId).toSet().length, 2);
      expect(originals.map((r) => r.sourceOrdinal).toSet(), {2, 3});
      await repo.create(
        MovementInput(
          accountId: a2,
          valueDate: ValueDate(2026, 3, 30),
          concept: 'Árbol',
          amountCents: -450,
          categoryId: leaf,
        ),
      );
      await repo.create(
        MovementInput(
          accountId: a1,
          valueDate: ValueDate(2026, 4, 1),
          concept: 'Fuera del mes',
          amountCents: -200,
        ),
      );
      await SqliteBudgetRepository(db).create(
        BudgetInput(
          month: BudgetMonth(2026, 3),
          categoryId: destination,
          amountCents: -300,
          concept: 'Previsión sintética',
        ),
      );
      final wealth = SqliteWealthRepository(db);
      await wealth.prepare(Month(2026, 3));
      await wealth.setValue(Month(2026, 3), a1, 900000);
      await wealth.setValue(Month(2026, 3), a2, 100000);
    });
    final protected = await snapshot(protectedOnly: true);
    expect(await io(session.open), isTrue);
    await tester.pumpWidget(AutofinanceApp(localSession: session));
    navigator().pushNamed('/real?a=2026&m=03');
    await settle();
    await tap('Gestión');
    await tap('Movimientos');
    expect(list().from.value, march.from.value);
    expect(list().until!.value, march.until!.value);
    expect(list().categoryId, isNull);
    expect(list().page!.subtotalCents, 2050);

    // Dos altas manuales con todos los campos visibles idénticos son legítimas.
    for (var n = 0; n < 2; n++) {
      final before = await revision();
      await tap('Añadir movimiento');
      await enter('Fecha de valor · AAAA-MM-DD', '2026-03-01');
      await enter('Concepto', 'Duplicado legítimo');
      await enter('Importe firmado (EUR)', '-3,00');
      await choose<String>(
        'Cuenta vigente en el mes',
        'Principal sintética · ${a1.substring(0, 8)}',
      );
      await tap('Guardar movimiento');
      expect(await revision(), before + 1);
    }
    final manuals = await io(
      () async =>
          (await SqliteMovementRepository(await session.store.open())
                  .readYear(2026))
              .where((r) => r.data.concept == 'Duplicado legítimo')
              .toList(),
    );
    expect(manuals.length, 2);
    expect(manuals[0].id, isNot(manuals[1].id));
    expect(manuals.map((r) => r.importRowId), everyElement(isNull));
    await settle();
    expect(list().page!.subtotalCents, 1450);

    await open(originals.first.id);
    await tap('Editar');
    await enter('Fecha de valor · AAAA-MM-DD', '2026-03-29');
    await enter('Importe firmado (EUR)', '-4,50');
    await enter('Discrecionalidad opcional', '  corregida  ');
    await choose<String>(
      'Cuenta vigente en el mes',
      'Cerrada sintética · ${a2.substring(0, 8)}',
    );
    final beforeEdit = await revision();
    await tap('Guardar movimiento');
    expect(await revision(), beforeEdit + 1);
    final edited = (await get(originals.first.id))!;
    expect(edited.data.valueDate.value, '2026-03-29');
    expect(edited.data.amountCents, -450);
    expect(edited.data.accountId, a2);
    expect(edited.data.discretion, 'corregida');
    expect(edited.data.concept, 'Café');
    expect(edited.importRowId, originals.first.importRowId);
    expect(edited.batchId, originals.first.batchId);
    expect(edited.sourceOrdinal, originals.first.sourceOrdinal);
    var unchanged = await snapshot();
    await repeatImport();
    expect(await snapshot(), unchanged);

    // Búsqueda y filtros desde widgets reales; no busca en discrecionalidad.
    await enter('Buscar por concepto', 'CAFÉ');
    await tap('Aplicar filtros');
    expect(
      list().page!.records.map((r) => r.id).toSet(),
      originals.map((r) => r.id).toSet(),
    );
    expect(list().page!.subtotalCents, 800);
    await enter('Buscar por concepto', 'arbol');
    await tap('Aplicar filtros');
    expect(list().page!.records.single.data.concept, 'Árbol');
    expect(list().page!.subtotalCents, -450);
    await enter('Buscar por concepto', 'corregida');
    await tap('Aplicar filtros');
    expect(list().page!.records, isEmpty);
    await tap('Limpiar filtros');
    await choose<String>(
      'Categoría',
      'Ocio sintético · ${root.substring(0, 8)}',
    );
    expect(list().page!.records.length, 3);
    expect(list().page!.subtotalCents, 350);
    await choose<MovementCategoryScope>('Alcance', 'Solo directos');
    expect(list().page!.records, isEmpty);
    await choose<String>(
      'Categoría',
      'Ocio sintético / Café sintético · ${child.substring(0, 8)}',
    );
    expect(list().page!.records.length, 2);
    expect(list().page!.subtotalCents, 800);
    await choose<String>('Cuenta', 'Cerrada sintética · ${a2.substring(0, 8)}');
    expect(list().page!.records.single.id, edited.id);
    expect(list().page!.subtotalCents, -450);
    await choose<String>('Categoría', 'Sin clasificar');
    expect(list().page!.records, isEmpty);
    await choose<String>('Cuenta', 'Todas las cuentas');
    expect(list().page!.records.length, 2);
    expect(list().page!.subtotalCents, -600);
    await tap('Limpiar filtros');
    expect(list().page!.subtotalCents, -250);

    // Cursor/página visible usan exactamente la misma fuente de la sesión.
    final paged = MovementListController(
      load: session.movements,
      from: march.from,
      until: march.until,
      pageSize: 2,
    );
    navigator().push(
      MaterialPageRoute<void>(
        builder: (_) => MovementListScreen(
          controller: paged,
          onOpen: (_) async {},
          onReturn: () => navigator().pop(),
        ),
      ),
    );
    try {
      await settle();
      final first = paged.page!.records.map((r) => r.id).toList();
      expect(paged.page!.subtotalCents, -250);
      expect(paged.page!.records.first.data.valueDate.value, '2026-03-31');
      await tap('Página siguiente');
      expect(paged.page!.subtotalCents, -250);
      expect(
        paged.page!.records
            .map((r) => r.id)
            .toSet()
            .intersection(first.toSet()),
        isEmpty,
      );
      await tap('Seleccionar página visible (2)');
      final request = paged.beginBatch()!;
      final rowsBefore = await snapshot();
      final before = await revision();
      await io(
        () => paged.executeBatch(
          request,
          MovementBatchAction.assignCategory,
          categoryId: destination,
        ),
      );
      expect(paged.error, isNull);
      expect(await revision(), before + 1);
      final rowsAfter = await snapshot();
      final oldRows = rowsBefore['movements'] as List<Map<String, Object?>>;
      final newRows = rowsAfter['movements'] as List<Map<String, Object?>>;
      for (var i = 0; i < oldRows.length; i++) {
        if (request.selection.ids.contains(oldRows[i]['id'])) {
          expect(newRows[i]['category_id'], destination);
          expect(
            {...newRows[i]}
              ..remove('category_id')
              ..remove('updated_at'),
            {...oldRows[i]}
              ..remove('category_id')
              ..remove('updated_at'),
          );
        } else {
          expect(newRows[i], oldRows[i]);
        }
      }
      await tap('Página anterior');
      expect(paged.selected, isEmpty);
      expect(paged.page!.records.map((r) => r.id), first);
    } finally {
      navigator().pop();
      await settle();
    }
    await io(() => list().refresh());
    await settle();

    // Selección explícita y selector compartido, conservación de campos/origen.
    list().toggle(originals[0].id, true);
    list().toggle(originals[1].id, true);
    await tester.pump();
    final beforeBatch = await io(
      () async => [
        await getRaw(originals[0].id, session),
        await getRaw(originals[1].id, session),
      ],
    );
    await tap('Asignar categoría');
    await tap('Destino sintético');
    await tap('Seleccionar');
    await tap('Asignar categoría');
    expect(list().notice, '2 movimientos categorizados.');
    await tap('Quitar categoría');
    expect(list().notice, '2 movimientos sin categoría.');
    for (var i = 0; i < originals.length; i++) {
      final after = await io(() => getRaw(originals[i].id, session));
      expect(after['category_id'], isNull);
      expect(
        {...after}
          ..remove('category_id')
          ..remove('updated_at'),
        {...beforeBatch[i]}
          ..remove('category_id')
          ..remove('updated_at'),
      );
    }

    // Cancelación individual no escribe, confirmación conserva el origen.
    await open(originals[1].id);
    unchanged = await snapshot();
    await tap('Borrar movimiento');
    await tap('Cancelar');
    expect(await snapshot(), unchanged);
    await tap('Borrar movimiento');
    await tap('Confirmar borrado');
    expect(await get(originals[1].id), isNull);
    unchanged = await snapshot();
    await repeatImport();
    expect(await snapshot(), unchanged);
    expect((unchanged['import_rows'] as List).length, 2);
    expect((unchanged['import_batches'] as List).length, 1);

    // Cancelación/confirmación en lote con alcance visible y revisión única.
    await tap('Seleccionar página visible (4)');
    unchanged = await snapshot();
    await tap('Borrar seleccionados (4)');
    await tap('Cancelar');
    expect(await snapshot(), unchanged);
    expect(list().selected.length, 4);
    await tap('Quitar selección');
    list().toggle(manuals[0].id, true);
    list().toggle(manuals[1].id, true);
    await tester.pump();
    final beforeDelete = await revision();
    await tap('Borrar seleccionados (2)');
    await tap('Confirmar borrado');
    expect(await revision(), beforeDelete + 1);
    await settle();
    expect(list().selected, isEmpty);
    expect(list().page!.subtotalCents, -900);

    // Fallo en la segunda escritura: prueba rollback, no solo prevalidación.
    final remaining = list().page!.records.map((r) => r.id).toList();
    expect(remaining.length, 2);
    for (final action in MovementBatchAction.values) {
      await io(() async {
        final db = await session.store.open();
        await (await session.movements()).management.assignCategory(
          remaining,
          destination,
        );
        final event = action == MovementBatchAction.delete
            ? 'DELETE'
            : 'UPDATE';
        await db.customStatement('''
          CREATE TRIGGER reject_095 BEFORE $event ON movements
          WHEN OLD.id = '${remaining.last}'
          BEGIN SELECT RAISE(ABORT,'synthetic-095'); END
        ''');
      });
      unchanged = await snapshot();
      list().selectPage();
      final request = list().beginBatch()!;
      await io(() => list().executeBatch(request, action, categoryId: child));
      await settle();
      expect(list().error, contains('Lote rechazado'));
      expect(list().notice, isNull);
      expect(list().selected, remaining.toSet());
      expect(await snapshot(), unchanged);
      await io(
        () async => (await session.store.open()).customStatement(
          'DROP TRIGGER reject_095',
        ),
      );
    }

    list().selectPage();
    final obsolete = list().beginBatch()!;
    final lost = remaining.singleWhere((id) => id != edited.id);
    await io(() async => (await session.movements()).management.delete(lost));
    unchanged = await snapshot();
    await io(
      () => list().executeBatch(obsolete, MovementBatchAction.removeCategory),
    );
    await settle();
    expect(list().error, contains('Lote rechazado'));
    expect(await snapshot(), unchanged);
    await io(() => list().refresh());
    await settle();
    expect(list().selected, {edited.id});

    // Referencias históricas: categoría archivada conservable y cuenta cerrada
    // elegible en marzo, rechazada en abril. Fallos no cambian revisión.
    await io(() async {
      final source = await session.movements();
      await source.management.assignCategory([edited.id], child);
      await SqliteCategoryRepository(await session.store.open())
          .setArchived(child, archived: true);
    });
    await open(edited.id);
    expect(find.textContaining('Archivada'), findsWidgets);
    await tap('Editar');
    await enter('Concepto', 'Café histórico corregido');
    await tap('Guardar movimiento');
    expect((await get(edited.id))!.data.categoryId, child);
    await open(edited.id);
    await tap('Editar');
    await enter('Fecha de valor · AAAA-MM-DD', '2026-04-01');
    unchanged = await snapshot();
    await tap('Guardar movimiento');
    expect(
      find.text('Elige una cuenta vigente para esta fecha.'),
      findsOneWidget,
    );
    expect(await snapshot(), unchanged);
    await tap('Cancelar');
    await tap('Descartar cambios');
    await tap('Volver a Movimientos');
    await io(() async {
      final source = await session.movements();
      await expectLater(
        source.management.edit(edited.id, valueDate: '2026-04-01'),
        throwsA(isA<MovementFailure>()),
      );
      await expectLater(
        source.management.create(
          accountId: a1,
          valueDate: '2026-03-01',
          concept: 'Prohibida',
          amount: '1',
          categoryId: child,
        ),
        throwsA(isA<MovementFailure>()),
      );
      final editor = await source.editor!();
      final closed = (await editor.accounts()).singleWhere((a) => a.id == a2);
      expect(closed.eligible(ValueDate(2026, 3, 31)), isTrue);
      expect(closed.eligible(ValueDate(2026, 4, 1)), isFalse);
    });
    expect(await snapshot(), unchanged);

    // Contrato de informes: intersección y retorno al contexto original.
    navigator().pop();
    await settle();
    final origin = '/real?a=2026&m=03&rama=$root&alcance=rama';
    navigator().pushReplacementNamed(origin);
    await settle();
    final reportQuery = MovementListQuery(
      from: march.from,
      until: march.until,
      categoryId: child,
      scope: MovementCategoryScope.direct,
      accountId: a2,
      concept: 'CAFE',
    );
    navigator().pushNamed(MovementLinks.list(reportQuery, origin: origin));
    await settle();
    expect(list().scope, MovementCategoryScope.direct);
    expect(list().categoryId, child);
    expect(list().accountId, a2);
    expect(list().concept, 'CAFE');
    expect(list().page!.records.single.id, edited.id);
    expect(list().page!.subtotalCents, -450);
    await tap(
      tester
          .widget<MovementListScreen>(find.byType(MovementListScreen))
          .returnLabel,
    );
    expect(
      ModalRoute.of(tester.element(find.text('Real anual')))?.settings.name,
      origin,
    );

    expect(await snapshot(protectedOnly: true), protected);
    unchanged = await snapshot();
    await tester.pumpWidget(const SizedBox.shrink());
    await io(session.store.close);
    session.controller.dispose();
    await io(session.categoryInvalidation.close);
    session = LocalBackupSession(supportDirectory: () async => directory);
    expect(await io(session.open), isTrue);
    expect(await snapshot(), unchanged);
    await repeatImport();
    expect(await snapshot(), unchanged);
    await tester.pumpWidget(AutofinanceApp(localSession: session));
    navigator().pushNamed(MovementLinks.list(reportQuery, origin: origin));
    await settle();
    expect(list().page!.records.single.id, edited.id);
    expect(list().page!.subtotalCents, -450);
    final reopened = (await get(edited.id))!;
    expect(reopened.importRowId, edited.importRowId);
    expect(reopened.data.discretion, 'corregida');
    expect(await snapshot(protectedOnly: true), protected);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await io(session.store.close);
    session.controller.dispose();
    await io(session.categoryInvalidation.close);
  }
}

Future<Map<String, Object?>> getRaw(
  String id,
  LocalBackupSession session,
) async {
  final db = await session.store.open();
  return (await db.customSelect('SELECT * FROM movements').get())
      .singleWhere((r) => r.data['id'] == id)
      .data;
}
