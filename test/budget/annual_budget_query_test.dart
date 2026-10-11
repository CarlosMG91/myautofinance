import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/annual_budget_query_factory.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_read_unit_of_work.dart';
import 'package:myautofinance/core/persistence/unit_of_work.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/data/historical_csv_reader.dart';
import 'package:myautofinance/features/importing/historical_csv.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:sqlite3/sqlite3.dart';

final class _AnnualReader implements BudgetRepository {
  _AnnualReader(this.read);
  final Future<List<BudgetRecord>> Function(int year) read;
  int calls = 0;
  @override
  Future<List<BudgetRecord>> readYear(int year, {bool incomeOnly = false}) {
    expect(incomeOnly, isFalse);
    calls++;
    return read(year);
  }

  // Cualquier lectura mensual o escritura inesperada hace fallar la prueba.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Operación inesperada: ${invocation.memberName}');
}

final class _AfterRead implements UnitOfWork {
  _AfterRead(this.inner, this.after);
  final UnitOfWork inner;
  final void Function() after;
  @override
  Future<DatasetState> readState() => inner.readState();
  @override
  Future<T> run<T>(Future<T> Function() operation) async {
    final result = await inner.run(operation);
    after();
    return result;
  }
}

void main() {
  late LocalDatabase db;
  late CategoryManagement categories;
  late CategoryReadInvalidation invalidation;
  late SqliteBudgetRepository budgets;
  late AnnualBudgetQuery query;
  final jan = BudgetMonth(2026, 1);
  AnnualBudgetRow row(AnnualBudget result, String id) =>
      result.rows.singleWhere((row) => row.categoryId == id);
  Future<BudgetRecord> budget(
    String id,
    int cents, {
    int month = 1,
    int year = 2026,
  }) => budgets.create(
    BudgetInput(
      month: BudgetMonth(year, month),
      categoryId: id,
      amountCents: cents,
    ),
  );
  AnnualBudgetQuery withReader(
    _AnnualReader reader, {
    UnitOfWork? unitOfWork,
  }) => AnnualBudgetQuery(
    budgets: reader,
    categories: categories,
    unitOfWork: unitOfWork ?? SqliteReadUnitOfWork(db),
  );
  TypeMatcher<AnnualBudgetFailure> failure(AnnualBudgetFailureCode code) =>
      isA<AnnualBudgetFailure>().having((e) => e.code, 'código', code);

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    invalidation = CategoryReadInvalidation();
    categories = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    budgets = SqliteBudgetRepository(db);
    query = createAnnualBudgetQuery(database: db, invalidation: invalidation);
  });
  tearDown(() async {
    await invalidation.close();
    await db.close();
  });

  test(
    'Doce meses, árbol activo completo, nombres repetidos y neto cero presente',
    () async {
      final root = await categories.create(name: 'Ingresos', isIncome: true);
      final child = await categories.create(
        name: 'Salario',
        parentId: root.node.id,
      );
      final a = await categories.create(
        name: 'Repetida',
        parentId: child.node.id,
      );
      final b = await categories.create(
        name: 'Repetida',
        parentId: child.node.id,
      );
      final empty = await categories.create(
        name: 'Vacía',
        parentId: root.node.id,
      );
      final out = await categories.create(name: 'Salida', isIncome: false);
      final negative = await budget(a.node.id, -123);
      final positive = await budget(b.node.id, 123);
      final zero = await budget(out.node.id, 0);
      await budget(a.node.id, -777, year: 2025);
      await budget(a.node.id, 888, year: 2027);
      final reader = _AnnualReader(
        (year) async => List.unmodifiable(await budgets.readYear(year)),
      );
      final result = await withReader(reader).read(2026);
      expect(reader.calls, 1);
      expect(result.rows.length, 6);
      expect(result.year, 2026);
      expect(result.rows.take(2).map((r) => r.categoryId), [
        root.node.id,
        child.node.id,
      ]);
      expect(
        result.rows.skip(2).take(2).map((r) => r.categoryId),
        [a.node.id, b.node.id]..sort(),
      );
      for (final r in result.rows) {
        expect(
          r.months.map((cell) => cell.month.value),
          List.generate(12, (i) => BudgetMonth(2026, i + 1).value),
        );
      }
      final rootCell = row(result, root.node.id).months.first;
      expect(rootCell.hasOwnBudget, isFalse);
      expect(rootCell.ownAmountCents, isNull);
      expect(rootCell.total.hasBudget, isTrue);
      expect(rootCell.total.amountCents, 0);
      expect(
        rootCell.total.budgetIds,
        unorderedEquals([negative.id, positive.id]),
      );
      expect(row(result, a.node.id).months.first.ownAmountCents, -123);
      expect(
        row(result, b.node.id).category.path,
        row(result, a.node.id).category.path,
      );
      expect(row(result, a.node.id).category.node.isIncome, isTrue);
      final emptyCell = row(result, empty.node.id).months.first;
      expect(emptyCell.ownBudget, isNull);
      expect(emptyCell.total.hasBudget, isFalse);
      expect(emptyCell.total.amountCents, 0);
      expect(row(result, out.node.id).months.first.ownBudget!.id, zero.id);
      expect(row(result, out.node.id).months.first.hasOwnBudget, isTrue);
      expect(row(result, out.node.id).months.first.ownAmountCents, 0);
      expect(result.months.first.budgetCount, 3);
      expect(result.months.first.hasBudget, isTrue);
      expect(result.months[1].hasBudget, isFalse);
      expect(result.annualTotal.budgetCount, 3);
      expect(result.annualTotal.amountCents, 0);
      expect(() => result.rows.clear(), throwsUnsupportedError);
      expect(() => result.months.clear(), throwsUnsupportedError);
      expect(() => result.rows.first.months.clear(), throwsUnsupportedError);
      expect(() => rootCell.total.budgetIds.clear(), throwsUnsupportedError);
      expect(() => rootCell.total.budgets.clear(), throwsUnsupportedError);
    },
  );

  test('Partida de padre no prorratea; niveles distintos por mes y total solo raíces', () async {
    final root = await categories.create(name: 'Rama', isIncome: false);
    final child = await categories.create(name: 'Hija', parentId: root.node.id);
    final a = await categories.create(name: 'A', parentId: child.node.id);
    final b = await categories.create(name: 'B', parentId: child.node.id);
    final own = await budget(root.node.id, -101);
    final first = await budget(a.node.id, -202, month: 2);
    final second = await budget(b.node.id, 33, month: 2);
    final dec = await budget(child.node.id, 70, month: 12);
    final before = await db.readState();
    final result = await query.read(2026);
    expect(row(result, root.node.id).months.first.ownBudget!.id, own.id);
    for (final id in [child.node.id, a.node.id, b.node.id]) {
      expect(row(result, id).months.first.ownBudget, isNull);
      expect(row(result, id).months.first.total.hasBudget, isFalse);
    }
    expect(row(result, root.node.id).months[1].ownBudget, isNull);
    expect(row(result, child.node.id).months[1].total.amountCents, -169);
    expect(
      row(result, child.node.id).months[1].total.budgetIds,
      unorderedEquals([first.id, second.id]),
    );
    expect(result.months.map((m) => m.amountCents), [
      -101,
      -169,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      70,
    ]);
    expect(result.annualTotal.amountCents, -200);
    expect(
      result.annualTotal.budgetIds,
      unorderedEquals([own.id, first.id, second.id, dec.id]),
    );
    expect(row(result, root.node.id).annualTotal.amountCents, -200);
    expect(row(result, root.node.id).ownAnnualTotal.amountCents, -101);
    expect(row(result, child.node.id).ownAnnualTotal.budgetIds, [dec.id]);
    expect(result.datasetState.datasetId, before.datasetId);
    expect(result.datasetState.revision, before.revision);
    expect((await db.readState()).revision, before.revision);
    await expectLater(budget(a.node.id, 0), throwsA(isA<BudgetFailure>()));
    expect((await query.read(2026)).annualTotal.amountCents, -200);
  });

  test('Archivadas con partidas y antecesores; sin ramas vacías ni partidas de otro año', () async {
    final root = await categories.create(name: 'Archivada', isIncome: false);
    final child = await categories.create(
      name: 'Antecesora',
      parentId: root.node.id,
    );
    final leaf = await categories.create(
      name: 'Con datos',
      parentId: child.node.id,
    );
    await categories.create(name: 'Sin datos', parentId: root.node.id);
    final other = await categories.create(
      name: 'Otro año',
      parentId: root.node.id,
    );
    await budget(other.node.id, 999, year: 2025);
    final record = await budget(leaf.node.id, 0, month: 12);
    await categories.archive(root.node.id);
    final result = await query.read(2026);
    expect(result.rows.map((r) => r.categoryId), [
      root.node.id,
      child.node.id,
      leaf.node.id,
    ]);
    expect(result.rows.every((r) => r.category.node.archived), isTrue);
    expect(result.rows.first.months[11].ownBudget, isNull);
    expect(result.rows.first.months[11].total.hasBudget, isTrue);
    expect(result.annualTotal.budgetIds, [record.id]);
    await categories.reactivate(root.node.id);
    expect((await query.read(2026)).rows.length, 5);
  });

  test(
    'Reparent y rename usan árbol actual/UUID, incluso histórico archivado',
    () async {
      final income = await categories.create(name: 'Ingreso', isIncome: true);
      final expense = await categories.create(name: 'Salida', isIncome: false);
      final child = await categories.create(
        name: 'Rama',
        parentId: income.node.id,
      );
      final leaf = await categories.create(
        name: 'Hoja',
        parentId: child.node.id,
      );
      final record = await budget(leaf.node.id, -60000);
      final old = await query.read(2026);
      final events = <int>[];
      final subscription = query.invalidation.changes.listen(events.add);
      await categories.archive(child.node.id);
      await categories.move(child.node.id, parentId: expense.node.id);
      await categories.rename(expense.node.id, name: 'Salidas');
      final fresh = await query.read(2026);
      expect(events.length, 3);
      expect(fresh.categoryGeneration, old.categoryGeneration + 3);
      expect(row(fresh, leaf.node.id).category.path, 'Salidas / Rama / Hoja');
      expect(row(fresh, leaf.node.id).category.node.isIncome, isFalse);
      expect(row(fresh, leaf.node.id).category.node.archived, isTrue);
      expect(row(fresh, leaf.node.id).months.first.ownBudget!.id, record.id);
      expect(row(fresh, expense.node.id).annualTotal.amountCents, -60000);
      expect(row(fresh, income.node.id).annualTotal.hasBudget, isFalse);
      expect(row(old, income.node.id).annualTotal.amountCents, -60000);
      expect(row(old, leaf.node.id).category.path, 'Ingreso / Rama / Hoja');
      await subscription.cancel();
    },
  );

  test(
    'EP-001 E: CSV sintético, doce totales +1100 EUR y anual +13200 EUR',
    () async {
      final csv = const HistoricalCsvReader().read(
        File('docs/ep-001/historico-ejemplo.csv').readAsBytesSync(),
      );
      expect(csv.isValid, isTrue);
      final ids = <String, String>{};
      final records = <ImportedBudget>[];
      var ordinal = 1;
      for (final entry in csv.records) {
        ordinal++;
        if (entry.type != HistoricalCsvType.budget) continue;
        String? parent;
        for (var level = 0; level < entry.categoryPath.length; level++) {
          final path = entry.categoryPath.take(level + 1).join(' / ');
          parent = ids[path] ??= (await categories.create(
            name: entry.categoryPath[level],
            parentId: parent,
            isIncome: level == 0
                ? entry.categoryPath.first == 'Ingresos'
                : null,
          )).node.id;
        }
        records.add(
          ImportedBudget(
            ordinal,
            BudgetInput.fromHistoricalCsv(
              month: BudgetMonth.parse(entry.date),
              categoryId: parent!,
              csvAmountCents: entry.csvAmountCents,
              concept: entry.concept,
              discretion: entry.discretion,
            ),
          ),
        );
      }
      final batch = await SqliteImportBatchRepository(db).create(
        sha256: 'a' * 64,
        source: ImportSource.historicalCsv,
        originalName: 'historico-ejemplo.csv',
        contractVersion: '1',
        budgets: records,
      );
      final result = await query.read(2026);
      expect(result.months.map((m) => m.amountCents), List.filled(12, 110000));
      expect(result.annualTotal.amountCents, 1320000);
      expect(result.annualTotal.budgetCount, 48);
      expect(result.annualTotal.budgetIds.toSet().length, 48);
      for (final entry in {
        'Ingresos': 3600000,
        'Vivienda': -1200000,
        'Alimentación': -480000,
        'Ahorro': -600000,
      }.entries) {
        expect(
          row(result, ids[entry.key]!).annualTotal.amountCents,
          entry.value,
        );
      }
      expect(row(result, ids['Alimentación']!).months.first.ownBudget, isNull);
      expect(
        row(
          result,
          ids['Alimentación / Supermercado']!,
        ).months.first.total.amountCents,
        -40000,
      );
      expect(
        result.annualTotal.budgets.every(
          (r) =>
              r.batchId == batch.id &&
              r.importRowId != null &&
              r.sourceOrdinal != null,
        ),
        isTrue,
      );
    },
  );

  test('Años vacíos y límites civiles conservan ausencia y revisión', () async {
    await categories.create(name: 'Activa', isIncome: false);
    final archived = await categories.create(
      name: 'Archivada vacía',
      isIncome: false,
    );
    await categories.archive(archived.node.id);
    final before = await db.readState();
    for (final year in [1, 2026, 9999]) {
      final result = await query.read(year);
      expect(result.rows.length, 1);
      expect(result.annualTotal.amountCents, 0);
      expect(result.annualTotal.hasBudget, isFalse);
      expect(result.months.every((m) => !m.hasBudget), isTrue);
      expect(
        result.rows.single.months.last.month.value,
        BudgetMonth(year, 12).value,
      );
    }
    await expectLater(
      budget(archived.node.id, 0),
      throwsA(isA<BudgetFailure>()),
    );
    expect((await db.readState()).revision, before.revision);
  });

  test('Año inválido no consulta repositorios', () async {
    final reader = _AnnualReader((year) => budgets.readYear(year));
    for (final year in [0, -1, 10000]) {
      await expectLater(
        withReader(reader).read(year),
        throwsA(failure(AnnualBudgetFailureCode.invalidYear)),
      );
    }
    expect(reader.calls, 0);
  });

  test(
    'Extremos de año y corrección/borrado releen sin caché ni repartir',
    () async {
      final root = await categories.create(name: 'Raíz', isIncome: false);
      final leaf = await categories.create(
        name: 'Hoja',
        parentId: root.node.id,
      );
      final first = await budget(leaf.node.id, -1, year: 1);
      final last = await budget(root.node.id, 1, year: 9999, month: 12);
      expect((await query.read(1)).annualTotal.budgetIds, [first.id]);
      expect((await query.read(9999)).annualTotal.budgetIds, [last.id]);
      final management = BudgetManagement(repository: budgets, unitOfWork: db);
      await management.edit(first.id, amountCents: 0);
      final zero = await query.read(1);
      expect(zero.annualTotal.hasBudget, isTrue);
      expect(row(zero, leaf.node.id).months.first.ownAmountCents, 0);
      await management.delete(first.id);
      expect((await query.read(1)).annualTotal.hasBudget, isFalse);
      expect(zero.annualTotal.budgetIds, [first.id]);
    },
  );

  test(
    'Overflow mensual/anual rechaza; cancelación intermedia suma exacta',
    () async {
      const max = 9223372036854775807;
      final root = await categories.create(name: 'Raíz', isIncome: false);
      final a = await categories.create(name: 'A', parentId: root.node.id);
      final b = await categories.create(name: 'B', parentId: root.node.id);
      final c = await categories.create(name: 'C', parentId: root.node.id);
      await budget(a.node.id, max);
      final extra = await budget(b.node.id, 1);
      await expectLater(
        query.read(2026),
        throwsA(failure(AnnualBudgetFailureCode.overflow)),
      );
      await budget(c.node.id, -max);
      expect((await query.read(2026)).annualTotal.amountCents, 1);
      await budgets.delete(extra.id);
      await budget(a.node.id, max, month: 2);
      await expectLater(
        query.read(2026),
        throwsA(failure(AnnualBudgetFailureCode.overflow)),
      );
    },
  );

  test(
    'Datos ajenos al año, duplicados UUID/celda y conflicto padre-hoja fallan',
    () async {
      final root = await categories.create(name: 'Raíz', isIncome: false);
      final child = await categories.create(
        name: 'Hija',
        parentId: root.node.id,
      );
      final valid = await budget(child.node.id, 0);
      BudgetRecord synthetic(String id, String categoryId, {int year = 2026}) =>
          BudgetRecord(
            id: id,
            data: BudgetInput(
              month: BudgetMonth(year, 1),
              categoryId: categoryId,
              amountCents: 0,
            ),
          );
      for (final records in [
        [valid, valid],
        [valid, synthetic('otro', child.node.id)],
        [valid, synthetic('otro', root.node.id)],
        [synthetic('otro', child.node.id, year: 2025)],
        [synthetic('otro', 'categoría-ausente')],
      ]) {
        final reader = _AnnualReader((_) async => records);
        await expectLater(
          withReader(reader).read(2026),
          throwsA(failure(AnnualBudgetFailureCode.invalidData)),
        );
      }
    },
  );

  test(
    'Invalidación durante lectura o después de transacción descarta snapshot',
    () async {
      for (final after in [false, true]) {
        final reader = _AnnualReader((year) async {
          if (!after) invalidation.invalidate();
          return budgets.readYear(year);
        });
        final uow = after
            ? _AfterRead(SqliteReadUnitOfWork(db), invalidation.invalidate)
            : null;
        await expectLater(
          withReader(reader, unitOfWork: uow).read(2026),
          throwsA(failure(AnnualBudgetFailureCode.invalidated)),
        );
        expect(reader.calls, 1);
      }
      expect(
        (await query.read(2026)).categoryGeneration,
        invalidation.generation,
      );
    },
  );

  test(
    'Fallo entrega error español sin ceros ficticios y permite reintentar',
    () async {
      final reader = _AnnualReader(
        (_) async => throw StateError('detalle SQLite privado'),
      );
      await expectLater(
        withReader(reader).read(2026),
        throwsA(
          failure(AnnualBudgetFailureCode.persistence).having(
            (e) => e.message,
            'mensaje',
            'No se pudo consultar el presupuesto anual. Inténtalo de nuevo.',
          ),
        ),
      );
      await categories.create(name: 'Reintento', isIncome: false);
      expect((await query.read(2026)).rows.single.category.path, 'Reintento');
      await db.customStatement('DROP TABLE budgets');
      await expectLater(
        query.read(2026),
        throwsA(failure(AnnualBudgetFailureCode.persistence)),
      );
    },
  );

  test(
    'Snapshot comparte árbol, partidas y revisión con bloqueo de otra conexión',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'presupuesto-166-',
      );
      final previousWarning =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final file = File('${directory.path}/sintetico.sqlite');
      final local = LocalDatabase(
        NativeDatabase(file, setup: configureConnection),
      );
      final localInvalidation = CategoryReadInvalidation();
      try {
        final localCategories = createCategoryManagement(
          database: local,
          invalidation: localInvalidation,
        );
        final root = await localCategories.create(
          name: 'Antes',
          isIncome: false,
        );
        final repo = SqliteBudgetRepository(local);
        final record = await repo.create(
          BudgetInput(month: jan, categoryId: root.node.id, amountCents: 101),
        );
        final before = await local.readState();
        final competing = sqlite3.open(file.path);
        try {
          final reader = _AnnualReader((year) async {
            // Se intenta escribir entre árbol y readYear, en otra conexión.
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
            return repo.readYear(year);
          });
          final result = await AnnualBudgetQuery(
            budgets: reader,
            categories: localCategories,
            unitOfWork: SqliteReadUnitOfWork(local),
          ).read(2026);
          expect(result.rows.single.category.path, 'Antes');
          expect(result.annualTotal.amountCents, 101);
          expect(result.datasetState.revision, before.revision);
          expect(reader.calls, 1);
          competing.execute('BEGIN IMMEDIATE');
          competing.execute('ROLLBACK');
          await local.run(() async {
            await repo.edit(
              record.id,
              BudgetInput(
                month: jan,
                categoryId: root.node.id,
                amountCents: 202,
              ),
            );
            await local.customStatement(
              'UPDATE categories SET name=? WHERE id=?',
              ['Después', root.node.id],
            );
          });
          localInvalidation.invalidate();
          final fresh = await createAnnualBudgetQuery(
            database: local,
            invalidation: localInvalidation,
          ).read(2026);
          expect(fresh.rows.single.category.path, 'Después');
          expect(fresh.annualTotal.amountCents, 202);
          expect(fresh.datasetState.revision, before.revision + 1);
          expect(result.rows.single.category.path, 'Antes');
          expect(result.annualTotal.amountCents, 101);
        } finally {
          competing.close();
        }
      } finally {
        await local.close();
        await localInvalidation.close();
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
        await directory.delete(recursive: true);
      }
    },
  );
}
