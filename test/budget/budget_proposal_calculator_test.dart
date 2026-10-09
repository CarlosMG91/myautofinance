import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/budget_proposal_factory.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/core/persistence/unit_of_work.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/data/historical_csv_reader.dart';
import 'package:myautofinance/features/importing/historical_csv.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  late LocalDatabase db;
  late CategoryManagement categories;
  late CategoryReadInvalidation invalidation;
  late SqliteMovementRepository movements;
  late SqliteBudgetRepository budgets;
  late BudgetProposalCalculator calculator;
  late String accountId;

  setUp(() async {
    db = LocalDatabase(
      NativeDatabase.memory(
        setup: (sqlite) => sqlite.execute('PRAGMA foreign_keys=ON'),
      ),
    );
    invalidation = CategoryReadInvalidation();
    categories = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    movements = SqliteMovementRepository(db);
    budgets = SqliteBudgetRepository(db);
    calculator = createBudgetProposalCalculator(
      database: db,
      invalidation: invalidation,
    );
    accountId = (await SqliteAccountRepository(db).create(
      name: 'Cuenta sintética',
      kind: AccountKind.account,
      activeFrom: Month(1, 1),
      liquidity: Liquidity.liquid,
    )).id;
  });
  tearDown(() async {
    await invalidation.close();
    await db.close();
  });

  Future<MovementRecord> real(
    String? category,
    int cents, {
    int year = 2026,
    int month = 1,
    int day = 15,
  }) => movements.create(
    MovementInput(
      accountId: accountId,
      valueDate: ValueDate(year, month, day),
      concept: 'Real sintético',
      categoryId: category,
      amountCents: cents,
    ),
  );
  BudgetProposalRow row(BudgetProposalDraft draft, String id, int month) =>
      draft.sourceRows.singleWhere(
        (r) =>
            r.categoryId == id &&
            r.targetMonth.value.substring(5, 7) ==
                month.toString().padLeft(2, '0'),
      );
  Matcher failure(BudgetProposalFailureCode code) =>
      isA<BudgetProposalFailure>().having((e) => e.code, 'código', code);

  Future<Map<String, Object?>> snapshot() async {
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
        )
        .get();
    return {
      for (final table in tables)
        table.read<String>(
          'name',
        ): (await db
                .customSelect(
                  'SELECT * FROM "${table.read<String>('name')}" ORDER BY rowid',
                )
                .get())
            .map((r) => r.data)
            .toList(),
    };
  }

  test(
    'Caso H completo con CSV EP-001: raíces, doce meses y ninguna escritura',
    () async {
      final csv = const HistoricalCsvReader().read(
        File('docs/ep-001/historico-ejemplo.csv').readAsBytesSync(),
      );
      expect(csv.isValid, isTrue);
      final nodes = <String, CategoryDetails>{};
      for (final record in csv.records) {
        final names = record.categoryPath;
        String? parent;
        for (var index = 0; index < names.length; index++) {
          final path = names.take(index + 1).join(' / ');
          final category = nodes[path] ??= await categories.create(
            name: names[index],
            parentId: parent,
            isIncome: parent == null ? names.first == 'Ingresos' : null,
          );
          parent = category.node.id;
        }
        if (record.type == HistoricalCsvType.real) {
          await movements.create(
            MovementInput(
              accountId: accountId,
              valueDate: ValueDate.parse(record.date),
              concept: record.concept,
              categoryId: parent,
              amountCents: record.csvAmountCents,
            ),
          );
        } else {
          await budgets.create(
            BudgetInput.fromHistoricalCsv(
              month: BudgetMonth.parse(record.date),
              categoryId: parent!,
              csvAmountCents: record.csvAmountCents,
            ),
          );
        }
      }
      await budgets.create(
        BudgetInput(
          month: BudgetMonth(2027, 1),
          categoryId: nodes['Alimentación / Supermercado']!.node.id,
          amountCents: -42000,
        ),
      );
      final before = await snapshot();
      final draft = await calculator.calculate(2026);
      expect(await snapshot(), before);
      expect(draft.sourceYear, 2026);
      expect(draft.targetYear, 2027);
      expect(draft.sourceRows, hasLength(60));
      expect(draft.allocations, hasLength(60));
      expect(draft.includedScopes, hasLength(60));
      expect(draft.excludedReals, isEmpty);
      expect(draft.requiresSignReview, isFalse);
      const expected = {
        'Ingresos': [310000, 302000],
        'Vivienda': [-100000, -100000],
        'Alimentación': [-36000, -43000],
        'Ahorro': [-50000, -50000],
        'Ocio': [-2000, 0],
      };
      for (final entry in expected.entries) {
        final id = nodes[entry.key]!.node.id;
        for (var month = 1; month <= 12; month++) {
          final proposed = row(draft, id, month);
          expect(
            proposed.proposedAmountCents,
            month <= 2 ? entry.value[month - 1] : 0,
          );
          expect(proposed.categoryPath, entry.key);
          expect(proposed.sourceMonth.value.startsWith('2026'), isTrue);
          expect(proposed.targetMonth.value.startsWith('2027'), isTrue);
        }
      }
      expect(
        row(draft, nodes['Alimentación']!.node.id, 1).sourceAmountCents,
        -35025,
      );
      expect(
        row(draft, nodes['Alimentación']!.node.id, 2).sourceAmountCents,
        -42010,
      );
      expect(row(draft, nodes['Ocio']!.node.id, 1).sourceMovementCount, 2);
      expect(row(draft, nodes['Ingresos']!.node.id, 3).hasSourceReals, isFalse);
      expect(draft.basis.sourceReals, hasLength(10));
      expect(draft.basis.targetBudgets.single.data.amountCents, -42000);
      for (final collection in <List<Object?>>[
        draft.sourceRows,
        draft.allocations,
        draft.includedScopes,
        draft.excludedReals,
        draft.basis.categories,
        draft.basis.sourceReals,
        draft.basis.targetBudgets,
      ]) {
        expect(() => collection.clear(), throwsUnsupportedError);
      }
    },
  );

  test('Suma directa y tres niveles antes de redondear, abonos y transferencias por signo', () async {
    final root = await categories.create(
      name: 'Ahorro y transferencias',
      isIncome: false,
    );
    final child = await categories.create(name: 'Rama', parentId: root.node.id);
    final leaf = await categories.create(name: 'Hoja', parentId: child.node.id);
    await real(root.node.id, -1001);
    await real(child.node.id, -1001);
    await real(leaf.node.id, 1002);
    await real(root.node.id, -1, month: 2);
    await real(child.node.id, 1, month: 2);
    await real(root.node.id, 1001, month: 3);
    await real(root.node.id, -9000, year: 2025);
    await real(root.node.id, -9000, year: 2027);
    final draft = await calculator.calculate(2026);
    expect(draft.sourceRows, hasLength(12));
    expect(row(draft, root.node.id, 1).sourceAmountCents, -1000);
    expect(row(draft, root.node.id, 1).proposedAmountCents, -1000);
    expect(row(draft, root.node.id, 2).sourceAmountCents, 0);
    expect(row(draft, root.node.id, 2).hasSourceReals, isTrue);
    expect(row(draft, root.node.id, 2).proposedAmountCents, 0);
    expect(row(draft, root.node.id, 3).proposedAmountCents, 2000);
    expect(row(draft, root.node.id, 4).hasSourceReals, isFalse);
    expect(
      draft.allocations.every((r) => r.categoryId == root.node.id),
      isTrue,
    );
    expect(draft.basis.sourceReals, hasLength(6));
  });

  test('Archivados bajo raíz activa suman; Sin clasificar y raíz archivada se excluyen por UUID', () async {
    final root = await categories.create(name: 'Duplicada', isIncome: false);
    final oldChild = await categories.create(
      name: 'Histórica',
      parentId: root.node.id,
    );
    final oldRoot = await categories.create(name: 'Duplicada', isIncome: true);
    final oldLeaf = await categories.create(
      name: 'Histórica',
      parentId: oldRoot.node.id,
    );
    await real(root.node.id, -100);
    final included = await real(oldChild.node.id, -1901);
    final excludedRoot = await real(oldRoot.node.id, 20000);
    final excludedLeaf = await real(oldLeaf.node.id, -123);
    final unclassified = await real(null, 9876);
    await budgets.create(
      BudgetInput(
        month: BudgetMonth(2027, 2),
        categoryId: oldChild.node.id,
        amountCents: -1000,
      ),
    );
    await budgets.create(
      BudgetInput(
        month: BudgetMonth(2027, 1),
        categoryId: oldRoot.node.id,
        amountCents: 1234,
      ),
    );
    await categories.archive(oldChild.node.id);
    await categories.archive(oldRoot.node.id);
    final before = await snapshot();
    final draft = await calculator.calculate(2026);
    expect(await snapshot(), before);
    expect(row(draft, root.node.id, 1).sourceAmountCents, -2001);
    expect(row(draft, root.node.id, 1).proposedAmountCents, -3000);
    expect(
      draft.allocations.every((r) => r.categoryId == root.node.id),
      isTrue,
    );
    expect(draft.basis.targetBudgets.single.data.categoryId, oldChild.node.id);
    expect(draft.basis.sourceReals.map((r) => r.id), contains(included.id));
    expect(
      draft.excludedReals.map((r) => r.real.id),
      unorderedEquals([excludedRoot.id, excludedLeaf.id, unclassified.id]),
    );
    final none = draft.excludedReals.singleWhere(
      (r) => r.real.id == unclassified.id,
    );
    expect(none.real.categoryId, isNull);
    expect(none.categoryPath, isNull);
    expect(none.reason, BudgetProposalExclusionReason.unclassified);
    final old = draft.excludedReals.singleWhere(
      (r) => r.real.id == excludedLeaf.id,
    );
    expect(old.categoryPath, 'Duplicada / Histórica');
    expect(old.reason, BudgetProposalExclusionReason.archivedRoot);
    expect(draft.requiresSignReview, isFalse);
    expect(draft.signsReviewed, isFalse);
  });

  test('Solo signos netos atípicos exigen revisión; céntimo y múltiplo exacto conservan signo', () async {
    final income = await categories.create(name: 'Ingresos', isIncome: true);
    final expense = await categories.create(name: 'Salidas', isIncome: false);
    await real(income.node.id, -1);
    await real(expense.node.id, 1);
    await real(income.node.id, 302100, month: 2);
    await real(expense.node.id, -1000, month: 2);
    final draft = await calculator.calculate(2026);
    expect(row(draft, income.node.id, 1).proposedAmountCents, -1000);
    expect(row(draft, expense.node.id, 1).proposedAmountCents, 1000);
    expect(row(draft, income.node.id, 2).proposedAmountCents, 303000);
    expect(row(draft, expense.node.id, 2).proposedAmountCents, -1000);
    expect(draft.sourceRows.where((r) => r.requiresSignReview), hasLength(2));
    expect(draft.requiresSignReview, isTrue);
    expect(draft.signsReviewed, isFalse);
  });

  test(
    'Años civiles extremos y error claro para 9999; árbol vacío sin escrituras',
    () async {
      for (final sourceYear in [1, 9998]) {
        final result = await calculator.calculate(sourceYear);
        expect(result.targetYear, sourceYear + 1);
        expect(result.allocations, isEmpty);
      }
      final root = await categories.create(name: 'Límite', isIncome: false);
      await real(root.node.id, -1234, year: 9998, month: 12, day: 31);
      final result = await calculator.calculate(9998);
      expect(result.allocations.last.month.value, '9999-12-01');
      expect(result.allocations.last.amountCents, -2000);
      final before = await snapshot();
      for (final year in [-1, 0, 9999, 10000]) {
        await expectLater(
          calculator.calculate(year),
          throwsA(failure(BudgetProposalFailureCode.invalidSourceYear)),
        );
      }
      await expectLater(
        calculator.calculate(9999),
        throwsA(
          isA<BudgetProposalFailure>().having(
            (e) => e.message,
            'mensaje',
            'El año 9999 no tiene un año siguiente válido.',
          ),
        ),
      );
      expect(await snapshot(), before);
    },
  );

  test('BigInt permite cancelación tras intermedio fuera de int64', () async {
    final root = await categories.create(name: 'Exactitud', isIncome: true);
    const limit = 9223372036854775807;
    await real(root.node.id, limit, day: 1);
    await real(root.node.id, limit, day: 2);
    await real(root.node.id, -limit, day: 3);
    await real(root.node.id, -limit + 1, day: 4);
    final draft = await calculator.calculate(2026);
    expect(row(draft, root.node.id, 1).sourceAmountCents, 1);
    expect(row(draft, root.node.id, 1).proposedAmountCents, 1000);
    await real(root.node.id, 9223372036854775000, month: 2);
    await real(root.node.id, -9223372036854775000, month: 3);
    final exact = await calculator.calculate(2026);
    expect(
      row(exact, root.node.id, 2).proposedAmountCents,
      9223372036854775000,
    );
    expect(
      row(exact, root.node.id, 3).proposedAmountCents,
      -9223372036854775000,
    );
  });

  for (final amounts in <List<int>>[
    [9223372036854775807, 1],
    [-9223372036854775808, -1],
    [9223372036854775807],
    [-9223372036854775808],
  ]) {
    test('Rechaza desbordamiento de agregado o redondeo: $amounts', () async {
      final root = await categories.create(
        name: 'Desbordamiento',
        isIncome: false,
      );
      for (final amount in amounts) {
        await real(root.node.id, amount);
      }
      final before = await snapshot();
      await expectLater(
        calculator.calculate(2026),
        throwsA(failure(BudgetProposalFailureCode.overflow)),
      );
      expect(await snapshot(), before);
    });
  }

  test('Base de revalidación detecta altas/bajas/importes/fechas/categorías aunque no cambie el neto', () async {
    final root = await categories.create(name: 'Salidas', isIncome: false);
    final child = await categories.create(name: 'Hijo', parentId: root.node.id);
    final movement = await real(child.node.id, -1001);
    Future<BudgetProposalBasis> basis() async =>
        (await calculator.calculate(2026)).basis;
    final original = await basis();
    expect(original.hasSameRelevantData(await basis()), isTrue);
    final offsetA = await real(root.node.id, 100);
    final offsetB = await real(root.node.id, -100);
    expect(original.hasSameRelevantData(await basis()), isFalse);
    await movements.delete(offsetA.id);
    await movements.delete(offsetB.id);
    expect(original.hasSameRelevantData(await basis()), isTrue);
    await movements.edit(
      movement.id,
      MovementInput(
        accountId: accountId,
        valueDate: ValueDate(2026, 1, 15),
        concept: 'Otro concepto',
        categoryId: child.node.id,
        amountCents: -1001,
      ),
    );
    expect(original.hasSameRelevantData(await basis()), isTrue);
    await movements.edit(
      movement.id,
      MovementInput(
        accountId: accountId,
        valueDate: ValueDate(2026, 1, 16),
        concept: 'Otro concepto',
        categoryId: child.node.id,
        amountCents: -1001,
      ),
    );
    expect(original.hasSameRelevantData(await basis()), isFalse);
    await movements.edit(
      movement.id,
      MovementInput(
        accountId: accountId,
        valueDate: ValueDate(2026, 1, 15),
        concept: 'Otro concepto',
        categoryId: root.node.id,
        amountCents: -1001,
      ),
    );
    expect(original.hasSameRelevantData(await basis()), isFalse);
    await movements.edit(
      movement.id,
      MovementInput(
        accountId: accountId,
        valueDate: ValueDate(2026, 1, 15),
        concept: 'Otro concepto',
        categoryId: child.node.id,
        amountCents: -1002,
      ),
    );
    expect(original.hasSameRelevantData(await basis()), isFalse);
  });

  test('Base de revalidación detecta árbol y partidas destino, ignora otros años y presupuesto fuente', () async {
    final root = await categories.create(name: 'Salidas', isIncome: false);
    final child = await categories.create(name: 'Hijo', parentId: root.node.id);
    final original = (await calculator.calculate(2026)).basis;
    await budgets.create(
      BudgetInput(
        month: BudgetMonth(2026, 1),
        categoryId: root.node.id,
        amountCents: -123,
      ),
    );
    await real(root.node.id, -10, year: 2025);
    await real(root.node.id, -10, year: 2027);
    expect(
      original.hasSameRelevantData((await calculator.calculate(2026)).basis),
      isTrue,
    );
    final target = await budgets.create(
      BudgetInput(
        month: BudgetMonth(2027, 12),
        categoryId: child.node.id,
        amountCents: 0,
      ),
    );
    expect(
      original.hasSameRelevantData((await calculator.calculate(2026)).basis),
      isFalse,
    );
    await budgets.delete(target.id);
    expect(
      original.hasSameRelevantData((await calculator.calculate(2026)).basis),
      isTrue,
    );
    await categories.rename(child.node.id, name: 'Renombrada');
    expect(
      original.hasSameRelevantData((await calculator.calculate(2026)).basis),
      isFalse,
    );
    final renamed = (await calculator.calculate(2026)).basis;
    await categories.archive(child.node.id);
    expect(
      renamed.hasSameRelevantData((await calculator.calculate(2026)).basis),
      isFalse,
    );
    final current = (await calculator.calculate(2026)).basis;
    final otherDataset = BudgetProposalBasis(
      sourceYear: 2026,
      datasetState: DatasetState(
        datasetId: 'otro-dataset',
        revision: current.datasetState.revision,
      ),
      categories: current.categories,
      sourceReals: current.sourceReals,
      targetBudgets: current.targetBudgets,
    );
    expect(current.hasSameRelevantData(otherDataset), isFalse);
  });

  test('Errores de lectura no se presentan como propuesta de ceros', () async {
    await categories.create(name: 'Activa', isIncome: true);
    await db.customStatement('DROP TABLE movements');
    await expectLater(
      calculator.calculate(2026),
      throwsA(failure(BudgetProposalFailureCode.persistence)),
    );
  });
}
