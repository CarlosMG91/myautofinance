import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_read_unit_of_work.dart';
import 'package:myautofinance/app/monthly_status_query_factory.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/monthly_status/monthly_status.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:sqlite3/sqlite3.dart';

final class _BeforeRead implements MonthlyMovementTotalsReader {
  const _BeforeRead(this.reader, this.action);
  final MonthlyMovementTotalsReader reader;
  final Future<void> Function() action;
  @override
  Future<List<MonthlyMovementTotal>> readMonthTotals(
    int year,
    int month,
  ) async {
    await action();
    return reader.readMonthTotals(year, month);
  }
}

void main() {
  test(
    'Snapshot serializa otra conexión: árbol, presupuesto, reales y revisión',
    () async {
      final directory = await Directory.systemTemp.createTemp('estado-158-');
      final file = File('${directory.path}/sintetico.sqlite');
      final previousWarning =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      LocalDatabase open() =>
          LocalDatabase(NativeDatabase(file, setup: configureConnection));
      final db = open();
      final invalidation = CategoryReadInvalidation();
      final jan = BudgetMonth(2026, 1);
      try {
        final categories = createCategoryManagement(
          database: db,
          invalidation: invalidation,
        );
        final root = await categories.create(name: 'Antes', isIncome: false);
        final account = await SqliteAccountRepository(db).create(
          name: 'Sintética',
          kind: AccountKind.account,
          activeFrom: Month(2026, 1),
          liquidity: Liquidity.liquid,
        );
        final budgets = SqliteBudgetRepository(db);
        final budget = await budgets.create(
          BudgetInput(month: jan, categoryId: root.node.id, amountCents: 100),
        );
        final movements = SqliteMovementRepository(db);
        final real = await movements.create(
          MovementInput(
            accountId: account.id,
            valueDate: ValueDate(2026, 1, 31),
            concept: 'Sintético',
            amountCents: 120,
            categoryId: root.node.id,
          ),
        );
        final before = await db.readState();
        final competing = sqlite3.open(file.path);
        try {
          final query = MonthlyStatusQuery(
            movements: _BeforeRead(movements, () async {
              // Se intenta adquirir escritura ENTRE presupuesto y reales.
              expect(
                () => competing.execute('BEGIN IMMEDIATE'),
                throwsA(
                  isA<SqliteException>().having(
                    (e) => e.resultCode,
                    'SQLITE_BUSY',
                    5,
                  ),
                ),
              );
            }),
            budgets: budgets,
            categories: categories,
            unitOfWork: SqliteReadUnitOfWork(db),
          );
          final captured = await query.read(jan);
          expect(captured.rows.single.category.path, 'Antes');
          expect(captured.total.plannedCents, 100);
          expect(captured.total.actualCents, 120);
          expect(captured.datasetState.revision, before.revision);
          // El snapshot ha soltado el bloqueo al devolver el resultado.
          competing.execute('BEGIN IMMEDIATE');
          competing.execute('ROLLBACK');
          final writer = open();
          try {
            await writer.run(() async {
              await SqliteBudgetRepository(writer).edit(
                budget.id,
                BudgetInput(
                  month: jan,
                  categoryId: root.node.id,
                  amountCents: 200,
                ),
              );
              await SqliteMovementRepository(writer).edit(
                real.id,
                MovementInput(
                  accountId: account.id,
                  valueDate: real.data.valueDate,
                  concept: 'Sintético',
                  amountCents: 230,
                  categoryId: root.node.id,
                ),
              );
              await writer.customStatement(
                'UPDATE categories SET name=? WHERE id=?',
                ['Después', root.node.id],
              );
            });
          } finally {
            await writer.close();
          }
          invalidation.invalidate();
          final fresh = await createMonthlyStatusQuery(
            database: db,
            invalidation: invalidation,
          ).read(jan);
          expect(fresh.rows.single.category.path, 'Después');
          expect(fresh.total.plannedCents, 200);
          expect(fresh.total.actualCents, 230);
          expect(fresh.datasetState.revision, before.revision + 1);
          expect(captured.rows.single.category.path, 'Antes');
          expect(captured.total.actualCents, 120);
        } finally {
          competing.close();
        }
      } finally {
        await db.close();
        await invalidation.close();
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'Invalidación durante lectura descarta el resultado y permite releer',
    () async {
      final db = LocalDatabase(
        NativeDatabase.memory(setup: configureConnection),
      );
      final invalidation = CategoryReadInvalidation();
      try {
        final categories = createCategoryManagement(
          database: db,
          invalidation: invalidation,
        );
        final jan = BudgetMonth(2026, 1);
        final query = MonthlyStatusQuery(
          movements: _BeforeRead(
            SqliteMovementRepository(db),
            () async => invalidation.invalidate(),
          ),
          budgets: SqliteBudgetRepository(db),
          categories: categories,
          unitOfWork: SqliteReadUnitOfWork(db),
        );
        await expectLater(
          query.read(jan),
          throwsA(
            isA<MonthlyStatusFailure>().having(
              (e) => e.code,
              'invalidación',
              MonthlyStatusFailureCode.invalidated,
            ),
          ),
        );
        final fresh = await createMonthlyStatusQuery(
          database: db,
          invalidation: invalidation,
        ).read(jan);
        expect(fresh.categoryGeneration, invalidation.generation);
        expect(fresh.total.hasMovements, isFalse);
      } finally {
        await db.close();
        await invalidation.close();
      }
    },
  );

  test(
    'Rollback de lectura tras error libera la conexión para reintentar',
    () async {
      final db = LocalDatabase(
        NativeDatabase.memory(setup: configureConnection),
      );
      final invalidation = CategoryReadInvalidation();
      try {
        final query = MonthlyStatusQuery(
          movements: _BeforeRead(
            SqliteMovementRepository(db),
            () async => throw StateError('fallo sintético'),
          ),
          budgets: SqliteBudgetRepository(db),
          categories: createCategoryManagement(
            database: db,
            invalidation: invalidation,
          ),
          unitOfWork: SqliteReadUnitOfWork(db),
        );
        await expectLater(
          query.read(BudgetMonth(2026, 1)),
          throwsA(isA<MonthlyStatusFailure>()),
        );
        await createCategoryManagement(
          database: db,
          invalidation: invalidation,
        ).create(name: 'Reintento', isIncome: false);
        final fresh = await createMonthlyStatusQuery(
          database: db,
          invalidation: invalidation,
        ).read(BudgetMonth(2026, 1));
        expect(fresh.rows.single.category.path, 'Reintento');
      } finally {
        await db.close();
        await invalidation.close();
      }
    },
  );
}
