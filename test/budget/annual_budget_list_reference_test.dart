import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/annual_budget_query_factory.dart';
import 'package:myautofinance/app/budget_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/movements/movements.dart';

import '../support/recovery_reference.dart';

void main() {
  test('Caso E: 48 orígenes, anual +13200 EUR y mensual +1100 EUR coinciden con matriz', () async {
    final db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    final invalidation = CategoryReadInvalidation();
    try {
      await seedRecoveryReference(db);
      final before = await db.readState();
      final reader = createBudgetSource(db, invalidation).entries!;
      final annual = await createAnnualBudgetQuery(
        database: db,
        invalidation: invalidation,
      ).read(2026);
      final entries = await reader.read(
        BudgetListQuery.annual(2026, focusedMonth: 10),
      );
      expect(entries, hasLength(48));
      expect(
        entries.map((e) => e.record.id).toSet(),
        annual.annualTotal.budgetIds.toSet(),
      );
      expect(
        entries.fold<int>(0, (sum, e) => sum + e.record.data.amountCents),
        1320000,
      );
      for (var month = 1; month <= 12; month++) {
        final monthly = await reader.read(
          BudgetListQuery(month: BudgetMonth(2026, month)),
        );
        expect(monthly, hasLength(4));
        expect(
          monthly.fold<int>(0, (sum, e) => sum + e.record.data.amountCents),
          110000,
        );
        expect(
          monthly.map((e) => e.record.id).toSet(),
          annual.months[month - 1].budgetIds.toSet(),
        );
      }
      for (final row in annual.rows) {
        final branch = await reader.read(
          BudgetListQuery.annual(
            2026,
            focusedMonth: 10,
            categoryId: row.categoryId,
          ),
        );
        expect(
          branch.map((e) => e.record.id).toSet(),
          row.annualTotal.budgetIds.toSet(),
        );
        expect(
          branch.fold<int>(0, (sum, e) => sum + e.record.data.amountCents),
          row.annualTotal.amountCents,
        );
      }
      expect((await db.readState()).revision, before.revision);
    } finally {
      await invalidation.close();
      await db.close();
    }
  });
}
