import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/annual_actual_query_factory.dart';
import 'package:myautofinance/app/budget_factory.dart';
import 'package:myautofinance/app/monthly_status_query_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/navigation/budget_links.dart';
import 'package:myautofinance/app/navigation/movement_links.dart';
import 'package:myautofinance/features/actual_spending/actual_spending.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/monthly_status/monthly_status.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

import '../support/drilldown_reference.dart';

void main() {
  test(
    'MA-TSK-194: cada cifra de los tres informes concilia UUID y revisión',
    () async {
      final db = LocalDatabase(
        NativeDatabase.memory(setup: configureConnection),
      );
      final invalidation = CategoryReadInvalidation();
      addTearDown(db.close);
      addTearDown(invalidation.close);
      final fixture = DrilldownReference();
      await fixture.seed(db, invalidation);
      final source = createBudgetSource(db, invalidation);
      final reader = source.entries!;
      final repository = SqliteMovementRepository(db);
      final before = await db.readState();
      final annualBudget = await source.annual!.read(2026);
      final annualReal = await createAnnualActualQuery(
        database: db,
        invalidation: invalidation,
      ).read(2026);
      expect(annualBudget.annualTotal.amountCents, 419300);
      expect(annualReal.annualTotal.amountCents, 332465);

      Future<void> real(
        MovementListQuery query,
        int cents,
        int count,
        Set<String> ids,
      ) async {
        // Serializar y parsear el enlace público original, sin otra apertura.
        final q = MovementLinks.parse(
          MovementLinks.list(query),
          defaultMonth: Month(2026, 10),
        );
        final seen = <String>[];
        MovementCursor? cursor;
        do {
          final page = await repository.readPage(
            from: q.from,
            until: q.until,
            categoryId: q.categoryId,
            accountId: q.accountId,
            categoryScope: q.scope,
            unclassifiedOnly: q.unclassified,
            concept: q.concept,
            after: cursor,
            limit: 3,
          );
          expect(page.subtotalCents, cents);
          expect(page.totalCount, count);
          seen.addAll(page.records.map((r) => r.id));
          cursor = page.nextCursor;
        } while (cursor != null);
        expect(seen, unorderedEquals(ids));
        expect(
          seen.length,
          ids.length,
          reason: 'Sin doble conteo entre páginas',
        );
      }

      Future<void> planned(
        BudgetListQuery query,
        int cents,
        Set<String> ids,
      ) async {
        final result = await reader.readResult(
          BudgetLinks.parse(BudgetLinks.list(query)),
        );
        expect(result.datasetState.datasetId, before.datasetId);
        expect(result.datasetState.revision, before.revision);
        expect(result.subtotalCents, BigInt.from(cents));
        expect(result.totalCount, ids.length);
        final seen = <String>[];
        for (var offset = 0; offset < result.totalCount; offset += 3) {
          seen.addAll(
            result.page(offset: offset, limit: 3).map((e) => e.record.id),
          );
        }
        expect(seen, unorderedEquals(ids));
        expect(seen.length, ids.length);
      }

      Set<String> expectedReal(
        String? name,
        MovementCategoryScope scope,
        int? month, {
        bool unclassified = false,
      }) {
        final categories = fixture.categoryIds(name, scope);
        return fixture.movements.values
            .where(
              (r) =>
                  r.data.valueDate.value.startsWith('2026-') &&
                  (month == null ||
                      int.parse(r.data.valueDate.value.substring(5, 7)) ==
                          month) &&
                  (unclassified
                      ? r.data.categoryId == null
                      : name == null || categories.contains(r.data.categoryId)),
            )
            .map((r) => r.id)
            .toSet();
      }

      Set<String> expectedBudget(
        String? name,
        MovementCategoryScope scope,
        int? month,
      ) {
        final categories = fixture.categoryIds(name, scope);
        return fixture.budgets.values
            .where(
              (r) =>
                  (month == null ||
                      int.parse(r.data.month.value.substring(5, 7)) == month) &&
                  categories.contains(r.data.categoryId),
            )
            .map((r) => r.id)
            .toSet();
      }

      // Cada celda, incluso cero/vacío, rama/directo, archivadas y homónimas.
      for (final name in <String?>[null, ...fixture.categories.keys]) {
        final id = fixture.categories[name];
        for (final scope in MovementCategoryScope.values) {
          final budgetRow = name == null
              ? null
              : annualBudget.rows.where((r) => r.categoryId == id).firstOrNull;
          final realRow = name == null
              ? null
              : annualReal.rows.where((r) => r.categoryId == id).firstOrNull;
          for (final month in <int?>[
            null,
            ...List.generate(12, (i) => i + 1),
          ]) {
            final ids = expectedReal(name, scope, month);
            final total = name == null
                ? month == null
                      ? annualReal.annualTotal
                      : annualReal.months[month - 1]
                : month == null
                ? scope == MovementCategoryScope.direct
                      ? realRow?.directAnnualTotal
                      : realRow?.annualTotal
                : scope == MovementCategoryScope.direct
                ? realRow?.months[month - 1].direct
                : realRow?.months[month - 1].total;
            await real(
              AnnualActualDetail(
                year: 2026,
                month: month,
                categoryId: id,
                scope: scope,
              ).movements,
              total?.amountCents ?? 0,
              total?.movementCount ?? 0,
              ids,
            );
            final budgetIds = expectedBudget(name, scope, month);
            final totalBudget = name == null
                ? month == null
                      ? annualBudget.annualTotal
                      : annualBudget.months[month - 1]
                : month == null
                ? scope == MovementCategoryScope.direct
                      ? budgetRow?.ownAnnualTotal
                      : budgetRow?.annualTotal
                : scope == MovementCategoryScope.direct
                ? null
                : budgetRow?.months[month - 1].total;
            final own = month == null
                ? null
                : budgetRow?.months[month - 1].ownBudget;
            final cents =
                name != null &&
                    month != null &&
                    scope == MovementCategoryScope.direct
                ? own?.data.amountCents ?? 0
                : totalBudget?.amountCents ?? 0;
            await planned(
              month == null
                  ? BudgetListQuery.annual(2026, categoryId: id, scope: scope)
                  : BudgetListQuery(
                      month: BudgetMonth(2026, month),
                      categoryId: id,
                      scope: scope,
                    ),
              cents,
              budgetIds,
            );
            if (month != null) {
              final status = await createMonthlyStatusQuery(
                database: db,
                invalidation: invalidation,
              ).read(BudgetMonth(2026, month));
              final row = status.rows
                  .where((r) => r.categoryId == id)
                  .firstOrNull;
              final actual = name == null
                  ? status.total.actualCents
                  : scope == MovementCategoryScope.direct
                  ? row?.actualDirectCents ?? 0
                  : row?.totals.actualCents ?? 0;
              final detail = MonthlyFigureDetail(
                month: status.month,
                categoryId: id,
                scope: scope,
              );
              await real(detail.movements, actual, ids.length, ids);
              // Estado ofrece previsto agregado, independientemente de real directo.
              if (scope == MovementCategoryScope.branch) {
                await planned(
                  detail.budgets,
                  name == null
                      ? status.total.plannedCents
                      : row?.totals.plannedCents ?? 0,
                  budgetIds,
                );
                expect(
                  (name == null ? status.total : row?.totals)
                          ?.differenceCents ??
                      0,
                  actual - cents,
                );
              }
            }
          }
        }
      }
      for (var month = 1; month <= 12; month++) {
        final total = annualReal.unclassified.months[month - 1].total;
        await real(
          AnnualActualDetail(
            year: 2026,
            month: month,
            unclassified: true,
          ).movements,
          total.amountCents,
          total.movementCount,
          expectedReal(
            null,
            MovementCategoryScope.branch,
            month,
            unclassified: true,
          ),
        );
      }
      await real(
        MovementListQuery(
          from: ValueDate(2026, 1, 1),
          until: ValueDate(2027, 1, 1),
          accountId: fixture.accounts['C2'],
        ),
        299500,
        6,
        {
          'R04',
          'R05',
          'R07',
          'R10',
          'R13',
          'R14',
        }.map((n) => fixture.movements[n]!.id).toSet(),
      );
      await planned(
        BudgetListQuery.range(
          month: BudgetMonth(2026, 10),
          firstMonth: BudgetMonth(2025, 12),
          lastMonth: BudgetMonth(2026, 2),
          categoryId: fixture.categories['OLD'],
        ),
        -700,
        {fixture.budgets['P07']!.id},
      );
      expect(annualBudget.datasetState.revision, before.revision);
      expect(annualReal.datasetState.revision, before.revision);
      final after = await db.readState();
      expect(after.datasetId, before.datasetId);
      expect(after.revision, before.revision, reason: 'Consultar no escribe');
    },
  );
}
