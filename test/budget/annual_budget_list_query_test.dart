import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/movements/movements.dart';

import 'budget_list_query_test.dart' as fixture;

class _Budgets implements BudgetRepository {
  int annualReads = 0, monthlyReads = 0;
  bool fail = false;
  void Function()? afterRead;
  List<BudgetRecord> records = [
    for (final (id, category, month, amount) in [
      ('a', fixture.root, 1, -100),
      ('b', fixture.leaf, 2, -300),
      ('c', fixture.sibling, 2, 300),
      ('d', fixture.sibling, 3, 0),
    ])
      BudgetRecord(
        id: id,
        data: BudgetInput(
          month: BudgetMonth(2026, month),
          categoryId: category,
          amountCents: amount,
        ),
      ),
  ];
  @override
  Future<List<BudgetRecord>> readYear(
    int year, {
    bool incomeOnly = false,
  }) async {
    annualReads++;
    expect(year, 2026);
    expect(incomeOnly, isFalse);
    if (fail) throw StateError('Fallo sintético');
    afterRead?.call();
    return records;
  }

  @override
  Future<List<BudgetRecord>> list(BudgetMonth month) async {
    monthlyReads++;
    return records
        .where((record) => record.data.month.value == month.value)
        .toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Escritura no autorizada por lectura.');
}

void main() {
  late _Budgets budgets;
  late CategoryReadInvalidation invalidation;
  late BudgetListReader reader;
  setUp(() {
    budgets = _Budgets();
    invalidation = CategoryReadInvalidation();
    final unit = fixture.ReadUnit();
    reader = BudgetListReader(
      budgets: budgets,
      unitOfWork: unit,
      categories: CategoryManagement(
        repository: fixture.Categories(),
        unitOfWork: unit,
        invalidation: invalidation,
      ),
    );
  });
  tearDown(() => invalidation.close());

  test('Una lectura anual: rama, padre propio y archivada sin reparto o doble origen', () async {
    final entries = await reader.read(
      BudgetListQuery.annual(2026, focusedMonth: 10, categoryId: fixture.root),
    );
    expect(entries.map((entry) => entry.record.id), ['a', 'b']);
    expect(entries.last.category.node.archived, isTrue);
    expect(
      entries.fold<int>(0, (sum, entry) => sum + entry.record.data.amountCents),
      -400,
    );
    expect(budgets.annualReads, 1);
    expect(budgets.monthlyReads, 0);
    expect(
      (await reader.read(
        BudgetListQuery.annual(
          2026,
          categoryId: fixture.root,
          scope: MovementCategoryScope.direct,
        ),
      )).map((e) => e.record.id),
      ['a'],
    );
    expect(
      (await reader.read(
        BudgetListQuery(month: BudgetMonth(2026, 1), categoryId: fixture.leaf),
      )),
      isEmpty,
    );
    expect(budgets.monthlyReads, 1);
  });

  test(
    'Mensual neto cero conserva ambos IDs; cero explícito y ausencia distintos',
    () async {
      final net = await reader.read(
        BudgetListQuery(month: BudgetMonth(2026, 2)),
      );
      expect(net.map((e) => e.record.id), unorderedEquals(['b', 'c']));
      expect(net.fold<int>(0, (sum, e) => sum + e.record.data.amountCents), 0);
      expect(
        (await reader.read(BudgetListQuery(month: BudgetMonth(2026, 3))))
            .single
            .record
            .id,
        'd',
      );
      expect(
        await reader.read(BudgetListQuery(month: BudgetMonth(2026, 4))),
        isEmpty,
      );
      final range = await reader.read(
        BudgetListQuery.range(
          month: BudgetMonth(2026, 10),
          firstMonth: BudgetMonth(2026, 2),
          lastMonth: BudgetMonth(2026, 3),
        ),
      );
      expect(range.map((e) => e.record.id), unorderedEquals(['b', 'c', 'd']));
      expect(
        (await reader.read(BudgetListQuery.annual(2026)))
            .map((e) => e.record.id),
        unorderedEquals(['a', 'b', 'c', 'd']),
      );
    },
  );

  test('Fallo, invalidación, IDs duplicados y otro año nunca devuelven detalle parcial', () async {
    final query = BudgetListQuery.annual(2026);
    budgets.fail = true;
    await expectLater(reader.read(query), throwsA(isA<BudgetFailure>()));
    budgets.fail = false;
    budgets.afterRead = invalidation.invalidate;
    await expectLater(reader.read(query), throwsA(isA<BudgetFailure>()));
    budgets.afterRead = null;
    budgets.records.add(budgets.records.first);
    await expectLater(reader.read(query), throwsA(isA<BudgetFailure>()));
    budgets.records.removeLast();
    budgets.records.add(
      BudgetRecord(
        id: 'e',
        data: BudgetInput(
          month: BudgetMonth(2025, 1),
          categoryId: fixture.root,
          amountCents: 0,
        ),
      ),
    );
    await expectLater(reader.read(query), throwsA(isA<BudgetFailure>()));
  });
}
