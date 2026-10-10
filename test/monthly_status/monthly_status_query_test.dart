import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/monthly_status_query_factory.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/data/historical_csv_reader.dart';
import 'package:myautofinance/features/importing/historical_csv.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/monthly_status/monthly_status.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  late LocalDatabase db;
  late CategoryReadInvalidation invalidation;
  late CategoryManagement categories;
  late MonthlyStatusQuery query;
  late SqliteMovementRepository movements;
  late SqliteBudgetRepository budgets;
  late String account, secondAccount;
  final jan = BudgetMonth(2026, 1);

  Future<MovementRecord> real(
    String? id,
    int amount, {
    String? onAccount,
    ValueDate? date,
  }) => movements.create(
    MovementInput(
      accountId: onAccount ?? account,
      valueDate: date ?? ValueDate(2026, 1, 9),
      concept: 'Movimiento sintético',
      amountCents: amount,
      categoryId: id,
    ),
  );
  Future<BudgetRecord> budget(String id, int amount, {BudgetMonth? month}) =>
      budgets.create(
        BudgetInput(month: month ?? jan, categoryId: id, amountCents: amount),
      );
  MonthlyStatusRow row(MonthlyStatus result, String id) =>
      result.rows.singleWhere((r) => r.categoryId == id);

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    invalidation = CategoryReadInvalidation();
    categories = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    query = createMonthlyStatusQuery(database: db, invalidation: invalidation);
    movements = SqliteMovementRepository(db);
    budgets = SqliteBudgetRepository(db);
    final accounts = SqliteAccountRepository(db);
    Future<String> createAccount() async => (await accounts.create(
      name: 'Cuenta sintética',
      kind: AccountKind.account,
      activeFrom: Month(1, 1),
      liquidity: Liquidity.liquid,
    )).id;
    account = await createAccount();
    secondAccount = await createAccount();
  });
  tearDown(() async {
    await invalidation.close();
    await db.close();
  });

  Future<Map<String, String>> importReference() async {
    final csv = const HistoricalCsvReader().read(
      File('docs/ep-001/historico-ejemplo.csv').readAsBytesSync(),
    );
    expect(csv.isValid, isTrue);
    final ids = <String, String>{};
    final reals = <ImportedMovement>[];
    final planned = <ImportedBudget>[];
    var ordinal = 1;
    for (final record in csv.records) {
      ordinal++;
      String? parent;
      for (var level = 0; level < record.categoryPath.length; level++) {
        final path = record.categoryPath.take(level + 1).join(' / ');
        parent = ids[path] ??= (await categories.create(
          name: record.categoryPath[level],
          parentId: parent,
          isIncome: parent == null
              ? record.categoryPath.first == 'Ingresos'
              : null,
        )).node.id;
      }
      if (record.type == HistoricalCsvType.real) {
        reals.add(
          ImportedMovement(
            ordinal,
            MovementInput(
              accountId: account,
              valueDate: ValueDate.parse(record.date),
              concept: record.concept,
              amountCents: record.csvAmountCents,
              categoryId: parent,
            ),
          ),
        );
      } else {
        planned.add(
          ImportedBudget(
            ordinal,
            BudgetInput.fromHistoricalCsv(
              month: BudgetMonth.parse(record.date),
              categoryId: parent!,
              csvAmountCents: record.csvAmountCents,
              concept: record.concept,
            ),
          ),
        );
      }
    }
    await SqliteImportBatchRepository(db).create(
      sha256: '1' * 64,
      source: ImportSource.historicalCsv,
      originalName: 'historico-ejemplo.csv',
      contractVersion: '1',
      movements: reals,
      budgets: planned,
    );
    return ids;
  }

  test(
    'EP-001 B/C: céntimos firmados, duplicados y ausencia de foto',
    () async {
      final ids = await importReference();
      final before = await db.readState();
      // Incluye las tablas TEMP: detecta también escrituras de control sin revisión.
      final changes =
          (await db.customSelect('SELECT total_changes() AS n').getSingle())
              .read<int>('n');
      final january = await query.read(jan);
      final february = await query.read(BudgetMonth(2026, 2));
      expect(january.total.plannedCents, 110000);
      expect(january.total.actualCents, 122975);
      expect(january.total.differenceCents, 12975);
      expect(january.total.movementCount, 6);
      expect(january.total.budgetCount, 4);
      expect(february.total.plannedCents, 110000);
      expect(february.total.actualCents, 109990);
      expect(february.total.differenceCents, -10);
      expect(row(january, ids['Alimentación']!).totals.actualCents, -35025);
      expect(row(february, ids['Alimentación']!).totals.differenceCents, -2010);
      final leisure = row(january, ids['Ocio']!);
      expect(leisure.totals.hasBudget, isFalse);
      expect(leisure.totals.plannedCents, 0);
      expect(leisure.directMovementCount, 2);
      expect(leisure.totals.differenceCents, -2000);
      expect(january.datasetState.revision, before.revision);
      expect((await db.readState()).revision, before.revision);
      expect(
        (await db.customSelect('SELECT total_changes() AS n').getSingle())
            .read<int>('n'),
        changes,
      );
      expect(() => january.rows.clear(), throwsUnsupportedError);
      expect(() => january.tree.clear(), throwsUnsupportedError);
    },
  );

  test(
    'EP-001 J/K: padre directo, descendientes, null y transferencia neta cero',
    () async {
      final ids = await importReference();
      final food = ids['Alimentación']!,
          shop = ids['Alimentación / Supermercado']!;
      final savings = ids['Ahorro / Cuenta de ahorro']!;
      await real(food, -1200);
      await real(shop, 200);
      await real(null, 700);
      await real(null, -300);
      await real(savings, 500);
      await real(ids['Ingresos / Salario'], -400);
      final j = await query.read(jan);
      expect(row(j, food).actualDirectCents, -1200);
      expect(row(j, shop).actualDirectCents, 200);
      expect(row(j, shop).totals.actualCents, -34825);
      expect(row(j, food).totals.actualCents, -36025);
      expect(j.unclassified.actualCents, 400);
      expect(j.unclassified.movementCount, 2);
      expect(j.unclassified.hasBudget, isFalse);
      expect(j.total.actualCents, 122475);
      expect(j.total.differenceCents, 12475);
      // Variante K independiente: retirar las adiciones de J.
      final originals = await movements.readMonth(2026, 1);
      for (final record in originals.where((m) => m.importRowId == null)) {
        await movements.delete(record.id);
      }
      final incoming = await real(savings, 50000, onAccount: secondAccount);
      final k = await query.read(jan);
      expect(row(k, ids['Ahorro']!).totals.actualCents, 0);
      expect(row(k, savings).hasDirectMovements, isTrue);
      expect(row(k, savings).directMovementCount, 2);
      expect(k.total.actualCents, 172975);
      await movements.delete(incoming.id);
      expect((await query.read(jan)).total.actualCents, 122975);
    },
  );

  test('EP-001 L: tipo raíz, presupuesto hermano y tres niveles', () async {
    final income = await categories.create(name: 'INGRESOS', isIncome: true);
    final salary = await categories.create(
      name: 'SALARIO',
      parentId: income.node.id,
    );
    final tax = await categories.create(
      name: 'IMPUESTOS',
      parentId: salary.node.id,
    );
    final wage = await categories.create(
      name: 'NÓMINA',
      parentId: salary.node.id,
    );
    await real(salary.node.id, 300000);
    await real(tax.node.id, -60000);
    await budget(wage.node.id, 300000);
    await budget(tax.node.id, -60000);
    final result = await query.read(jan);
    expect(row(result, salary.node.id).actualDirectCents, 300000);
    expect(row(result, salary.node.id).totals.actualCents, 240000);
    expect(row(result, salary.node.id).totals.plannedCents, 240000);
    expect(row(result, salary.node.id).hasOwnBudget, isFalse);
    expect(row(result, tax.node.id).category.node.isIncome, isTrue);
    expect(result.total.differenceCents, 0);
    expect(result.total.actualCents, 240000);
  });

  test(
    'Raíces activas, antecesores históricos, UUID homónimos y cero explícito',
    () async {
      final root = await categories.create(name: 'Raíz', isIncome: false);
      final branch = await categories.create(
        name: 'Rama',
        parentId: root.node.id,
      );
      final zero = await categories.create(
        name: 'Igual',
        parentId: branch.node.id,
      );
      final net = await categories.create(
        name: 'Igual',
        parentId: branch.node.id,
      );
      await categories.create(name: 'Sin datos', parentId: root.node.id);
      final empty = await categories.create(name: 'Vacía', isIncome: false);
      final hidden = await categories.create(
        name: 'Archivo sin datos',
        isIncome: false,
      );
      await categories.archive(hidden.node.id);
      final recorded = await budget(zero.node.id, 0);
      await real(net.node.id, 900);
      await real(net.node.id, -900, onAccount: secondAccount);
      await categories.archive(branch.node.id);
      final result = await query.read(jan);
      expect(result.rows.map((r) => r.categoryId).toSet(), {
        root.node.id,
        branch.node.id,
        zero.node.id,
        net.node.id,
        empty.node.id,
      });
      expect(row(result, zero.node.id).ownBudget!.id, recorded.id);
      expect(row(result, zero.node.id).hasOwnBudget, isTrue);
      expect(row(result, zero.node.id).totals.hasBudget, isTrue);
      expect(row(result, branch.node.id).hasOwnBudget, isFalse);
      expect(row(result, branch.node.id).totals.hasBudget, isTrue);
      expect(row(result, net.node.id).totals.hasBudget, isFalse);
      expect(row(result, net.node.id).actualDirectCents, 0);
      expect(row(result, net.node.id).directMovementCount, 2);
      expect(row(result, branch.node.id).category.node.archived, isTrue);
      expect(result.total.budgetCount, 1);
      expect(result.total.movementCount, 2);
      expect(result.tree, hasLength(7));
    },
  );

  test('Padre presupuestado no prorratea; ausencia propia/agregada', () async {
    final root = await categories.create(name: 'Padre', isIncome: false);
    final child = await categories.create(name: 'Hija', parentId: root.node.id);
    await budget(root.node.id, -10000);
    await real(child.node.id, -8000);
    final result = await query.read(jan);
    expect(row(result, root.node.id).totals.plannedCents, -10000);
    expect(row(result, root.node.id).totals.differenceCents, 2000);
    expect(row(result, child.node.id).hasOwnBudget, isFalse);
    expect(row(result, child.node.id).totals.hasBudget, isFalse);
    expect(row(result, child.node.id).totals.plannedCents, 0);
    expect(row(result, child.node.id).totals.differenceCents, -8000);
    expect(result.total.plannedCents, -10000);
  });

  test(
    'Mes civil, límites 1/9999, todas las cuentas y vacíos reales',
    () async {
      final root = await categories.create(name: 'Raíz', isIncome: false);
      await real(root.node.id, 1, date: ValueDate(1, 1, 1));
      await real(root.node.id, 20, date: ValueDate(2025, 12, 31));
      await real(root.node.id, 30, date: ValueDate(2026, 1, 1));
      await real(
        root.node.id,
        -10,
        date: ValueDate(2026, 1, 31),
        onAccount: secondAccount,
      );
      await real(root.node.id, 40, date: ValueDate(2026, 2, 1));
      await real(null, 99, date: ValueDate(9999, 12, 31));
      expect((await query.read(jan)).total.actualCents, 20);
      expect((await query.read(BudgetMonth(1, 1))).total.actualCents, 1);
      expect(
        (await query.read(BudgetMonth(9999, 12))).unclassified.actualCents,
        99,
      );
      final empty = await query.read(BudgetMonth(2027, 1));
      expect(empty.total.actualCents, 0);
      expect(empty.total.hasBudget, isFalse);
      expect(empty.total.hasMovements, isFalse);
    },
  );

  test(
    'Relectura tras datos, traslado, archivo y restauración de conexión',
    () async {
      final root = await categories.create(name: 'Ingreso', isIncome: true);
      final other = await categories.create(name: 'Salida', isIncome: false);
      final child = await categories.create(
        name: 'Rama',
        parentId: root.node.id,
      );
      final movement = await real(child.node.id, 100);
      await budget(child.node.id, 80);
      final old = await query.read(jan);
      await movements.edit(
        movement.id,
        MovementInput(
          accountId: account,
          valueDate: movement.data.valueDate,
          concept: 'Corregido',
          amountCents: 150,
          categoryId: child.node.id,
        ),
      );
      await categories.move(child.node.id, parentId: other.node.id);
      await categories.rename(other.node.id, name: 'Salidas');
      await categories.archive(child.node.id);
      final current = await query.read(jan);
      expect(row(current, root.node.id).totals.actualCents, 0);
      expect(row(current, other.node.id).totals.actualCents, 150);
      expect(row(current, child.node.id).category.path, 'Salidas / Rama');
      expect(row(current, child.node.id).category.node.isIncome, isFalse);
      expect(current.categoryGeneration, greaterThan(old.categoryGeneration));
      expect(
        current.datasetState.revision,
        greaterThan(old.datasetState.revision),
      );
      expect(row(old, child.node.id).category.path, 'Ingreso / Rama');
      expect(old.total.actualCents, 100);
      await db.close();
      db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
      invalidation.invalidate();
      query = createMonthlyStatusQuery(
        database: db,
        invalidation: invalidation,
      );
      final replaced = await query.read(jan);
      expect(
        replaced.datasetState.datasetId,
        isNot(old.datasetState.datasetId),
      );
      expect(replaced.rows, isEmpty);
      expect(replaced.total.actualCents, 0);
      expect(
        replaced.categoryGeneration,
        greaterThan(current.categoryGeneration),
      );
    },
  );

  test(
    'Agregado SQLite acotado por categoría conserva más de una página',
    () async {
      final root = await categories.create(name: 'Raíz', isIncome: false);
      await db.run(() async {
        for (var i = 0; i < 601; i++) {
          await real(root.node.id, i.isEven ? 100 : -100);
        }
      });
      final grouped = await movements.readMonthTotals(2026, 1);
      expect(grouped, hasLength(1));
      expect(grouped.single.movementCount, 601);
      expect(grouped.single.amountCents, 100);
      expect((await query.read(jan)).total.movementCount, 601);
    },
  );

  test(
    'Desbordamiento directo SQLite, agregado, diferencia y cancelación exacta',
    () async {
      const max = 9223372036854775807;
      final root = await categories.create(name: 'Raíz', isIncome: false);
      final child = await categories.create(
        name: 'Hija',
        parentId: root.node.id,
      );
      final a = await real(root.node.id, max);
      final b = await real(child.node.id, 1);
      await expectLater(
        query.read(jan),
        throwsA(
          isA<MonthlyStatusFailure>().having(
            (e) => e.code,
            'overflow agregado',
            MonthlyStatusFailureCode.overflow,
          ),
        ),
      );
      await movements.delete(b.id);
      final planned = await budget(root.node.id, -1);
      await expectLater(
        query.read(jan),
        throwsA(
          isA<MonthlyStatusFailure>().having(
            (e) => e.code,
            'overflow diferencia',
            MonthlyStatusFailureCode.overflow,
          ),
        ),
      );
      await budgets.delete(planned.id);
      final same = await real(root.node.id, 1);
      await expectLater(
        movements.readMonthTotals(2026, 1),
        throwsA(isA<MovementTotalsOverflow>()),
      );
      await expectLater(query.read(jan), throwsA(isA<MonthlyStatusFailure>()));
      await real(root.node.id, -max);
      expect((await query.read(jan)).total.actualCents, 1);
      await movements.delete(same.id);
      await movements.delete(a.id);
      expect((await query.read(jan)).total.actualCents, -max);
    },
  );

  test(
    'Previsto y total general comprueban int64 y permiten compensación',
    () async {
      const max = 9223372036854775807;
      final root = await categories.create(name: 'Padre', isIncome: false);
      final a = await categories.create(name: 'Hija A', parentId: root.node.id);
      final b = await categories.create(name: 'Hija B', parentId: root.node.id);
      await budget(a.node.id, max);
      final extra = await budget(b.node.id, 1);
      await expectLater(
        query.read(jan),
        throwsA(
          isA<MonthlyStatusFailure>().having(
            (e) => e.code,
            'previsto',
            MonthlyStatusFailureCode.overflow,
          ),
        ),
      );
      await budgets.delete(extra.id);
      // Sin previstos para probar el total sin overflow de diferencias de fila.
      await budgets.delete((await budgets.list(jan)).single.id);
      final other = await categories.create(name: 'Otra raíz', isIncome: false);
      await real(root.node.id, max);
      final one = await real(other.node.id, 1);
      await expectLater(
        query.read(jan),
        throwsA(
          isA<MonthlyStatusFailure>().having(
            (e) => e.code,
            'total',
            MonthlyStatusFailureCode.overflow,
          ),
        ),
      );
      await movements.delete(one.id);
      await real(other.node.id, -max);
      expect((await query.read(jan)).total.actualCents, 0);
      expect((await query.read(jan)).total.movementCount, 2);
    },
  );

  test('Fallo de lectura entrega error, nunca cifras cero ficticias', () async {
    await db.customStatement('DROP TABLE budgets');
    await expectLater(
      query.read(jan),
      throwsA(
        isA<MonthlyStatusFailure>()
            .having(
              (e) => e.code,
              'código',
              MonthlyStatusFailureCode.persistence,
            )
            .having(
              (e) => e.message,
              'mensaje',
              'No se pudo consultar el estado del mes. Inténtalo de nuevo.',
            ),
      ),
    );
  });
}
