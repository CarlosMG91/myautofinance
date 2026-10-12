import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/annual_actual_query_factory.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_read_unit_of_work.dart';
import 'package:myautofinance/core/persistence/unit_of_work.dart';
import 'package:myautofinance/features/actual_spending/actual_spending.dart';
import 'package:myautofinance/features/importing/data/historical_csv_reader.dart';
import 'package:myautofinance/features/importing/historical_csv.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late LocalDatabase db;
  late CategoryReadInvalidation invalidation;
  late CategoryManagement categories;
  late SqliteMovementRepository movements;
  late AnnualActualQuery query;
  late String account, secondAccount;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    invalidation = CategoryReadInvalidation();
    categories = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    movements = SqliteMovementRepository(db);
    query = createAnnualActualQuery(database: db, invalidation: invalidation);
    final accounts = SqliteAccountRepository(db);
    Future<String> createAccount() async => (await accounts.create(
      name: 'Cuenta sintética',
      kind: AccountKind.account,
      activeFrom: Month(1, 1),
      liquidity: Liquidity.liquid,
    )).id;
    account = await createAccount();
    secondAccount = await createAccount();
  });
  tearDown(() async {
    await invalidation.close();
    await db.close();
  });

  Future<MovementRecord> real(
    String? id,
    int amount, {
    ValueDate? date,
    String? onAccount,
  }) => movements.create(
    MovementInput(
      accountId: onAccount ?? account,
      valueDate: date ?? ValueDate(2026, 1, 9),
      concept: 'Movimiento sintético',
      amountCents: amount,
      categoryId: id,
    ),
  );
  AnnualActualRow row(AnnualActual result, String id) =>
      result.rows.singleWhere((r) => r.categoryId == id);
  Matcher failure(AnnualActualFailureCode code) =>
      isA<AnnualActualFailure>().having((e) => e.code, 'código', code);
  AnnualActualQuery withReader(_Reader reader, {UnitOfWork? unitOfWork}) =>
      AnnualActualQuery(
        movements: reader,
        categories: categories,
        unitOfWork: unitOfWork ?? SqliteReadUnitOfWork(db),
      );
  Future<int> changes() async =>
      (await db.customSelect('SELECT total_changes() AS n').getSingle())
          .read<int>('n');

  test(
    'EP-001 F: diez originales, doce meses, firmas y lectura inmutable',
    () async {
      final csv = const HistoricalCsvReader().read(
        File('docs/ep-001/historico-ejemplo.csv').readAsBytesSync(),
      );
      expect(csv.isValid, isTrue);
      final ids = <String, String>{};
      final imported = <ImportedMovement>[];
      var ordinal = 1;
      for (final record in csv.records) {
        ordinal++;
        if (record.type != HistoricalCsvType.real) continue;
        String? parent;
        for (var level = 0; level < record.categoryPath.length; level++) {
          final path = record.categoryPath.take(level + 1).join(' / ');
          parent = ids[path] ??= (await categories.create(
            name: record.categoryPath[level],
            parentId: parent,
            isIncome: parent == null
                ? record.categoryPath.first == 'Ingresos'
                : null,
          )).node.id;
        }
        imported.add(
          ImportedMovement(
            ordinal,
            MovementInput(
              accountId: account,
              valueDate: ValueDate.parse(record.date),
              concept: record.concept,
              amountCents: record.csvAmountCents,
              categoryId: parent,
            ),
          ),
        );
      }
      await SqliteImportBatchRepository(db).create(
        sha256: '1' * 64,
        source: ImportSource.historicalCsv,
        originalName: 'historico-ejemplo.csv',
        contractVersion: '1',
        movements: imported,
        budgets: [],
      );
      final before = await db.readState();
      final beforeChanges = await changes();
      final reader = _Reader(movements.readYearTotals);
      final result = await withReader(reader).read(2026);
      expect(reader.calls, 1);
      expect(result.months.map((t) => t.amountCents), [
        122975,
        109990,
        ...List.filled(10, 0),
      ]);
      expect(result.annualTotal.amountCents, 232965);
      expect(result.annualTotal.movementCount, 10);
      for (final entry in {
        'Ingresos': 612000,
        'Vivienda': -200000,
        'Alimentación': -77035,
        'Ahorro': -100000,
        'Ocio': -2000,
      }.entries) {
        expect(
          row(result, ids[entry.key]!).annualTotal.amountCents,
          entry.value,
        );
      }
      expect(
        row(
          result,
          ids['Alimentación / Supermercado / Compra semanal']!,
        ).annualTotal.amountCents,
        -77035,
      );
      final leisure = row(result, ids['Ocio']!);
      expect(leisure.months.first.direct.movementCount, 2);
      expect(leisure.months[1].total.hasMovements, isFalse);
      final originals = await movements.readYear(2026);
      expect(originals, hasLength(10));
      expect(
        originals.every((r) => r.importRowId != null && r.batchId != null),
        isTrue,
      );
      expect(originals.where((r) => r.data.concept == 'Café'), hasLength(2));
      expect(result.datasetState.datasetId, before.datasetId);
      expect(result.datasetState.revision, before.revision);
      expect((await db.readState()).revision, before.revision);
      expect(await changes(), beforeChanges);
      for (final list in [
        result.rows,
        result.tree,
        result.months,
        leisure.months,
        result.unclassified.months,
      ]) {
        expect(() => list.clear(), throwsUnsupportedError);
      }
    },
  );

  test(
    'Directos en tres niveles, signos excepcionales, transferencias y null',
    () async {
      final root = await categories.create(name: 'INGRESOS', isIncome: true);
      final salary = await categories.create(
        name: 'SALARIO',
        parentId: root.node.id,
      );
      final tax = await categories.create(
        name: 'IMPUESTOS',
        parentId: salary.node.id,
      );
      final savings = await categories.create(name: 'Ahorro', isIncome: false);
      await real(root.node.id, -100);
      await real(salary.node.id, 300000);
      await real(tax.node.id, -60000);
      await real(savings.node.id, -50000);
      await real(savings.node.id, 50000, onAccount: secondAccount);
      await real(savings.node.id, 17, date: ValueDate(2026, 12, 31));
      await real(null, 700);
      await real(null, -700, onAccount: secondAccount);
      final result = await query.read(2026);
      expect(row(result, root.node.id).months.first.direct.amountCents, -100);
      expect(row(result, root.node.id).annualTotal.amountCents, 239900);
      expect(row(result, salary.node.id).directAnnualTotal.amountCents, 300000);
      expect(row(result, salary.node.id).annualTotal.amountCents, 240000);
      expect(row(result, tax.node.id).category!.node.isIncome, isTrue);
      final saving = row(result, savings.node.id);
      expect(saving.months.first.total.amountCents, 0);
      expect(saving.months.first.total.movementCount, 2);
      expect(saving.months.first.total.hasMovements, isTrue);
      expect(saving.annualTotal.amountCents, 17);
      expect(result.unclassified.categoryId, isNull);
      expect(result.unclassified.category, isNull);
      expect(result.unclassified.annualTotal.amountCents, 0);
      expect(result.unclassified.annualTotal.movementCount, 2);
      expect(result.annualTotal.amountCents, 239917);
      expect(result.annualTotal.movementCount, 8);
      expect(result.tree, hasLength(4));
      expect(result.rows.map((r) => r.categoryId), isNot(contains(null)));
      expect(result.months[1].hasMovements, isFalse);
    },
  );

  test(
    'Raíces activas, histórico archivado y antecesores por UUID homónimo',
    () async {
      final root = await categories.create(name: 'Raíz', isIncome: false);
      final branch = await categories.create(
        name: 'Rama',
        parentId: root.node.id,
      );
      final first = await categories.create(
        name: 'Igual',
        parentId: branch.node.id,
      );
      final second = await categories.create(
        name: 'Igual',
        parentId: branch.node.id,
      );
      final unused = await categories.create(
        name: 'Sin datos',
        parentId: root.node.id,
      );
      final empty = await categories.create(name: 'Vacía', isIncome: false);
      final hidden = await categories.create(
        name: 'Archivo vacío',
        isIncome: false,
      );
      await categories.archive(hidden.node.id);
      await real(first.node.id, 9);
      await real(second.node.id, 10);
      await real(second.node.id, -10);
      await categories.archive(root.node.id);
      final result = await query.read(2026);
      expect(result.rows.map((r) => r.categoryId).toSet(), {
        root.node.id,
        branch.node.id,
        first.node.id,
        second.node.id,
        empty.node.id,
      });
      expect(
        result.rows.every(
          (r) =>
              r.categoryId != unused.node.id && r.categoryId != hidden.node.id,
        ),
        isTrue,
      );
      expect(
        result.rows.map((r) => r.categoryId).toList().indexOf(root.node.id),
        lessThan(
          result.rows.map((r) => r.categoryId).toList().indexOf(branch.node.id),
        ),
      );
      final siblings = result.rows
          .where((r) => r.category!.node.parentId == branch.node.id)
          .toList();
      expect(
        siblings.map((r) => r.categoryId),
        [first.node.id, second.node.id]..sort(),
      );
      expect(row(result, second.node.id).annualTotal.hasMovements, isTrue);
      expect(row(result, second.node.id).annualTotal.amountCents, 0);
      expect(row(result, first.node.id).annualTotal.amountCents, 9);
      expect(result.annualTotal.movementCount, 3);
      expect(result.annualTotal.amountCents, 9);
      expect(row(result, root.node.id).category!.node.archived, isTrue);
      await categories.reactivate(root.node.id);
      expect(
        row(await query.read(2026), root.node.id).category!.node.archived,
        isFalse,
      );
      expect((await query.read(2027)).rows.map((r) => r.categoryId).toSet(), {
        root.node.id,
        empty.node.id,
      });
    },
  );

  test('Límites civiles 1/9999 y cada mes sin filtro de cuenta', () async {
    await real(null, 1, date: ValueDate(1, 1, 1));
    await real(null, 2, date: ValueDate(1, 12, 31));
    await real(null, 99, date: ValueDate(2025, 12, 31));
    for (var month = 1; month <= 12; month++) {
      await real(null, month, date: ValueDate(2026, month, 1));
      final last = DateTime.utc(2026, month + 1, 0).day;
      await real(
        null,
        -1,
        date: ValueDate(2026, month, last),
        onAccount: secondAccount,
      );
    }
    await real(null, 99, date: ValueDate(2027, 1, 1));
    await real(null, 3, date: ValueDate(9999, 1, 1));
    await real(null, 4, date: ValueDate(9999, 12, 31));
    expect((await query.read(1)).annualTotal.amountCents, 3);
    expect((await query.read(9999)).annualTotal.amountCents, 7);
    final result = await query.read(2026);
    expect(
      result.months.map((t) => t.amountCents),
      List.generate(12, (i) => i),
    );
    expect(
      result.unclassified.months.map((c) => c.month),
      List.generate(12, (i) => i + 1),
    );
    expect(result.annualTotal.amountCents, 66);
    expect(result.annualTotal.movementCount, 24);
    final empty = await query.read(2028);
    expect(empty.annualTotal.hasMovements, isFalse);
    expect(
      empty.months.every((t) => t.amountCents == 0 && t.movementCount == 0),
      isTrue,
    );
    for (final year in [0, -1, 10000]) {
      await expectLater(
        query.read(year),
        throwsA(failure(AnnualActualFailureCode.invalidYear)),
      );
      await expectLater(
        movements.readYearTotals(year),
        throwsA(isA<MovementFailure>()),
      );
    }
  });

  test(
    'Lectura agregada supera paginación y no consulta presupuesto ni fotos',
    () async {
      final root = await categories.create(name: 'Raíz', isIncome: false);
      await db.run(() async {
        for (var i = 0; i < 601; i++) {
          await real(root.node.id, i.isEven ? 100 : -100);
        }
        await real(null, -1, date: ValueDate(2026, 12, 31));
      });
      final grouped = await movements.readYearTotals(2026);
      expect(grouped, hasLength(2));
      expect(grouped.singleWhere((t) => t.month == 1).movementCount, 601);
      // Las tablas ajenas al informe no participan ni siquiera como control.
      await db.customStatement('DROP TABLE budgets');
      await db.customStatement('DROP TABLE wealth_values');
      await db.customStatement('DROP TABLE wealth_snapshots');
      final reader = _Reader(movements.readYearTotals);
      final result = await withReader(reader).read(2026);
      expect(reader.calls, 1);
      expect(result.annualTotal.movementCount, 602);
      expect(result.annualTotal.amountCents, 99);
    },
  );

  test(
    'Relectura tras editar, borrar, reclasificar y reorganizar histórico',
    () async {
      final root = await categories.create(name: 'Ingreso', isIncome: true);
      final other = await categories.create(name: 'Salida', isIncome: false);
      final child = await categories.create(
        name: 'Rama',
        parentId: root.node.id,
      );
      final movement = await real(child.node.id, 100);
      final old = await query.read(2026);
      await movements.edit(
        movement.id,
        MovementInput(
          accountId: secondAccount,
          valueDate: ValueDate(2026, 12, 31),
          concept: 'Corregido',
          amountCents: -150,
          categoryId: child.node.id,
        ),
      );
      await categories.move(child.node.id, parentId: other.node.id);
      await categories.rename(other.node.id, name: 'Salidas');
      await categories.archive(child.node.id);
      final current = await query.read(2026);
      expect(row(current, root.node.id).annualTotal.amountCents, 0);
      expect(row(current, other.node.id).annualTotal.amountCents, -150);
      expect(row(current, child.node.id).category!.path, 'Salidas / Rama');
      expect(row(current, child.node.id).category!.node.isIncome, isFalse);
      expect(current.months.first.amountCents, 0);
      expect(current.months.last.amountCents, -150);
      expect(current.categoryGeneration, greaterThan(old.categoryGeneration));
      expect(
        current.datasetState.revision,
        greaterThan(old.datasetState.revision),
      );
      expect(row(old, child.node.id).category!.path, 'Ingreso / Rama');
      expect(old.annualTotal.amountCents, 100);
      await movements.setCategoryBatch([movement.id], null);
      expect(
        (await query.read(2026)).unclassified.annualTotal.amountCents,
        -150,
      );
      await movements.delete(movement.id);
      expect((await query.read(2026)).annualTotal.hasMovements, isFalse);
    },
  );

  test(
    'Cambio de base recompone conexión e identidad con invalidación común',
    () async {
      await real(null, 123);
      final old = await query.read(2026);
      await db.close();
      db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
      invalidation.invalidate();
      query = createAnnualActualQuery(database: db, invalidation: invalidation);
      final replaced = await query.read(2026);
      expect(
        replaced.datasetState.datasetId,
        isNot(old.datasetState.datasetId),
      );
      expect(replaced.categoryGeneration, greaterThan(old.categoryGeneration));
      expect(replaced.annualTotal.hasMovements, isFalse);
      expect(old.annualTotal.amountCents, 123);
    },
  );

  test(
    'Overflow directo SQLite; compensación intermedia exacta int64',
    () async {
      const max = 9223372036854775807;
      await real(null, max);
      await real(null, 1);
      await expectLater(
        movements.readYearTotals(2026),
        throwsA(isA<MovementTotalsOverflow>()),
      );
      await expectLater(
        query.read(2026),
        throwsA(failure(AnnualActualFailureCode.overflow)),
      );
      await real(null, -max);
      final result = await query.read(2026);
      expect(result.annualTotal.amountCents, 1);
      expect(result.annualTotal.movementCount, 3);
      await real(null, -9223372036854775808);
      expect(
        (await query.read(2026)).annualTotal.amountCents,
        -9223372036854775807,
      );
      await real(null, -2);
      await expectLater(
        query.read(2026),
        throwsA(failure(AnnualActualFailureCode.overflow)),
      );
    },
  );

  test(
    'Overflow de rama, total mensual y anual; BigInt evita pérdida intermedia',
    () async {
      const max = 9223372036854775807;
      final root = await categories.create(name: 'Raíz', isIncome: false);
      final a = await categories.create(name: 'A', parentId: root.node.id);
      final b = await categories.create(name: 'B', parentId: root.node.id);
      final c = await categories.create(name: 'C', parentId: root.node.id);
      final first = await real(a.node.id, max);
      final extra = await real(b.node.id, 1);
      await expectLater(
        query.read(2026),
        throwsA(failure(AnnualActualFailureCode.overflow)),
      );
      final cancel = await real(c.node.id, -max);
      expect((await query.read(2026)).annualTotal.amountCents, 1);
      await movements.delete(extra.id);
      await movements.delete(cancel.id);
      final nullExtra = await real(null, 1);
      await expectLater(
        query.read(2026),
        throwsA(failure(AnnualActualFailureCode.overflow)),
      );
      await movements.delete(nullExtra.id);
      final next = await real(a.node.id, 1, date: ValueDate(2026, 2, 1));
      await expectLater(
        query.read(2026),
        throwsA(failure(AnnualActualFailureCode.overflow)),
      );
      await movements.delete(first.id);
      await real(a.node.id, -1);
      expect((await query.read(2026)).annualTotal.amountCents, 0);
      expect((await query.read(2026)).annualTotal.hasMovements, isTrue);
      await movements.delete(next.id);
    },
  );

  test(
    'Subtotales incoherentes fallan sin devolver cifras parciales',
    () async {
      final root = await categories.create(name: 'Raíz', isIncome: false);
      AnnualMovementTotal total({int month = 1, String? id, int count = 1}) =>
          AnnualMovementTotal(
            month: month,
            categoryId: id,
            amountCents: 0,
            movementCount: count,
          );
      for (final totals in [
        [total(month: 0)],
        [total(month: 13)],
        [total(count: 0)],
        [total(count: -1)],
        [total(id: 'ausente')],
        [total(id: root.node.id), total(id: root.node.id)],
        [total(), total()],
      ]) {
        await expectLater(
          withReader(_Reader((_) async => totals)).read(2026),
          throwsA(failure(AnnualActualFailureCode.invalidData)),
        );
      }
      final reader = _Reader((_) async => []);
      await expectLater(
        withReader(reader).read(0),
        throwsA(failure(AnnualActualFailureCode.invalidYear)),
      );
      expect(reader.calls, 0);
    },
  );

  test(
    'Invalidación durante lectura y después de transacción descarta resultado',
    () async {
      for (final after in [false, true]) {
        final reader = _Reader((year) async {
          if (!after) invalidation.invalidate();
          return movements.readYearTotals(year);
        });
        final uow = after
            ? _AfterRead(SqliteReadUnitOfWork(db), invalidation.invalidate)
            : null;
        await expectLater(
          withReader(reader, unitOfWork: uow).read(2026),
          throwsA(failure(AnnualActualFailureCode.invalidated)),
        );
        expect(reader.calls, 1);
      }
      expect(
        (await query.read(2026)).categoryGeneration,
        invalidation.generation,
      );
    },
  );

  test('Error de persistencia español y reintento sin cero ficticio', () async {
    await expectLater(
      withReader(_Reader((_) async => throw StateError('SQLite privado')))
          .read(2026),
      throwsA(failure(AnnualActualFailureCode.persistence)),
    );
    await real(null, 1);
    expect((await query.read(2026)).annualTotal.amountCents, 1);
    await db.customStatement('DROP TABLE movements');
    await expectLater(
      query.read(2026),
      throwsA(failure(AnnualActualFailureCode.persistence)),
    );
  });

  test(
    'Snapshot único de árbol, reales y revisión ante otra conexión',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'real-anual-174-',
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
        final accounts = SqliteAccountRepository(local);
        final localAccount = await accounts.create(
          name: 'Cuenta sintética',
          kind: AccountKind.account,
          activeFrom: Month(2026, 1),
          liquidity: Liquidity.liquid,
        );
        final repo = SqliteMovementRepository(local);
        final original = await repo.create(
          MovementInput(
            accountId: localAccount.id,
            valueDate: ValueDate(2026, 1, 1),
            concept: 'Sintético',
            amountCents: 101,
            categoryId: root.node.id,
          ),
        );
        final before = await local.readState();
        final competing = sqlite3.open(file.path);
        try {
          final reader = _Reader((year) async {
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
            return repo.readYearTotals(year);
          });
          final snapshot = await AnnualActualQuery(
            movements: reader,
            categories: localCategories,
            unitOfWork: SqliteReadUnitOfWork(local),
          ).read(2026);
          expect(snapshot.rows.single.category!.path, 'Antes');
          expect(snapshot.annualTotal.amountCents, 101);
          expect(snapshot.datasetState.revision, before.revision);
          expect(reader.calls, 1);
          competing.execute('BEGIN IMMEDIATE');
          competing.execute('ROLLBACK');
          await local.run(() async {
            await repo.edit(
              original.id,
              MovementInput(
                accountId: localAccount.id,
                valueDate: ValueDate(2026, 2, 1),
                concept: 'Sintético',
                amountCents: 202,
                categoryId: root.node.id,
              ),
            );
            await localCategories.rename(root.node.id, name: 'Después');
          });
          final fresh = await createAnnualActualQuery(
            database: local,
            invalidation: localInvalidation,
          ).read(2026);
          expect(fresh.rows.single.category!.path, 'Después');
          expect(fresh.months.first.amountCents, 0);
          expect(fresh.months[1].amountCents, 202);
          expect(fresh.datasetState.revision, before.revision + 1);
          expect(snapshot.annualTotal.amountCents, 101);
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

final class _Reader implements AnnualMovementTotalsReader {
  _Reader(this.read);
  final Future<List<AnnualMovementTotal>> Function(int) read;
  int calls = 0;
  @override
  Future<List<AnnualMovementTotal>> readYearTotals(int year) {
    calls++;
    return read(year);
  }
}

final class _AfterRead implements UnitOfWork {
  _AfterRead(this.inner, this.after);
  final UnitOfWork inner;
  final void Function() after;
  @override
  Future<T> run<T>(Future<T> Function() operation) async {
    final result = await inner.run(operation);
    after();
    return result;
  }

  @override
  Future<DatasetState> readState() => inner.readState();
}
