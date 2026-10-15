import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_read_unit_of_work.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/movements/movements.dart';

class _ReadBudgetRepository implements BudgetRepository {
  _ReadBudgetRepository(this.inner);
  final BudgetRepository inner;
  final years = <int>[];
  final months = <String>[];
  @override
  Future<List<BudgetRecord>> readYear(int year, {bool incomeOnly = false}) {
    years.add(year);
    return inner.readYear(year, incomeOnly: incomeOnly);
  }

  @override
  Future<List<BudgetRecord>> list(BudgetMonth month) {
    months.add(month.value);
    return inner.list(month);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('La consulta no puede escribir.');
}

void main() {
  late LocalDatabase db;
  late CategoryManagement categories;
  late CategoryReadInvalidation invalidation;
  late SqliteBudgetRepository budgets;
  late _ReadBudgetRepository reads;
  late BudgetListReader reader;
  late String root, child, leaf, sibling;

  Future<BudgetRecord> add(String category, int year, int month, int cents) =>
      budgets.create(
        BudgetInput(
          categoryId: category,
          month: BudgetMonth(year, month),
          amountCents: cents,
        ),
      );

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    invalidation = CategoryReadInvalidation();
    categories = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    budgets = SqliteBudgetRepository(db);
    reads = _ReadBudgetRepository(budgets);
    reader = BudgetListReader(
      budgets: reads,
      categories: categories,
      unitOfWork: SqliteReadUnitOfWork(db),
    );
    root = (await categories.create(name: 'Hogar')).node.id;
    child = (await categories.create(name: 'Compras', parentId: root)).node.id;
    leaf = (await categories.create(name: 'Comida', parentId: child)).node.id;
    sibling = (await categories.create(
      name: 'Compras',
      parentId: root,
    )).node.id;
  });
  tearDown(() async {
    await invalidation.close();
    await db.close();
  });

  test(
    'Rango entre años inclusivo, foco independiente y lectura sin mutación',
    () async {
      await add(root, 2025, 11, -999);
      final a = await add(root, 2025, 12, -123);
      final b = await add(leaf, 2026, 1, 123);
      final c = await add(sibling, 2026, 2, 0);
      await add(root, 2026, 3, 999);
      final before = await db.readState();
      final result = await reader.readResult(
        BudgetListQuery.range(
          month: BudgetMonth(2027, 10),
          firstMonth: BudgetMonth(2025, 12),
          lastMonth: BudgetMonth(2026, 2),
          categoryId: root,
        ),
      );
      expect(result.query.isAnnual, isFalse);
      expect(result.entries.map((e) => e.record.id), [a.id, b.id, c.id]);
      expect(result.totalCount, 3);
      expect(result.subtotalCents, BigInt.zero);
      expect(result.page(limit: 1).single.record.id, a.id);
      expect(result.page(offset: 1, limit: 1).single.record.id, b.id);
      expect(result.page(offset: 2, limit: 1).single.record.id, c.id);
      expect(result.page(offset: 3), isEmpty);
      expect(result.page(offset: 999999), isEmpty);
      expect(reads.years, [2025, 2026]);
      expect(reads.months, isEmpty);
      final after = await db.readState();
      expect(after.datasetId, before.datasetId);
      expect(after.revision, before.revision);
      expect(result.datasetState.datasetId, before.datasetId);
      expect(result.datasetState.revision, before.revision);
      expect(result.categoryGeneration, invalidation.generation);
    },
  );

  test(
    'Directo no reparte padre, vacío y cero explícito son distintos',
    () async {
      final own = await add(root, 2026, 1, 0);
      await add(leaf, 2026, 2, -1);
      final direct = await reader.readResult(
        BudgetListQuery.annual(
          2026,
          categoryId: root,
          scope: MovementCategoryScope.direct,
        ),
      );
      expect(direct.totalCount, 1);
      expect(direct.entries.single.record.id, own.id);
      expect(direct.subtotalCents, BigInt.zero);
      final empty = await reader.readResult(
        BudgetListQuery(month: BudgetMonth(2026, 1), categoryId: leaf),
      );
      expect(empty.totalCount, 0);
      expect(empty.subtotalCents, BigInt.zero);
      expect(empty.page(), isEmpty);
      expect(reads.years, [2026]);
      expect(reads.months, ['2026-01-01']);
    },
  );

  test(
    'Archivo, traslado y nombres/rutas repetidas conservan UUID y orden',
    () async {
      final a = await add(child, 2026, 1, -100);
      final b = await add(sibling, 2026, 1, -100);
      await categories.archive(child);
      final query = BudgetListQuery(
        month: BudgetMonth(2026, 1),
        categoryId: root,
      );
      final result = await reader.readResult(query);
      final orderedIds = [a.id, b.id]..sort();
      expect(result.entries.map((e) => e.record.id), orderedIds);
      expect(result.entries.map((e) => e.category.path).toSet(), {
        'Hogar / Compras',
      });
      expect(result.entries.map((e) => e.category.node.id).toSet(), {
        child,
        sibling,
      });
      expect(
        result.entries
            .singleWhere((e) => e.record.id == a.id)
            .category
            .node
            .archived,
        isTrue,
      );
      expect(result.subtotalCents, BigInt.from(-200));
      final destination = (await categories.create(name: 'Otro hogar')).node.id;
      await categories.move(child, parentId: destination);
      final refreshed = await reader.readResult(query);
      expect(refreshed.entries.single.record.id, b.id);
      final moved = await reader.readResult(
        BudgetListQuery(month: BudgetMonth(2026, 1), categoryId: destination),
      );
      expect(moved.entries.single.record.id, a.id);
      expect(moved.entries.single.category.path, 'Otro hogar / Compras');
    },
  );

  test(
    'Páginas acotadas, totales completos e inmutables y relectura tras cambios',
    () async {
      final ids = <String>[];
      for (var i = 0; i < 205; i++) {
        final category = (await categories.create(name: 'Partida $i')).node.id;
        ids.add((await add(category, 2026, 1, i == 0 ? 0 : -1)).id);
      }
      final query = BudgetListQuery(month: BudgetMonth(2026, 1));
      final result = await reader.readResult(query);
      final first = result.page(limit: BudgetListResult.maxPageSize);
      final last = result.page(
        offset: 200,
        limit: BudgetListResult.maxPageSize,
      );
      expect(first.length, 200);
      expect(last.length, 5);
      expect([...first, ...last].map((e) => e.record.id), unorderedEquals(ids));
      expect(result.subtotalCents, BigInt.from(-204));
      expect(result.totalCount, 205);
      expect(() => result.entries.clear(), throwsUnsupportedError);
      expect(() => first.clear(), throwsUnsupportedError);
      for (final (offset, limit) in [(-1, 1), (0, 0), (0, 201)]) {
        expect(
          () => result.page(offset: offset, limit: limit),
          throwsA(isA<BudgetFailure>()),
        );
      }
      await budgets.delete(ids.first);
      expect(result.totalCount, 205);
      expect(
        result.page(limit: 200).map((e) => e.record.id),
        first.map((e) => e.record.id),
      );
      expect(reads.months, hasLength(1));
      final refreshed = await reader.readResult(query);
      expect(refreshed.totalCount, 204);
      expect(
        refreshed.datasetState.revision,
        greaterThan(result.datasetState.revision),
      );
    },
  );

  test('Subtotal exacto al exceder int64 y al cancelarse, también en extremos de año', () async {
    const max = 9223372036854775807;
    await add(child, 9999, 12, max);
    await add(sibling, 9999, 12, max);
    final result = await reader.readResult(BudgetListQuery.annual(9999));
    expect(result.subtotalCents, BigInt.from(max) * BigInt.two);
    await add(child, 9999, 11, -max);
    await add(sibling, 9999, 11, -max);
    final net = await reader.readResult(BudgetListQuery.annual(9999));
    expect(net.subtotalCents, BigInt.zero);
    expect(net.totalCount, 4);
    await add(root, 1, 1, 1);
    expect(
      (await reader.readResult(BudgetListQuery.annual(1))).subtotalCents,
      BigInt.one,
    );
  });

  test(
    'Filtros inválidos y categoría inexistente producen errores de presupuesto',
    () async {
      final month = BudgetMonth(2026, 1);
      for (final id in ['', 'sin-clasificar', 'no-uuid']) {
        expect(
          () => BudgetListQuery(month: month, categoryId: id),
          throwsA(isA<BudgetFailure>()),
        );
      }
      expect(
        () => BudgetListQuery(month: month, unclassified: true),
        throwsA(isA<BudgetFailure>()),
      );
      expect(
        () => BudgetListQuery.range(
          month: month,
          firstMonth: BudgetMonth(2026, 2),
          lastMonth: month,
        ),
        throwsA(isA<BudgetFailure>()),
      );
      await expectLater(
        reader.readResult(
          BudgetListQuery(
            month: month,
            categoryId: '00000000-0000-0000-0000-000000000000',
          ),
        ),
        throwsA(
          isA<BudgetFailure>().having(
            (e) => e.code,
            'código',
            BudgetFailureCode.categoryNotFound,
          ),
        ),
      );
    },
  );
}
