import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/core/persistence/unit_of_work.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/movements/movements.dart';

const root = '00000000-0000-0000-0000-000000000001';
const child = '00000000-0000-0000-0000-000000000002';
const leaf = '00000000-0000-0000-0000-000000000003';
const sibling = '00000000-0000-0000-0000-000000000004';

class ReadUnit implements UnitOfWork {
  int reads = 0;
  @override
  Future<T> run<T>(Future<T> Function() operation) async {
    reads++;
    return operation();
  }

  @override
  Future<DatasetState> readState() async =>
      const DatasetState(datasetId: root, revision: 0);
}

class Categories implements CategoryRepository {
  @override
  Future<List<CategoryNode>> list({bool includeArchived = true}) async => [
    const CategoryNode(
      id: root,
      parentId: null,
      name: 'Hogar',
      isIncome: false,
      archived: false,
      depth: 1,
    ),
    const CategoryNode(
      id: child,
      parentId: root,
      name: 'Hija',
      isIncome: false,
      archived: false,
      depth: 2,
    ),
    const CategoryNode(
      id: leaf,
      parentId: child,
      name: 'Hoja',
      isIncome: false,
      archived: true,
      depth: 3,
    ),
    const CategoryNode(
      id: sibling,
      parentId: null,
      name: 'Hogar',
      isIncome: false,
      archived: false,
      depth: 1,
    ),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No se permite escribir.');
}

class Budgets implements BudgetRepository {
  bool fail = false;
  void Function()? afterRead;
  @override
  Future<List<BudgetRecord>> list(BudgetMonth month) async {
    if (fail) throw StateError('Fallo sintético de almacenamiento');
    afterRead?.call();
    return [
      for (final id in [leaf, sibling])
        BudgetRecord(
          id: id,
          data: BudgetInput(
            month: month,
            categoryId: id,
            amountCents: id == leaf ? -40000 : 0,
          ),
        ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No se permite escribir.');
}

void main() {
  test('Puerto con doubles respeta UUID, rama, archivo, total, cero y ausencia sin escrituras', () async {
    final unit = ReadUnit();
    final repo = Budgets();
    final invalidation = CategoryReadInvalidation();
    addTearDown(invalidation.close);
    final reader = BudgetListReader(
      budgets: repo,
      unitOfWork: unit,
      categories: CategoryManagement(
        repository: Categories(),
        unitOfWork: unit,
        invalidation: invalidation,
      ),
    );
    final month = BudgetMonth(2026, 1);
    final branch = await reader.read(
      BudgetListQuery(month: month, categoryId: root),
    );
    expect(branch.single.record.id, leaf);
    expect(branch.single.category.node.archived, isTrue);
    expect(() => branch.clear(), throwsUnsupportedError);
    expect(
      await reader.read(
        BudgetListQuery(
          month: month,
          categoryId: root,
          scope: MovementCategoryScope.direct,
        ),
      ),
      isEmpty,
    );
    expect(
      await reader.read(BudgetListQuery(month: month, unclassified: true)),
      isEmpty,
    );
    expect(
      (await reader.read(BudgetListQuery(month: month)))
          .map((e) => e.record.id),
      unorderedEquals([leaf, sibling]),
    );
    expect(unit.reads, 4);
    repo.fail = true;
    await expectLater(
      reader.read(BudgetListQuery(month: month)),
      throwsA(isA<BudgetFailure>()),
    );
    repo.fail = false;
    repo.afterRead = invalidation.invalidate;
    await expectLater(
      reader.read(BudgetListQuery(month: month)),
      throwsA(isA<BudgetFailure>()),
    );
  });
}
