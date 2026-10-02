import 'package:myautofinance/app/data/sqlite/local_database.dart'
    show LocalDatabase;
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

// Datos sintéticos de los casos A–G de EP-001, ya normalizados.
Future<String> seedRecoveryReference(LocalDatabase db) async {
  late CategoryRepository categories;
  late WealthRepository wealth;
  late AccountRepository accounts;
  late String mainAccount, savings, portfolio, debt;
  late Map<String, String> nodes;
  final jan = Month(2026, 1);

  categories = SqliteCategoryRepository(db);
  wealth = SqliteWealthRepository(db);
  accounts = SqliteAccountRepository(db);
  nodes = {};
  // Misma jerarquía y registros que los casos A–G de EP-001.
  for (final root in [
    'Ingresos',
    'Vivienda',
    'Alimentación',
    'Ahorro',
    'Ocio',
  ]) {
    nodes[root] = (await categories.create(
      name: root,
      isIncome: root == 'Ingresos',
    )).id;
  }
  for (final pair in {
    'Salario': 'Ingresos',
    'Alquiler': 'Vivienda',
    'Supermercado': 'Alimentación',
    'Cuenta de ahorro': 'Ahorro',
    'Compra semanal': 'Supermercado',
  }.entries) {
    nodes[pair.key] = (await categories.create(
      name: pair.key,
      parentId: nodes[pair.value],
    )).id;
  }
  Future<String> account(
    String name,
    AccountKind kind,
    Liquidity? liquidity,
  ) async => (await accounts.create(
    name: name,
    kind: kind,
    activeFrom: jan,
    liquidity: liquidity,
  )).id;
  mainAccount = await account(
    'Cuenta principal',
    AccountKind.account,
    Liquidity.liquid,
  );
  savings = await account(
    'Cuenta de ahorro',
    AccountKind.account,
    Liquidity.liquid,
  );
  portfolio = await account('Cartera', AccountKind.portfolio, Liquidity.medium);
  debt = await account('Deuda familiar', AccountKind.debt, null);
  final importedBudgets = <ImportedBudget>[];
  for (var month = 1; month <= 12; month++) {
    for (final entry in {
      'Salario': 300000,
      'Alquiler': -100000,
      'Compra semanal': -40000,
      'Cuenta de ahorro': -50000,
    }.entries) {
      importedBudgets.add(
        ImportedBudget(
          importedBudgets.length + 2,
          BudgetInput(
            month: BudgetMonth(2026, month),
            categoryId: nodes[entry.key]!,
            amountCents: entry.value,
          ),
        ),
      );
    }
  }
  final importedMovements = <ImportedMovement>[];
  for (var month = 1; month <= 2; month++) {
    for (final entry in {
      'Salario': month == 1 ? 310000 : 302000,
      'Alquiler': -100000,
      'Compra semanal': month == 1 ? -35025 : -42010,
      'Cuenta de ahorro': -50000,
    }.entries) {
      importedMovements.add(
        ImportedMovement(
          importedMovements.length + 50,
          MovementInput(
            accountId: mainAccount,
            valueDate: ValueDate(2026, month, 5 + importedMovements.length % 4),
            concept: entry.key,
            categoryId: nodes[entry.key],
            amountCents: entry.value,
            discretion: entry.key == 'Compra semanal' ? 'Discrecional' : null,
          ),
        ),
      );
    }
    if (month == 1) {
      for (var i = 0; i < 2; i++) {
        importedMovements.add(
          ImportedMovement(
            importedMovements.length + 50,
            MovementInput(
              accountId: mainAccount,
              valueDate: ValueDate(2026, 1, 9),
              concept: 'Café',
              categoryId: nodes['Ocio'],
              amountCents: -1000,
            ),
          ),
        );
      }
    }
  }
  await SqliteImportBatchRepository(db).create(
    sha256: 'a' * 64,
    source: ImportSource.historicalCsv,
    originalName: 'synthetic.csv',
    contractVersion: '1',
    movements: importedMovements,
    budgets: importedBudgets,
  );
  for (final entry in {
    mainAccount: 600000,
    savings: 300000,
    portfolio: 1000000,
    debt: 500000,
  }.entries) {
    await wealth.setValue(jan, entry.key, entry.value);
  }

  return mainAccount;
}
