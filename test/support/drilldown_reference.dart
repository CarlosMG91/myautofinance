import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

/// MA-TSK-193 ejecutable. P07 va en febrero: en enero solaparía P02
/// después de mover OLD a HOG. P04 se reserva al fixture alternativo EP-001.
final class DrilldownReference {
  final categories = <String, String>{};
  final accounts = <String, String>{};
  final budgets = <String, BudgetRecord>{};
  final movements = <String, MovementRecord>{};

  Future<void> seed(
    LocalDatabase db,
    CategoryReadInvalidation invalidation,
  ) async {
    final management = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    for (final (name, parent) in [
      ('ING', null),
      ('HOG', null),
      ('ALQ', 'HOG'),
      ('ALI', null),
      ('SUP', 'ALI'),
      ('COMP', 'SUP'),
      ('OCIO', null),
      ('OLD', 'ALI'),
      ('NET', null),
      ('DUP-A', 'NET'),
      ('DUP-B', 'NET'),
      ('EMPTY', null),
    ]) {
      categories[name] = (await management.create(
        name: name.startsWith('DUP-') ? 'Otros' : name,
        parentId: categories[parent],
        isIncome: parent == null ? name == 'ING' : null,
      )).node.id;
    }
    for (final name in ['C1', 'C2']) {
      accounts[name] = (await SqliteAccountRepository(db).create(
        name: name,
        kind: AccountKind.account,
        activeFrom: Month(2025, 1),
        liquidity: Liquidity.liquid,
      )).id;
    }
    final planned = <ImportedBudget>[];
    for (final (name, month, category, cents) in [
      ('P01', 1, 'ING', 300000),
      ('P02', 1, 'HOG', -100000),
      ('P03', 1, 'COMP', -40000),
      ('P05', 2, 'ING', 300000),
      ('P06', 2, 'COMP', -40000),
      ('P07', 2, 'OLD', -700),
    ]) {
      planned.add(
        ImportedBudget(
          planned.length + 2,
          BudgetInput(
            month: BudgetMonth(2026, month),
            categoryId: categories[category]!,
            amountCents: cents,
            concept: name,
            discretion: 'Sintética',
          ),
        ),
      );
    }
    final real = <ImportedMovement>[];
    for (final (name, year, month, category, account, cents) in [
      ('R01', 2026, 1, 'ING', 'C1', 310000),
      ('R02', 2026, 1, 'ALQ', 'C1', -100000),
      ('R03', 2026, 1, 'COMP', 'C1', -35025),
      ('R04', 2026, 1, 'OCIO', 'C2', -1000),
      ('R05', 2026, 1, 'OCIO', 'C2', -1000),
      ('R06', 2026, 1, null, 'C1', -500),
      ('R07', 2026, 2, 'ING', 'C2', 302000),
      ('R08', 2026, 2, 'ALQ', 'C1', -100000),
      ('R09', 2026, 2, 'COMP', 'C1', -42010),
      ('R10', 2026, 2, 'OCIO', 'C2', 100),
      ('R11', 2025, 12, 'OLD', 'C1', -700),
      ('R12', 2026, 1, 'DUP-A', 'C1', 500),
      ('R13', 2026, 1, 'DUP-B', 'C2', -500),
      ('R14', 2026, 2, 'OCIO', 'C2', -100),
    ]) {
      real.add(
        ImportedMovement(
          real.length + 20,
          MovementInput(
            accountId: accounts[account]!,
            valueDate: ValueDate(year, month, 9),
            categoryId: categories[category],
            amountCents: cents,
            concept: name == 'R04' || name == 'R05' ? 'Café' : name,
            discretion: 'Sintética',
          ),
        ),
      );
    }
    await SqliteImportBatchRepository(db).create(
      sha256: 'd' * 64,
      source: ImportSource.historicalCsv,
      originalName: 'synthetic-drilldowns.csv',
      contractVersion: '1',
      movements: real,
      budgets: planned,
    );
    for (final record in await SqliteBudgetRepository(db).readYear(2026)) {
      budgets[record.data.concept!] = record;
    }
    var cafe = 4;
    for (final record in [
      ...await SqliteMovementRepository(db).readYear(2025),
      ...await SqliteMovementRepository(db).readYear(2026),
    ]) {
      final name = record.data.concept == 'Café'
          ? 'R0${cafe++}'
          : record.data.concept;
      movements[name] = record;
    }
    await management.move(categories['OLD']!, parentId: categories['HOG']);
    await management.archive(categories['OLD']!);
    for (final account in accounts.values) {
      await SqliteWealthRepository(db)
          .setValue(Month(2026, 1), account, 123456);
    }
  }

  // Árbol esperado declarado por la muestra, independiente del informe leído.
  Set<String> categoryIds(String? category, MovementCategoryScope scope) {
    if (category == null) return categories.values.toSet();
    final names = scope == MovementCategoryScope.direct
        ? [category]
        : switch (category) {
            'ALI' => ['ALI', 'SUP', 'COMP'],
            'SUP' => ['SUP', 'COMP'],
            'HOG' => ['HOG', 'ALQ', 'OLD'],
            'NET' => ['NET', 'DUP-A', 'DUP-B'],
            _ => [category],
          };
    return names.map((name) => categories[name]!).toSet();
  }
}
