import 'package:drift/drift.dart' show Variable;

import '../../../features/budget/budget.dart';
import '../../../features/importing/importing.dart';
import '../../../features/movements/movements.dart';
import 'local_database.dart';
import 'sqlite_account_repository.dart';
import 'sqlite_budget_repository.dart';
import 'sqlite_category_repository.dart';
import 'sqlite_movement_repository.dart';

/// Lee catálogos y meses completos sobre la misma instantánea SQLite.
/// No usa writeTransaction ni incrementa la revisión local.
final class SqliteImportPreviewSource implements ImportPreviewSource {
  const SqliteImportPreviewSource(this.database);
  final LocalDatabase database;

  @override
  Future<ImportPreviewSnapshot> read(ImportSession session) =>
      database.transaction(() async {
        final accounts = await SqliteAccountRepository(database).list();
        final categories = await SqliteCategoryRepository(database).list();
        final batches = await database
            .customSelect(
              'SELECT id FROM import_batches WHERE content_sha256=?',
              variables: [Variable(session.file.sha256)],
            )
            .get();
        final movementMonths = <String>{};
        final budgetMonths = <String>{};
        for (final row in session.interpretation.rows) {
          switch (row) {
            case InterpretedMovement():
              movementMonths.add(row.valueDate.value.substring(0, 7));
            case InterpretedBudget():
              budgetMonths.add(row.month.value);
          }
        }
        final movements = <MovementRecord>[];
        final budgets = <BudgetRecord>[];
        for (final month in movementMonths) {
          movements.addAll(
            await SqliteMovementRepository(database).readMonth(
              int.parse(month.substring(0, 4)),
              int.parse(month.substring(5, 7)),
            ),
          );
        }
        for (final month in budgetMonths) {
          budgets.addAll(
            await SqliteBudgetRepository(database)
                .list(BudgetMonth.parse(month)),
          );
        }
        return ImportPreviewSnapshot(
          accounts: accounts,
          categories: categories,
          movements: movements,
          budgets: budgets,
          sameFileBatchId: batches.isEmpty
              ? null
              : batches.single.read<String>('id'),
        );
      });
}
