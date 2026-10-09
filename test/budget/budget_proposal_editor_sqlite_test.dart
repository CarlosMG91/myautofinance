import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/budget_proposal_factory.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/data/historical_csv_reader.dart';
import 'package:myautofinance/features/importing/historical_csv.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  test(
    'Caso H: edición, revisión, desglose y cancelación sin escrituras',
    () async {
      final db = LocalDatabase(
        NativeDatabase.memory(
          setup: (sqlite) => sqlite.execute('PRAGMA foreign_keys=ON'),
        ),
      );
      final invalidation = CategoryReadInvalidation();
      addTearDown(() async {
        await invalidation.close();
        await db.close();
      });
      final categories = createCategoryManagement(
        database: db,
        invalidation: invalidation,
      );
      final movements = SqliteMovementRepository(db);
      final budgets = SqliteBudgetRepository(db);
      final account = await SqliteAccountRepository(db).create(
        name: 'Cuenta sintética',
        kind: AccountKind.account,
        activeFrom: Month(1, 1),
        liquidity: Liquidity.liquid,
      );
      final csv = const HistoricalCsvReader().read(
        File('docs/ep-001/historico-ejemplo.csv').readAsBytesSync(),
      );
      expect(csv.isValid, isTrue);
      final nodes = <String, CategoryDetails>{};
      for (final record in csv.records) {
        String? parent;
        final names = record.categoryPath;
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
              accountId: account.id,
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
      final root = nodes['Alimentación']!.node.id;
      final child = nodes['Alimentación / Supermercado']!.node.id;
      final other = (await categories.create(
        name: 'Mercado sintético',
        parentId: root,
      )).node.id;
      final january = BudgetMonth(2027, 1);
      await budgets.create(
        BudgetInput(month: january, categoryId: root, amountCents: -99900),
      );
      final before = await _snapshot(db);
      final calculator = createBudgetProposalCalculator(
        database: db,
        invalidation: invalidation,
      );
      final original = await calculator.calculate(2026);
      final editor = BudgetProposalEditor(original);
      final sourceRow = editor.draft.sourceRows.singleWhere(
        (r) => r.categoryId == root && r.targetMonth.value == january.value,
      );
      expect(sourceRow.sourceAmountCents, -35025);
      expect(sourceRow.proposedAmountCents, -36000);
      editor.editAmount(month: january, categoryId: root, amountCents: -36100);
      editor.split(
        month: january,
        parentCategoryId: root,
        allocations: [
          BudgetProposalSplitAllocation(categoryId: child, amountCents: -36200),
          BudgetProposalSplitAllocation(categoryId: other, amountCents: 100),
        ],
      );
      expect(editor.draft.requiresSignReview, isTrue);
      editor.setSignsReviewed(true);
      expect(editor.validatedDraft().signsReviewed, isTrue);
      expect(await _snapshot(db), before);
      editor.cancel();
      final fresh = BudgetProposalEditor(await calculator.calculate(2026));
      expect(fresh.draft.signsReviewed, isFalse);
      expect(fresh.draft.requiresSignReview, isFalse);
      expect(
        fresh.draft.allocations
            .singleWhere(
              (a) => a.categoryId == root && a.month.value == january.value,
            )
            .amountCents,
        -36000,
      );
      expect(
        fresh.draft.allocations
            .singleWhere(
              (a) => a.categoryId == root && a.month.value == '2027-02-01',
            )
            .amountCents,
        -43000,
      );
      expect(
        fresh.draft.allocations
            .singleWhere(
              (a) => a.categoryId == root && a.month.value == '2027-03-01',
            )
            .amountCents,
        0,
      );
      expect(await _snapshot(db), before);
    },
  );
}

Future<Map<String, Object?>> _snapshot(LocalDatabase db) async {
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
