import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/budget_factory.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/monthly_status/monthly_status.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  late LocalDatabase db;
  late CategoryReadInvalidation invalidation;
  late CategoryManagement categories;
  late BudgetListReader budgets;
  late SqliteMovementRepository movements;
  late String root, child, leaf, sibling, account, otherAccount;
  final month = BudgetMonth(2026, 1);
  Future<MovementRecord> real(
    String? id,
    int cents, {
    String? onAccount,
    ValueDate? date,
  }) => movements.create(
    MovementInput(
      accountId: onAccount ?? account,
      valueDate: date ?? ValueDate(2026, 1, 15),
      concept: 'Café sintético',
      categoryId: id,
      amountCents: cents,
    ),
  );
  Future<List<MovementRecord>> read(MonthlyFigureDetail detail) {
    final q = detail.movements;
    return movements.list(
      from: q.from,
      until: q.until,
      categoryId: q.categoryId,
      categoryScope: q.scope,
      unclassifiedOnly: q.unclassified,
    );
  }

  Future<BudgetRecord> plan(String id, int cents, {BudgetMonth? at}) =>
      SqliteBudgetRepository(db).create(
        BudgetInput(month: at ?? month, categoryId: id, amountCents: cents),
      );
  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    invalidation = CategoryReadInvalidation();
    categories = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    budgets = createBudgetSource(db, invalidation).entries!;
    movements = SqliteMovementRepository(db);
    root = (await categories.create(name: 'Raíz', isIncome: false)).node.id;
    child = (await categories.create(name: 'Hija', parentId: root)).node.id;
    leaf = (await categories.create(name: 'Hoja', parentId: child)).node.id;
    sibling = (await categories.create(name: 'Raíz', isIncome: false)).node.id;
    final accounts = SqliteAccountRepository(db);
    Future<String> add() async => (await accounts.create(
      name: 'Cuenta sintética',
      kind: AccountKind.account,
      activeFrom: Month(1, 1),
      liquidity: Liquidity.liquid,
    )).id;
    account = await add();
    otherAccount = await add();
  });
  tearDown(() async {
    await invalidation.close();
    await db.close();
  });

  test('Directo, rama de tres niveles, NULL y total conservan UUID una vez y todas las cuentas', () async {
    final direct = await real(root, -1200);
    final middle = await real(child, 200);
    final first = await real(leaf, -50000);
    final second = await real(leaf, 50000, onAccount: otherAccount);
    final nullFirst = await real(null, 700);
    final nullSecond = await real(null, -300);
    final other = await real(sibling, -1000);
    await real(root, 999, date: ValueDate(2025, 12, 31));
    await real(leaf, 999, date: ValueDate(2026, 2, 1));
    final before = await db.readState();
    expect(
      (await read(
        MonthlyFigureDetail(
          month: month,
          categoryId: root,
          scope: MovementCategoryScope.direct,
        ),
      )).map((r) => r.id),
      [direct.id],
    );
    expect(
      (await read(MonthlyFigureDetail(month: month, categoryId: root)))
          .map((r) => r.id),
      unorderedEquals([direct.id, middle.id, first.id, second.id]),
    );
    final netZero = await read(
      MonthlyFigureDetail(month: month, categoryId: leaf),
    );
    expect(netZero.length, 2);
    expect(netZero.fold(0, (sum, row) => sum + row.data.amountCents), 0);
    expect(
      (await read(MonthlyFigureDetail(month: month, unclassified: true)))
          .map((r) => r.id),
      unorderedEquals([nullFirst.id, nullSecond.id]),
    );
    expect(
      (await read(MonthlyFigureDetail(month: month))).map((r) => r.id),
      unorderedEquals([
        direct.id,
        middle.id,
        first.id,
        second.id,
        nullFirst.id,
        nullSecond.id,
        other.id,
      ]),
    );
    expect((await db.readState()).revision, before.revision);
  });
  test('Previsto agregado conserva partida padre, hijos vacíos, cero explícito y total', () async {
    final parent = await plan(root, -40000);
    final zero = await plan(sibling, 0);
    await plan(leaf, -999, at: BudgetMonth(2026, 2));
    final before = await db.readState();
    expect(
      (await budgets.read(
        MonthlyFigureDetail(month: month, categoryId: root).budgets,
      )).single.record.id,
      parent.id,
    );
    expect(
      await budgets.read(
        MonthlyFigureDetail(month: month, categoryId: child).budgets,
      ),
      isEmpty,
    );
    expect(
      await budgets.read(
        MonthlyFigureDetail(month: month, unclassified: true).budgets,
      ),
      isEmpty,
    );
    expect(
      (await budgets.read(MonthlyFigureDetail(month: month).budgets))
          .map((e) => e.record.id),
      unorderedEquals([parent.id, zero.id]),
    );
    expect((await db.readState()).revision, before.revision);
  });
  test(
    'Partida hoja archivada y traslado histórico siguen el árbol actual',
    () async {
      final original = await plan(leaf, -40000);
      await real(leaf, -35025);
      await categories.archive(child);
      final rows = await budgets.read(
        MonthlyFigureDetail(month: month, categoryId: root).budgets,
      );
      expect(rows.single.record.id, original.id);
      expect(rows.single.category.node.archived, isTrue);
      await categories.reactivate(child);
      await categories.move(child, parentId: sibling);
      expect(
        await budgets.read(
          MonthlyFigureDetail(month: month, categoryId: root).budgets,
        ),
        isEmpty,
      );
      expect(
        (await budgets.read(
          MonthlyFigureDetail(month: month, categoryId: sibling).budgets,
        )).single.record.id,
        original.id,
      );
      expect(
        await read(MonthlyFigureDetail(month: month, categoryId: root)),
        isEmpty,
      );
      expect(
        (await read(MonthlyFigureDetail(month: month, categoryId: sibling)))
            .length,
        1,
      );
    },
  );
  test(
    'Meses vacíos, límites civiles y UUID ausente fallan sin escrituras',
    () async {
      for (final at in [BudgetMonth(1, 1), month, BudgetMonth(9999, 12)]) {
        final detail = MonthlyFigureDetail(month: at);
        expect(await read(detail), isEmpty);
        expect(await budgets.read(detail.budgets), isEmpty);
      }
      expect(
        MonthlyFigureDetail(month: BudgetMonth(9999, 12)).movements.until,
        isNull,
      );
      expect(
        MonthlyFigureDetail(month: BudgetMonth(2026, 12))
            .movements
            .until!
            .value,
        '2027-01-01',
      );
      await expectLater(
        budgets.read(
          BudgetListQuery(
            month: month,
            categoryId: '00000000-0000-0000-0000-000000000001',
          ),
        ),
        throwsA(isA<BudgetFailure>()),
      );
      expect(
        () => MonthlyFigureDetail(
          month: month,
          categoryId: root,
          unclassified: true,
        ),
        throwsException,
      );
      expect(
        () => MonthlyFigureDetail(month: month, categoryId: 'Raíz'),
        throwsException,
      );
    },
  );
}
