import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/app/navigation/indicator_origin.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/synchronization/domain/local_restore.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

import 'recovery_reference.dart';

/// App real, SQLite desechable y formularios EP-011/017. Reutilizable en runners.
Future<void> indicatorJourney(
  WidgetTester tester,
  Directory directory, {
  required bool desktop,
  GlobalKey? captureKey,
  Future<void> Function(String name)? capture,
  bool externalAndroidBack = false,
}) async {
  final local = LocalBackupSession(supportDirectory: () async => directory);
  final navigation = NavigationSession(
    initialContext: NavigationContext(
      destination: SessionDestination.indicators,
      period: NavigationPeriod(2026, 1),
    ),
  );

  Future<T> io<T>(Future<T> Function() operation) async {
    Object? error;
    StackTrace? trace;
    final result = await tester.runAsync(() async {
      T? value;
      var finished = false;
      final pending = (() async {
        try {
          value = await operation().timeout(const Duration(seconds: 45));
        } catch (caught, stack) {
          error = caught;
          trace = stack;
        } finally {
          finished = true;
        }
      })();
      while (!finished) {
        await tester.pump(const Duration(milliseconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await pending;
      return value;
    });
    if (error != null) Error.throwWithStackTrace(error!, trace!);
    return result as T;
  }

  Future<void> settle() async {
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump(const Duration(milliseconds: 50));
      if (i >= 6 &&
          find.text('Cargando').evaluate().isEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          find.textContaining('Guardando').evaluate().isEmpty) {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        return;
      }
    }
    fail('Indicadores no terminó de cargar.');
  }

  Future<void> tap(Finder finder) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(finder));
    await settle();
  }

  Future<void> press(String label) => tap(find.text(label).last);
  Finder action(String token) => find.byKey(ValueKey('indicator-$token'));
  Future<void> total(String value) async {
    await settle();
    expect(find.text(value), findsOneWidget);
  }

  Future<void> origin() async {
    await tester.binding.handlePopRoute();
    await settle();
    expect(navigation.period, NavigationPeriod(2026, 2));
  }

  Future<Map<String, Object?>> snapshot() => io(() async {
    final db = await local.store.open();
    return {
      for (final table in [
        'accounts',
        'account_liquidity_periods',
        'wealth_values',
        'wealth_snapshots',
        'budgets',
        'movements',
        'categories',
        'import_batches',
        'import_rows',
        'database_state',
      ])
        table: (await db.customSelect('SELECT * FROM $table ORDER BY 1').get())
            .map((r) => r.data)
            .toList(),
    };
  });

  try {
    expect(
      await io(local.open),
      isTrue,
      reason: local.controller.startupMessage,
    );
    await io(() async => seedRecoveryReference(await local.store.open()));
    final accounts = await io(() async => (await local.wealth()).catalog());
    final account = accounts.singleWhere((a) => a.name == 'Cuenta principal');
    final savings = accounts.singleWhere((a) => a.name == 'Cuenta de ahorro');
    final before = await snapshot();
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: AutofinanceApp(
          localSession: local,
          navigationSession: navigation,
        ),
      ),
    );
    await total('3,00 meses');
    expect(
      await snapshot(),
      before,
      reason: 'Consultar no escribe ninguna tabla financiera.',
    );
    await capture?.call('resumen');
    await tap(action('detail'));
    expect(find.text('Precedencia de motivos'), findsOneWidget);
    await capture?.call('detalle');
    if (externalAndroidBack) {
      // Probar Back de Indicadores antes de abrir campos con teclado nativo.
      // El teclado Android consume primero Back cuando permanece abierto.
      const run = String.fromEnvironment('INDICATOR_ANDROID_BACK_RUN');
      debugPrint('MA-TSK-186: esperando KEYCODE_BACK $run');
      for (var i = 0; i < 200 && action('detail').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        action('detail'),
        findsOneWidget,
        reason: 'No llegó Android Back nativo.',
      );
      await settle();
    } else {
      await press('Volver al resumen');
    }
    await io(() => navigation.selectPeriod(NavigationPeriod(2026, 2)));
    await settle();
    expect(find.text('Código: foto_ausente'), findsOneWidget);
    await capture?.call('foto-ausente');
    await tap(action('photo'));
    // Formulario real: ceros explícitos completan también la deuda y cartera.
    for (final a in accounts) {
      final field = find.byKey(ValueKey('photo-value-${a.id}'));
      await tester.ensureVisible(field);
      await tester.enterText(field, a.id == account.id ? '6200' : '0');
    }
    await press('Guardar foto');
    await total('2,07 meses');
    expect(navigation.period, NavigationPeriod(2026, 2));
    // La acción desaparece tras completar: el foco vuelve al encabezado.
    expect(navigation.context.focus, 'photo');
    await tap(action('detail'));
    await tap(action('detail-photo'));
    final offsetBeforePhoto = navigation.context.scrollOffset;
    final field = find.byKey(ValueKey('photo-value-${account.id}'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '6300');
    await press('Guardar foto');
    await total('2,10 meses');
    await capture?.call('foto-corregida');
    expect(navigation.context.filters['detalle'], '1');
    final photoButton = tester.widget<OutlinedButton>(action('detail-photo'));
    expect(photoButton.focusNode!.hasFocus, isTrue);
    expect(navigation.context.scrollOffset, closeTo(offsetBeforePhoto, 1));

    // Faltan ingresos de marzo; la acción abre marzo sin cambiar el origen febrero.
    await io(() async {
      final repo = SqliteBudgetRepository(await local.store.open());
      final march = (await repo.readYear(
        2026,
        incomeOnly: true,
      )).singleWhere((b) => b.data.month.value == '2026-03-01');
      await repo.delete(march.id);
      local.categoryInvalidation.invalidate();
    });
    await settle();
    expect(find.text('Código: ingresos_incompletos'), findsOneWidget);
    await tap(action('budget-3'));
    expect(find.textContaining('marzo', findRichText: true), findsWidgets);
    expect(navigation.period, NavigationPeriod(2026, 2));
    final categories = await io(() async => (await local.categories()).list());
    final salary = categories.singleWhere((c) => c.node.name == 'Salario');
    final row = find.byKey(ValueKey(salary.node.id));
    final open = find.descendant(of: row, matching: find.text('Abrir alta'));
    await tap(open);
    final amount = find.byKey(const Key('budget-form-amount'));
    await tester.ensureVisible(amount);
    await tester.enterText(amount, '3000');
    await press('Guardar partida');
    await press('Volver a Indicadores');
    await total('2,10 meses');
    expect(navigation.context.filters['detalle'], '1');
    expect(
      tester
          .widget<OutlinedButton>(action('detail-budget'))
          .focusNode!
          .hasFocus,
      isFalse,
      reason: 'El control del mes pendiente ya no existe.',
    );

    // Relectura al volver de ruta secundaria, sin invalidación del árbol.
    await tap(action('detail-photo'));
    await io(
      () async => (await local.wealth()).changeLiquidity(
        account.id,
        Month(2026, 2),
        Liquidity.medium,
      ),
    );
    await origin();
    await total('0,00 meses');
    await capture?.call('cero');
    await io(() => navigation.selectPeriod(NavigationPeriod(2026, 1)));
    await total('3,00 meses');
    await io(() => navigation.selectPeriod(NavigationPeriod(2026, 2)));
    await total('0,00 meses');
    // Importación confirmada por repositorio existente: suma firmada, no filas.
    await tap(action('detail-photo'));
    await io(() async {
      await (await local.wealth()).changeLiquidity(
        account.id,
        Month(2026, 2),
        Liquidity.liquid,
      );
      await SqliteImportBatchRepository(await local.store.open()).create(
        sha256: 'b' * 64,
        source: ImportSource.historicalCsv,
        originalName: 'synthetic-indicator.csv',
        contractVersion: '1',
        movements: [],
        budgets: [
          ImportedBudget(
            2,
            BudgetInput(
              month: BudgetMonth(2026, 1),
              categoryId: (await (await local.categories()).create(
                name: 'Ingreso importado sintético',
                parentId: categories
                    .singleWhere((c) => c.node.name == 'Ingresos')
                    .node
                    .id,
              )).node.id,
              amountCents: 120000,
            ),
          ),
        ],
      );
    });
    await origin();
    await total('2,03 meses');
    // Árbol actual: el traslado de Salario fuera de ingreso invalida doce meses.
    final other = await io(
      () async => (await local.categories()).create(name: 'Salida sintética'),
    );
    await io(
      () async => (await local.categories()).move(
        salary.node.id,
        parentId: other.node.id,
      ),
    );
    await settle();
    expect(find.text('Código: ingresos_incompletos'), findsOneWidget);
    final incomeRoot = categories
        .singleWhere((c) => c.node.name == 'Ingresos')
        .node
        .id;
    await io(
      () async =>
          (await local.categories()).move(salary.node.id, parentId: incomeRoot),
    );
    await total('2,03 meses');

    // Restauración real reemplaza conexión; el loader no retiene la vieja.
    final saved = await snapshot();
    await io(local.controller.create);
    await settle();
    expect(local.controller.error, isNull);
    final copy = local.controller.listing!.entries.single.backupId;
    await tap(action('detail-photo'));
    await io(
      () async => (await local.wealth()).photos.setValue(
        Month(2026, 2),
        savings.id,
        300000,
      ),
    );
    await origin();
    await total('3,00 meses');
    final old = await io(local.store.open);
    await io(() => local.controller.restore(copy, confirmed: true));
    expect(local.controller.restoreResult!.status, LocalRestoreStatus.restored);
    await total('2,03 meses');
    expect(identical(await io(local.store.open), old), isFalse);
    expect(await snapshot(), saved);
    await capture?.call('restaurado');
    await tester.pumpWidget(const SizedBox.shrink());
    await io(local.store.close);
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: AutofinanceApp(
          localSession: local,
          navigationSession: navigation,
        ),
      ),
    );
    await total('2,03 meses');
    expect(await snapshot(), saved);
    // Enlaces secundarios sin pila reconstruyen el origen validado también
    // con Back, conservando febrero y la vista de detalle.
    final savedOrigin = IndicatorOrigin(navigation.context);
    for (final path in ['/patrimonio/foto', '/presupuesto/mensual']) {
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .pushNamedAndRemoveUntil(
            Uri(
              path: path,
              queryParameters: {
                'a': '2026',
                'm': '03',
                'origen': savedOrigin.route,
              },
            ).toString(),
            (_) => false,
          );
      await settle();
      await tester.binding.handlePopRoute();
      await total('2,03 meses');
      expect(navigation.period, NavigationPeriod(2026, 2));
      expect(navigation.context.filters['detalle'], '1');
    }
    expect(find.byType(AfCard), findsWidgets);
    debugPrint(
      'MA-TSK-186: foto, presupuesto, liquidez, árbol, importación y restauración correctos.',
    );
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await io(local.store.close);
    local.controller.dispose();
    await io(local.categoryInvalidation.close);
    navigation.dispose();
  }
}
