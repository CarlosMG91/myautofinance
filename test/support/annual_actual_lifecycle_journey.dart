import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/features/actual_spending/actual_spending.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/movements/presentation/movement_list_screen.dart';
import 'package:myautofinance/features/movements/presentation/movement_record_list.dart';
import 'package:myautofinance/features/synchronization/domain/local_restore.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

import 'recovery_reference.dart';

/// App y servicios reales sobre una instalación sintética desechable.
/// Compartido por widgets Windows/Android y por el runner nativo.
Future<void> annualActualLifecycleJourney(
  WidgetTester tester,
  Directory directory, {
  required bool desktop,
}) async {
  var local = LocalBackupSession(supportDirectory: () async => directory);
  final navigation = NavigationSession(
    initialContext: NavigationContext(
      destination: SessionDestination.actual,
      period: NavigationPeriod(2026, 2),
    ),
  );
  Future<T> io<T>(Future<T> Function() action) async {
    Object? error;
    StackTrace? trace;
    final value = await tester.runAsync(() async {
      T? result;
      var finished = false;
      Future<void> perform() async {
        try {
          result = await action().timeout(const Duration(seconds: 45));
        } catch (caught, stack) {
          error = caught;
          trace = stack;
        } finally {
          finished = true;
        }
      }

      final operation = perform();
      // Avanzar las lecturas de la ruta anterior mientras SQLite espera.
      while (!finished) {
        await tester.pump(const Duration(milliseconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await operation;
      return result;
    });
    if (error != null) Error.throwWithStackTrace(error!, trace!);
    return value as T;
  }

  Future<void> settle() async {
    for (var turn = 0; turn < 200; turn++) {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump(const Duration(milliseconds: 100));
      if (turn >= 6 &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          find.textContaining('Cargando').evaluate().isEmpty &&
          find.textContaining('Guardando…').evaluate().isEmpty) {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        return;
      }
    }
    fail('Real anual no terminó de cargar.');
  }

  Future<void> tap(Finder finder) async {
    await settle();
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(finder));
    await settle();
  }

  Future<void> press(String text) => tap(find.text(text).last);
  Future<void> enter(String label, String value) async {
    final field = find.widgetWithText(TextFormField, label);
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
  }

  Future<LocalDatabase> db() => local.store.open();
  Future<AnnualActual> projection([int year = 2026]) =>
      io(() async => (await local.annualActual()).read(year));
  Future<List<MovementRecord>> records([int year = 2026]) =>
      io(() async => SqliteMovementRepository(await db()).readYear(year));
  Future<Map<String, Object?>> snapshot({bool protectedOnly = false}) =>
      io(() async {
        final database = await db();
        return {
          for (final table in [
            'budgets',
            'wealth_snapshots',
            'wealth_values',
            if (!protectedOnly) ...[
              'movements',
              'categories',
              'accounts',
              'database_state',
              'account_liquidity_periods',
              'import_batches',
              'import_rows',
            ],
          ])
            table:
                (await database
                        .customSelect('SELECT * FROM $table ORDER BY 1')
                        .get())
                    .map((row) => row.data)
                    .toList(),
        };
      });
  Future<void> mount() async {
    expect(await io(local.open), isTrue);
    await tester.pumpWidget(
      AutofinanceApp(localSession: local, navigationSession: navigation),
    );
    await settle();
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await io(local.store.close);
    local.controller.dispose();
    await io(local.categoryInvalidation.close);
  }

  Future<void> annual([int year = 2026]) async {
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .pushNamedAndRemoveUntil('/real/detalle?a=$year&m=02', (_) => false);
    await settle();
  }

  Future<void> reopen() async {
    final before = await snapshot();
    await close();
    local = LocalBackupSession(supportDirectory: () async => directory);
    await mount();
    await annual();
    expect(await snapshot(), before);
  }

  String amount(String token) =>
      (tester.widget<TextButton>(find.byKey(ValueKey('actual-$token'))).child!
              as AfMoneyText)
          .amount
          .format();
  Future<void> total(int cents, int count, {int year = 2026}) async {
    await settle();
    final data = await projection(year);
    expect(data.annualTotal.amountCents, cents);
    expect(data.annualTotal.movementCount, count);
    expect(amount('all:year'), AfAmount(cents).format());
  }

  Future<void> expand(String id) async {
    if ((navigation.context.filters['abiertas'] ?? '')
        .split(',')
        .contains(id)) {
      return;
    }
    if (desktop) {
      final data = await projection();
      final path = data.rows
          .singleWhere((row) => row.categoryId == id)
          .category!
          .path;
      tester
          .widget<AfDetailTable>(find.byType(AfDetailTable))
          .rows
          .singleWhere(
            (row) => row.label == path || row.label == '$path · Archivada',
          )
          .onExpand!();
      await settle();
    } else {
      await tap(find.byKey(ValueKey('actual-branch-$id')));
    }
  }

  Future<void> months(String id) async {
    if (!desktop &&
        !(navigation.context.filters['meses'] ?? '').split(',').contains(id)) {
      await tap(find.byKey(ValueKey('actual-months-$id')));
    }
  }

  Future<void> cell(String id, String month) async {
    if (month != 'year') await months(id == 'all' ? 'total-general' : id);
    await tap(find.byKey(ValueKey('actual-$id:$month')));
  }

  Future<void> origin() async {
    if (find.byKey(const ValueKey('actual-all:year')).evaluate().isEmpty) {
      await press('Volver a Real anual, 2026');
    }
    expect(navigation.period, NavigationPeriod(2026, 2));
  }

  void listEquals(Set<String> ids, int cents) {
    final controller = tester
        .widget<MovementListScreen>(find.byType(MovementListScreen))
        .controller;
    expect(controller.error, isNull);
    expect(controller.page!.subtotalCents, cents);
    expect(controller.page!.records.map((row) => row.id).toSet(), ids);
    expect(controller.page!.records, hasLength(ids.length));
    if (ids.isEmpty) {
      expect(find.byType(MovementRecordList), findsNothing);
      expect(find.textContaining('No hay movimientos'), findsWidgets);
    } else {
      final displayed = tester.widget<MovementRecordList>(
        find.byType(MovementRecordList),
      );
      expect(displayed.records.map((row) => row.id).toSet(), ids);
    }
  }

  try {
    expect(await io(local.open), isTrue);
    final account = await io(() async => seedRecoveryReference(await db()));
    await mount();
    await annual();
    final protected = await snapshot(protectedOnly: true);
    final baseline = await records();
    final f = await projection();
    final food = f.rows
        .singleWhere((r) => r.category?.node.name == 'Alimentación')
        .categoryId!;
    final market = f.rows
        .singleWhere((r) => r.category?.node.name == 'Supermercado')
        .categoryId!;
    final leaf = f.rows
        .singleWhere((r) => r.category?.node.name == 'Compra semanal')
        .categoryId!;
    final saving = f.rows
        .singleWhere((r) => r.category?.node.name == 'Cuenta de ahorro')
        .categoryId!;
    final income = f.rows
        .singleWhere((r) => r.category?.node.name == 'Salario')
        .categoryId!;
    final leisure = f.rows
        .singleWhere((r) => r.category?.node.name == 'Ocio')
        .categoryId!;
    debugPrint('EP-022 F: doce meses, raíces y UUID de duplicados legítimos');
    await total(232965, 10);
    expect(f.months.map((m) => m.amountCents), [
      122975,
      109990,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ]);
    expect(
      {
        for (final r in f.rows.where((r) => r.category!.node.parentId == null))
          r.category!.node.name: r.annualTotal.amountCents,
      },
      {
        'Ingresos': 612000,
        'Vivienda': -200000,
        'Alimentación': -77035,
        'Ahorro': -100000,
        'Ocio': -2000,
      },
    );
    expect(navigation.context.filters['abiertas'], anyOf(isNull, isEmpty));
    await expand(food);
    await expand(market);
    await months(food);
    expect(amount('$leaf:year'), '−770,35 €');
    for (var month = 1; month <= 12; month++) {
      await cell('all', '$month');
      listEquals(
        baseline
            .where(
              (r) =>
                  r.data.valueDate.value.substring(5, 7) ==
                  month.toString().padLeft(2, '0'),
            )
            .map((r) => r.id)
            .toSet(),
        f.months[month - 1].amountCents,
      );
      await origin();
    }
    await cell('all', 'year');
    listEquals(baseline.map((r) => r.id).toSet(), 232965);
    await origin();
    await cell(leisure, '1');
    final cafes = baseline
        .where((r) => r.data.concept == 'Café')
        .map((r) => r.id)
        .toSet();
    expect(cafes, hasLength(2));
    listEquals(cafes, -2000);
    await origin();

    debugPrint('EP-022 J/K: directos de padres, signos y neto cero con origen');
    final extras = await io(() async {
      final repo = SqliteMovementRepository(await db());
      final added = <MovementRecord>[];
      for (final entry in [
        (food, -1200),
        (market, 200),
        (null, 700),
        (null, -300),
        (saving, 500),
        (income, -400),
        (saving, 50000),
      ]) {
        added.add(
          await repo.create(
            MovementInput(
              accountId: account,
              valueDate: ValueDate(2026, 1, 16),
              concept: 'Variante sintética ${added.length}',
              categoryId: entry.$1,
              amountCents: entry.$2,
            ),
          ),
        );
      }
      return added;
    });
    await press('Actualizar año');
    await total(282465, 17);
    expect(amount('$food:year'), '−780,35 €');
    await cell(food, '1');
    listEquals({
      baseline
          .singleWhere(
            (r) =>
                r.data.categoryId == leaf &&
                r.data.valueDate.value.startsWith('2026-01'),
          )
          .id,
      extras[0].id,
      extras[1].id,
    }, -36025);
    await origin();
    await cell('sin-clasificar', '1');
    listEquals({extras[2].id, extras[3].id}, 400);
    await origin();
    // Segunda pierna de K deja exactamente cero al separar el ajuste J.
    await io(
      () async => SqliteMovementRepository(await db()).delete(extras[4].id),
    );
    await press('Actualizar año');
    await total(281965, 16);
    await expand(
      (await projection()).rows
          .singleWhere((r) => r.category?.node.name == 'Ahorro')
          .categoryId!,
    );
    await cell(saving, '1');
    listEquals({
      baseline
          .singleWhere(
            (r) =>
                r.data.categoryId == saving &&
                r.data.valueDate.value.startsWith('2026-01'),
          )
          .id,
      extras[6].id,
    }, 0);
    await origin();

    debugPrint(
      'EP-022 EP-010: cancelar/crear/editar/categorizar/quitar/borrar',
    );
    var before = await snapshot();
    await press('Añadir movimiento');
    expect(find.widgetWithText(TextFormField, '2026-02-01'), findsOneWidget);
    await press('Cancelar');
    expect(await snapshot(), before);
    await press('Añadir movimiento');
    await enter('Concepto', 'Alta integrada sintética');
    await enter('Importe firmado (EUR)', '-12,34');
    await tap(find.byType(DropdownButtonFormField<String>));
    await tap(find.textContaining('Cuenta principal ·').last);
    await press('Guardar movimiento');
    await origin();
    await total(280731, 17);
    final created = (await records()).singleWhere(
      (r) => r.data.concept == 'Alta integrada sintética',
    );
    await cell('sin-clasificar', '2');
    listEquals({created.id}, -1234);
    await press('Abrir Alta integrada sintética');
    before = await snapshot();
    await press('Editar');
    await enter('Importe firmado (EUR)', '999');
    await press('Cancelar');
    await press('Descartar cambios');
    expect(await snapshot(), before);
    await press('Editar');
    await enter('Importe firmado (EUR)', '-15,67');
    await press('Seleccionar categoría');
    await press('Alimentación');
    await press('Seleccionar');
    await press('Guardar movimiento');
    await origin();
    await total(280398, 17);
    expect(amount('$food:year'), '−796,02 €');
    expect(navigation.context.filters['abiertas'], contains(market));
    if (!desktop) expect(navigation.context.filters['meses'], contains(food));
    await cell(food, '2');
    listEquals({
      created.id,
      baseline
          .singleWhere(
            (r) =>
                r.data.categoryId == leaf &&
                r.data.valueDate.value.startsWith('2026-02'),
          )
          .id,
    }, -43577);
    await press('Abrir Alta integrada sintética');
    await press('Editar');
    await press('Quitar categoría');
    await enter('Fecha de valor · AAAA-MM-DD', '2026-03-01');
    await press('Guardar movimiento');
    expect(find.text('Ver mes'), findsOneWidget);
    expect(navigation.period, NavigationPeriod(2026, 2));
    await origin();
    expect(amount('$food:year'), '−780,35 €');
    await cell('sin-clasificar', '3');
    listEquals({created.id}, -1567);
    await press('Abrir Alta integrada sintética');
    await press('Editar');
    await enter('Fecha de valor · AAAA-MM-DD', '2027-01-01');
    await press('Guardar movimiento');
    expect(find.text('Ver mes'), findsOneWidget);
    await origin();
    await total(281965, 16);
    expect((await projection(2027)).annualTotal.amountCents, -1567);
    await reopen();
    await total(281965, 16);
    await annual(2027);
    await total(-1567, 1, year: 2027);
    await cell('sin-clasificar', 'year');
    listEquals({created.id}, -1567);
    await press('Abrir Alta integrada sintética');
    before = await snapshot();
    await press('Borrar movimiento');
    await press('Cancelar');
    expect(await snapshot(), before);
    await press('Borrar movimiento');
    await press('Confirmar borrado');
    await press('Volver a Real anual, 2027');
    await total(0, 0, year: 2027);
    await annual();

    debugPrint(
      'EP-022 archivo/reparent y restauración real sin cifras obsoletas',
    );
    await io(() async => (await local.categories()).archive(leaf));
    await settle();
    final newRoot = await io(
      () async => (await local.categories()).create(name: 'Reubicada'),
    );
    await io(
      () async =>
          (await local.categories()).move(leaf, parentId: newRoot.node.id),
    );
    await settle();
    await expand(newRoot.node.id);
    expect(amount('$leaf:year'), '−770,35 €');
    expect(
      (await projection()).rows
          .singleWhere((r) => r.categoryId == leaf)
          .category!
          .node
          .archived,
      isTrue,
    );
    await cell(newRoot.node.id, 'year');
    listEquals(
      baseline.where((r) => r.data.categoryId == leaf).map((r) => r.id).toSet(),
      -77035,
    );
    await origin();
    await total(281965, 16);
    before = await snapshot();
    await io(local.controller.create);
    expect(local.controller.error, isNull);
    final copy = local.controller.listing!.entries.single.backupId;
    final oldConnection = await io(db);
    await cell('sin-clasificar', '1');
    await press('Abrir Variante sintética 2');
    await press('Editar');
    await enter('Importe firmado (EUR)', '100');
    await press('Guardar movimiento');
    await origin();
    await total(291265, 16);
    await io(() => local.controller.restore(copy, confirmed: true));
    expect(local.controller.restoreResult!.status, LocalRestoreStatus.restored);
    await settle();
    expect(identical(await io(db), oldConnection), isFalse);
    await total(281965, 16);
    expect(await snapshot(), before);
    expect(await snapshot(protectedOnly: true), protected);
    await reopen();
    await total(281965, 16);
    expect(await snapshot(protectedOnly: true), protected);
    debugPrint('EP-022 recorrido integrado correcto');
  } finally {
    await close();
    navigation.dispose();
  }
}
