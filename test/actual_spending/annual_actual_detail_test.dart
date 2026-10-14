import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/navigation/movement_links.dart';
import 'package:myautofinance/features/actual_spending/actual_spending.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  test('Lista paginada conserva directos, descendientes, NULL, duplicados y cero neto', () async {
    final db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    final invalidation = CategoryReadInvalidation();
    addTearDown(() async {
      await invalidation.close();
      await db.close();
    });
    final categories = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    final root = (await categories.create(
      name: 'Raíz',
      isIncome: false,
    )).node.id;
    final child = (await categories.create(
      name: 'Hija',
      parentId: root,
    )).node.id;
    final leaf = (await categories.create(
      name: 'Hoja',
      parentId: child,
    )).node.id;
    final sibling = (await categories.create(
      name: 'Otra',
      isIncome: true,
    )).node.id;
    final accounts = SqliteAccountRepository(db);
    Future<String> account() async => (await accounts.create(
      name: 'Cuenta sintética',
      kind: AccountKind.account,
      activeFrom: Month(1, 1),
      liquidity: Liquidity.liquid,
    )).id;
    final firstAccount = await account(), secondAccount = await account();
    final repo = SqliteMovementRepository(db);
    Future<MovementRecord> real(
      String? category,
      int cents, {
      int month = 1,
      int year = 2026,
      bool second = false,
    }) => repo.create(
      MovementInput(
        accountId: second ? secondAccount : firstAccount,
        categoryId: category,
        amountCents: cents,
        valueDate: ValueDate(year, month, 15),
        concept: 'Café sintético',
      ),
    );
    final direct = await real(root, -1200);
    final middle = await real(child, 200, month: 2);
    final duplicate1 = await real(leaf, -500);
    final duplicate2 = await real(leaf, -500);
    final compensation = await real(leaf, 1000, second: true);
    final nullRow = await real(null, 700);
    final other = await real(sibling, 3000, month: 12);
    await real(root, 999, year: 2025, month: 12);
    await real(root, 999, year: 2027);
    final before = await db.readState();
    Future<void> check(
      AnnualActualDetail detail,
      List<MovementRecord> expected,
    ) async {
      final q = MovementLinks.parse(
        MovementLinks.list(detail.movements),
        defaultMonth: Month(2026, 10),
      );
      MovementCursor? cursor;
      final records = <MovementRecord>[];
      do {
        final page = await repo.readPage(
          from: q.from,
          until: q.until,
          categoryId: q.categoryId,
          categoryScope: q.scope,
          unclassifiedOnly: q.unclassified,
          after: cursor,
          limit: 2,
        );
        expect(page.totalCount, expected.length);
        expect(
          page.subtotalCents,
          expected.fold<int>(0, (sum, r) => sum + r.data.amountCents),
        );
        records.addAll(page.records);
        cursor = page.nextCursor;
      } while (cursor != null);
      expect(
        records.map((r) => r.id),
        unorderedEquals(expected.map((r) => r.id)),
      );
      expect(records.map((r) => r.id).toSet().length, expected.length);
    }

    await check(AnnualActualDetail(year: 2026, categoryId: root), [
      direct,
      middle,
      duplicate1,
      duplicate2,
      compensation,
    ]);
    await check(
      AnnualActualDetail(
        year: 2026,
        categoryId: root,
        scope: MovementCategoryScope.direct,
      ),
      [direct],
    );
    await check(AnnualActualDetail(year: 2026, month: 1, categoryId: root), [
      direct,
      duplicate1,
      duplicate2,
      compensation,
    ]);
    await check(AnnualActualDetail(year: 2026, categoryId: leaf), [
      duplicate1,
      duplicate2,
      compensation,
    ]);
    await check(AnnualActualDetail(year: 2026, unclassified: true), [nullRow]);
    await check(AnnualActualDetail(year: 2026), [
      direct,
      middle,
      duplicate1,
      duplicate2,
      compensation,
      nullRow,
      other,
    ]);
    await check(AnnualActualDetail(year: 2026, month: 3, categoryId: root), []);
    final last = await real(root, 123, year: 9999, month: 12);
    await check(AnnualActualDetail(year: 9999), [last]);
    await check(AnnualActualDetail(year: 9999, month: 12), [last]);
    expect((await db.readState()).revision, before.revision + 1);
  });
}
