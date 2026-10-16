import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/indicator_input_factory.dart';
import 'package:myautofinance/app/wealth_management_factory.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/indicators/indicators.dart';
import 'package:myautofinance/features/indicators/presentation/indicator_screen.dart';
import 'package:myautofinance/features/indicators/presentation/indicator_source.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

import 'recovery_reference.dart';

// La segunda definición y su cálculo solo existen en el árbol de pruebas.
final class _LiquidEuros implements IndicatorCalculation {
  @override
  IndicatorResult calculate(IndicatorInputs inputs) => CalculatedIndicator(
    value: IndicatorValue(
      BigInt.from(inputs.wealth!.liquidAssetsCents!),
      BigInt.from(100),
    ),
    precision: 2,
    unit: 'EUR',
  );
}

/// Mismos servicios SQLite, motor y widgets en host y runners nativos.
Future<void> indicatorAcceptance(WidgetTester tester) async {
  final db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
  final invalidation = CategoryReadInvalidation();
  final wealth = createWealthManagement(database: db);
  final categories = createCategoryManagement(
    database: db,
    invalidation: invalidation,
  );
  final budgets = SqliteBudgetRepository(db);
  final source = createIndicatorSource(
    database: db,
    invalidation: invalidation,
  );
  final jan = Month(2026, 1), feb = Month(2026, 2);

  Future<T> io<T>(Future<T> Function() operation) async {
    Object? error;
    StackTrace? trace;
    final result = await tester.runAsync(() async {
      T? value;
      var finished = false;
      final pending = (() async {
        try {
          value = await operation().timeout(const Duration(seconds: 30));
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

  Future<List<Object?>> fingerprint() async => [
    (await db.customSelect('SELECT total_changes() AS n').getSingle()).data,
    (await db.readState()).revision,
    for (final table in [
      'sqlite_master',
      'wealth_snapshots',
      'wealth_values',
      'accounts',
      'account_liquidity_periods',
      'categories',
      'budgets',
      'movements',
    ])
      (await db.customSelect('SELECT * FROM $table ORDER BY 1').get())
          .map((row) => row.data)
          .toList(),
  ];

  Future<IndicatorResult> check(
    Month month, {
    String? exact,
    String? display,
    String? code,
    List<int>? pendingMonths,
    List<String>? pendingAccounts,
    IndicatorSource? selectedSource,
  }) async {
    final current = selectedSource ?? source;
    final before = await io(fingerprint);
    final result = (await io(
      () => current.engine.evaluate('colchon_emergencia', month),
    )).result;
    if (code != null) {
      final missing = result as UnavailableIndicator;
      expect(missing.code, code);
      expect(
        missing.text,
        IndicatorCatalog.v1().definitions.single.reasons
            .singleWhere((reason) => reason.code == code)
            .text,
      );
      if (pendingMonths != null) {
        expect(missing.detail.pendingMonths, pendingMonths);
      }
      if (pendingAccounts != null) {
        expect(
          missing.detail.pendingAccounts.map((a) => a.name),
          unorderedEquals(pendingAccounts),
        );
      }
    } else {
      final value = result as CalculatedIndicator;
      expect('${value.value.numerator}/${value.value.denominator}', exact);
      expect(formatCalculatedIndicator(value), display);
    }
    // UI sin ramas especiales ni entidades añadidas para el segundo indicador.
    await tester.pumpWidget(
      MaterialApp(
        theme: AfTheme.light(),
        home: IndicatorScreen(
          key: UniqueKey(),
          load: () async => current,
          month: month,
          onPosition: (_, _) {},
          shell: (body, scroll, action) => Scaffold(
            body: SingleChildScrollView(controller: scroll, child: body),
          ),
        ),
      ),
    );
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (find.text('Cargando').evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.text(code == null ? display! : 'Código: $code'),
      findsOneWidget,
    );
    expect(await io(fingerprint), before, reason: 'Consultar es solo lectura.');
    return result;
  }

  try {
    await io(() => seedRecoveryReference(db));
    final accounts = await io(wealth.catalog);
    final main = accounts.singleWhere((a) => a.name == 'Cuenta principal');
    final savings = accounts.singleWhere((a) => a.name == 'Cuenta de ahorro');
    final portfolio = accounts.singleWhere((a) => a.name == 'Cartera');
    final debt = accounts.singleWhere((a) => a.kind == AccountKind.debt);
    final salary = (await io(() => budgets.readYear(2026, incomeOnly: true)));
    Future<void> incomes(int amount) async {
      for (final row in await budgets.readYear(2026, incomeOnly: true)) {
        await budgets.delete(row.id);
      }
      for (var m = 1; m <= 12; m++) {
        await budgets.create(
          BudgetInput(
            month: BudgetMonth(2026, m),
            categoryId: salary.first.data.categoryId,
            amountCents: amount,
          ),
        );
      }
    }

    await check(jan, exact: '3/1', display: '3,00 meses');
    await check(feb, code: 'foto_ausente');
    await io(() async {
      await wealth.photos.setValue(feb, main.id, 620000);
      await wealth.photos.setValue(feb, debt.id, 480000);
    });
    await check(
      feb,
      code: 'foto_incompleta',
      pendingAccounts: ['Cuenta de ahorro', 'Cartera'],
    );
    // Simultaneidad de ausencias: foto antes que presupuesto negativo/incompleto.
    await io(() async {
      await budgets.delete(salary[2].id);
      await budgets.edit(
        salary.first.id,
        BudgetInput(
          month: BudgetMonth(2026, 1),
          categoryId: salary.first.data.categoryId,
          amountCents: -9000000,
        ),
      );
    });
    await check(Month(2026, 3), code: 'foto_ausente');
    await check(feb, code: 'foto_incompleta');
    await check(jan, code: 'ingresos_incompletos', pendingMonths: [3]);
    await io(() => incomes(0));
    await check(jan, code: 'ingresos_nulos');
    await io(() => incomes(-100));
    await check(jan, code: 'ingresos_negativos');
    await io(() => incomes(300000));
    await io(() async {
      await wealth.photos.setValue(feb, savings.id, 0);
      await wealth.photos.setValue(feb, portfolio.id, 1050000);
    });
    await check(feb, exact: '31/15', display: '2,07 meses');
    // MA-TSK-200: variante D integrada con proveedor SQLite y motor EP-023.
    // Las cifras esperadas son las del contrato, sin recalcularlas en el test.
    final originalPhoto = await io(() => wealth.readMonth(feb));
    expect(originalPhoto.totals!.netWorthCents, 1190000);
    final valuesBefore = await io(
      () async =>
          (await db
                  .customSelect('SELECT * FROM wealth_values ORDER BY id')
                  .get())
              .map((row) => row.data)
              .toList(),
    );
    final history = await io(
      () => wealth.changeLiquidity(portfolio.id, feb, Liquidity.liquid),
    );
    expect(history.history, hasLength(2));
    expect(history.history.first.from.value, '2026-01-01');
    expect(history.history.first.until!.value, '2026-02-01');
    expect(history.history.first.liquidity, Liquidity.medium);
    expect(history.history.last.from.value, '2026-02-01');
    expect(history.history.last.liquidity, Liquidity.liquid);
    await check(jan, exact: '3/1', display: '3,00 meses');
    await check(feb, exact: '167/30', display: '5,57 meses');
    final liquidPhoto = await io(() => wealth.readMonth(feb));
    expect(liquidPhoto.liquidAssetsCents, 1670000);
    expect(liquidPhoto.totals!.assetsCents, 1670000);
    expect(liquidPhoto.totals!.debtsCents, 480000);
    expect(liquidPhoto.totals!.netWorthCents, 1190000);
    await io(
      () => wealth.correctHistoricalLiquidity(
        portfolio.id,
        feb,
        Month(2026, 3),
        Liquidity.medium,
      ),
    );
    await check(feb, exact: '31/15', display: '2,07 meses');
    expect(
      await io(
        () async =>
            (await db
                    .customSelect('SELECT * FROM wealth_values ORDER BY id')
                    .get())
                .map((row) => row.data)
                .toList(),
      ),
      valuesBefore,
    );
    await io(() => wealth.photos.setValue(feb, main.id, 630000));
    await check(feb, exact: '21/10', display: '2,10 meses');
    final correctedPhoto = await io(() => wealth.readMonth(feb));
    expect(
      correctedPhoto.snapshot.snapshotId,
      originalPhoto.snapshot.snapshotId,
    );
    expect(correctedPhoto.totals!.netWorthCents, 1200000);
    await check(jan, exact: '3/1', display: '3,00 meses');
    expect(
      (await io(() => wealth.readMonth(jan))).totals!.netWorthCents,
      1400000,
    );
    // Sin foto, la clasificación histórica tampoco produce un resultado.
    await io(() => wealth.photos.deleteSnapshot(feb));
    await check(feb, code: 'foto_ausente');
    await io(() => wealth.changeLiquidity(portfolio.id, feb, Liquidity.liquid));
    await check(feb, code: 'foto_ausente');
    await io(() async {
      await wealth.photos.setValue(jan, main.id, 0);
      await wealth.photos.setValue(jan, savings.id, 0);
    });
    await check(jan, exact: '0/1', display: '0,00 meses');
    // Promedio menor de un céntimo: 1 * 12 / 7, nunca dividir enteros primero.
    await io(() async {
      await incomes(0);
      final first = (await budgets.readYear(2026, incomeOnly: true)).first;
      await budgets.edit(
        first.id,
        BudgetInput(
          month: first.data.month,
          categoryId: first.data.categoryId,
          amountCents: 7,
        ),
      );
      await wealth.photos.setValue(jan, main.id, 1);
    });
    await check(jan, exact: '12/7', display: '1,71 meses');
    // Superior a 2^53 en SQLite int64 y producto por 12 superior a int64.
    const large = 900719925474099301;
    await io(() async {
      await incomes(large);
      await wealth.photos.setValue(jan, main.id, large);
    });
    await check(jan, exact: '1/1', display: '1,00 meses');
    // Doce filas en enero no completan los otros once meses.
    await io(() async {
      for (final row in await budgets.readYear(2026, incomeOnly: true)) {
        await budgets.delete(row.id);
      }
      final root = await categories.create(
        name: 'Ingresos test',
        isIncome: true,
      );
      for (var i = 0; i < 12; i++) {
        final child = await categories.create(
          name: 'Partida $i',
          parentId: root.node.id,
        );
        await budgets.create(
          BudgetInput(
            month: BudgetMonth(2026, 1),
            categoryId: child.node.id,
            amountCents: i == 0 ? 0 : -1,
          ),
        );
      }
    });
    await check(
      jan,
      code: 'ingresos_incompletos',
      pendingMonths: [for (var m = 2; m <= 12; m++) m],
    );
    // La raíz selecciona los signos; las salidas positivas no completan ingresos.
    await io(() async {
      await incomes(300000);
      final expense = await categories.create(name: 'Gasto positivo');
      await budgets.create(
        BudgetInput(
          month: BudgetMonth(2026, 1),
          categoryId: expense.node.id,
          amountCents: 999999999,
        ),
      );
      await wealth.photos.setValue(jan, main.id, 900000);
    });
    await check(jan, exact: '3/1', display: '3,00 meses');
    final schemaBefore = await io(fingerprint);
    final definition = IndicatorDefinition(
      id: 'indicador_sintetico_test',
      name: 'Liquidez de prueba',
      version: 1,
      requiredInputs: {IndicatorInput.monthlyWealth},
      period: IndicatorPeriod.month,
      unit: 'EUR',
      reasons: [],
    );
    final extended = IndicatorSource(
      engine: IndicatorEngine(
        catalog: IndicatorCatalog([
          ...IndicatorCatalog.v1().definitions,
          definition,
        ]),
        inputs: createIndicatorInputProvider(database: db),
        calculations: {
          'colchon_emergencia': const EmergencyCushionCalculation(),
          definition.id: _LiquidEuros(),
        },
      ),
      changes: invalidation.changes,
    );
    await check(
      jan,
      exact: '3/1',
      display: '3,00 meses',
      selectedSource: extended,
    );
    expect(find.text('Liquidez de prueba'), findsOneWidget);
    expect(find.text('9.000,00 EUR'), findsOneWidget);
    expect(await io(fingerprint), schemaBefore);
    expect(IndicatorCatalog.v1().definitions.map((d) => d.id), [
      'colchon_emergencia',
    ]);
    debugPrint(
      'MA-TSK-188: G, precedencia, precisión, presencia y extensión SQLite correctos.',
    );
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await io(db.close);
    await io(invalidation.close);
  }
}
