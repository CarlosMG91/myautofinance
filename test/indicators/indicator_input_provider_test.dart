import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart'
    show LocalDatabase;
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_read_unit_of_work.dart';
import 'package:myautofinance/app/indicator_input_factory.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/app/wealth_management_factory.dart';
import 'package:myautofinance/core/persistence/unit_of_work.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/indicators/indicators.dart';
import 'package:myautofinance/features/importing/data/historical_csv_reader.dart';
import 'package:myautofinance/features/importing/historical_csv.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:sqlite3/sqlite3.dart';

const _all = {IndicatorInput.monthlyWealth, IndicatorInput.annualIncomeBudget};

final class _BudgetReader implements BudgetRepository {
  _BudgetReader(this.read);
  final Future<List<BudgetRecord>> Function(int) read;
  @override
  Future<List<BudgetRecord>> readYear(int year, {bool incomeOnly = false}) {
    expect(incomeOnly, isTrue);
    return read(year);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Operación inesperada: ${invocation.memberName}');
}

final class _AfterState implements UnitOfWork {
  _AfterState(this.inner, this.after);
  final UnitOfWork inner;
  final void Function() after;
  @override
  Future<T> run<T>(Future<T> Function() operation) => inner.run(operation);
  @override
  Future<DatasetState> readState() async {
    final state = await inner.readState();
    after();
    return state;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
  late LocalDatabase db;
  late WealthManagement wealth;
  late CategoryManagement categories;
  late SqliteBudgetRepository budgets;
  late IndicatorInputProvider provider;
  final january = Month(2026, 1), february = Month(2026, 2);

  Future<AccountRecord> account(
    String name, {
    AccountKind kind = AccountKind.account,
    Liquidity liquidity = Liquidity.liquid,
    Month? from,
    Month? through,
  }) => wealth.accounts.create(
    name: name,
    kind: kind,
    activeFrom: from ?? january,
    activeThrough: through,
    liquidity: kind == AccountKind.debt ? null : liquidity,
  );

  Future<BudgetRecord> budget(
    String category,
    int cents, {
    int month = 1,
    int year = 2026,
  }) => budgets.create(
    BudgetInput(
      month: BudgetMonth(year, month),
      categoryId: category,
      amountCents: cents,
    ),
  );

  RepositoryIndicatorInputProvider withReader(
    BudgetRepository reader, {
    UnitOfWork? unitOfWork,
  }) => RepositoryIndicatorInputProvider(
    wealth: wealth,
    budgets: reader,
    unitOfWork: unitOfWork ?? SqliteReadUnitOfWork(db),
  );

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    wealth = createWealthManagement(database: db);
    categories = createCategoryManagement(
      database: db,
      invalidation: CategoryReadInvalidation(),
    );
    budgets = SqliteBudgetRepository(db);
    provider = createIndicatorInputProvider(database: db);
  });
  tearDown(() async {
    await categories.invalidation.close();
    await db.close();
  });

  test('EP-001 D/G: foto exacta, pendientes y cantidades originales', () async {
    final accounts = [
      await account('Cuenta principal'),
      await account('Cuenta ahorro'),
      await account(
        'Cartera',
        kind: AccountKind.portfolio,
        liquidity: Liquidity.medium,
      ),
      await account('Deuda', kind: AccountKind.debt),
      await account('Inmueble', liquidity: Liquidity.illiquid),
    ];
    final amounts = [600000, 300000, 1000000, 500000, 2000000];
    for (var i = 0; i < accounts.length; i++) {
      await wealth.photos.setValue(january, accounts[i].id, amounts[i]);
    }
    final income = await categories.create(name: 'Ingresos', isIncome: true);
    for (var month = 1; month <= 12; month++) {
      await budget(income.node.id, 300000, month: month);
    }
    final result = await provider.read(january, _all);
    expect(result.wealth!.month.value, '2026-01-01');
    expect(result.wealth!.status, WealthSnapshotStatus.complete);
    expect(result.wealth!.liquidAssetsCents, 900000);
    expect(
      result.wealth!.values.map((v) => v.amountCents),
      unorderedEquals(amounts),
    );
    expect(result.annualIncome!.totalCents, BigInt.from(3600000));
    expect(result.annualIncome!.isComplete, isTrue);
    expect(result.annualIncome!.pendingMonths, isEmpty);
    expect(result.datasetState!.datasetId, (await db.readState()).datasetId);

    var missing = (await provider.read(february, _all)).wealth!;
    expect(missing.status, WealthSnapshotStatus.absent);
    expect(missing.pending, hasLength(5));
    expect(missing.liquidAssetsCents, isNull);
    await wealth.photos.setValue(february, accounts[0].id, 620000);
    await wealth.photos.setValue(february, accounts[1].id, 0);
    missing = (await provider.read(february, _all)).wealth!;
    expect(missing.status, WealthSnapshotStatus.incomplete);
    expect(missing.liquidAssetsCents, isNull);
    expect(
      missing.pending.map((a) => a.id),
      unorderedEquals(accounts.skip(2).map((a) => a.id)),
    );
    expect(
      missing.values.map((v) => v.amountCents),
      unorderedEquals([620000, 0]),
    );
  });

  test(
    'Vigencia inclusiva y liquidez histórica efectiva, sin arrastre',
    () async {
      final closed = await account('Cerrada', through: january);
      final future = await account('Futura', from: Month(2026, 3));
      final portfolio = await account(
        'Cartera',
        kind: AccountKind.portfolio,
        liquidity: Liquidity.medium,
      );
      await wealth.photos.setValue(january, closed.id, 100);
      await wealth.photos.setValue(january, portfolio.id, 200);
      await wealth.photos.setValue(february, portfolio.id, 300);
      await wealth.accounts.changeLiquidity(
        portfolio.id,
        february,
        Liquidity.liquid,
      );
      expect(
        (await provider.read(january, _all)).wealth!.liquidAssetsCents,
        100,
      );
      final feb = (await provider.read(february, _all)).wealth!;
      expect(feb.liquidAssetsCents, 300);
      expect(feb.values.single.account.id, portfolio.id);
      expect(feb.values.single.account.liquidity, Liquidity.liquid);
      expect(feb.pending, isEmpty);
      final march = (await provider.read(Month(2026, 3), _all)).wealth!;
      expect(march.status, WealthSnapshotStatus.absent);
      expect(
        march.pending.map((a) => a.id),
        unorderedEquals([future.id, portfolio.id]),
      );
      await wealth.accounts.correctHistoricalLiquidity(
        portfolio.id,
        january,
        february,
        Liquidity.liquid,
      );
      expect(
        (await provider.read(january, _all)).wealth!.liquidAssetsCents,
        300,
      );
    },
  );

  test(
    'CSV EP-001: signo normalizado y procedencia histórica archivada',
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
        sha256: 'c' * 64,
        source: ImportSource.historicalCsv,
        originalName: 'historico-ejemplo.csv',
        contractVersion: '1',
        budgets: records,
      );
      await categories.archive(ids['Ingresos']!);
      final result = (await provider.read(january, _all)).annualIncome!;
      expect(result.totalCents, BigInt.from(3600000));
      expect(result.isComplete, isTrue);
      expect(result.sourceBudgets, hasLength(12));
      expect(
        result.sourceBudgets.every(
          (r) =>
              r.batchId == batch.id &&
              r.importRowId != null &&
              r.sourceOrdinal != null &&
              r.data.amountCents == 300000,
        ),
        isTrue,
      );
    },
  );

  test('Cero líquido explícito conserva foto completa', () async {
    final a = await account('Cuenta');
    await wealth.photos.setValue(january, a.id, 0);
    final result = await provider.read(january, _all);
    expect(result.wealth!.status, WealthSnapshotStatus.complete);
    expect(result.wealth!.liquidAssetsCents, 0);
    expect(result.annualIncome!.totalCents, BigInt.zero);
    expect(result.annualIncome!.pendingMonths, List.generate(12, (i) => i + 1));
  });

  test('EP-001 L/M/N: hermanos, raíces, archivo y traslado actual', () async {
    final income = await categories.create(name: 'Ingresos', isIncome: true);
    final salary = await categories.create(
      name: 'Salario',
      parentId: income.node.id,
    );
    final net = await categories.create(
      name: 'Nómina',
      parentId: salary.node.id,
    );
    final tax = await categories.create(
      name: 'Impuestos',
      parentId: salary.node.id,
    );
    final other = await categories.create(
      name: 'Otros ingresos',
      isIncome: true,
    );
    final expense = await categories.create(name: 'Gastos', isIncome: false);
    final expenseLeaf = await categories.create(
      name: 'Gasto positivo',
      parentId: expense.node.id,
    );
    final ids = <String>[];
    for (var month = 1; month <= 12; month++) {
      ids.add((await budget(net.node.id, 300000, month: month)).id);
      ids.add((await budget(tax.node.id, -60000, month: month)).id);
      ids.add((await budget(other.node.id, 0, month: month)).id);
      await budget(expenseLeaf.node.id, 999999, month: month);
    }
    await budget(income.node.id, 100, year: 2025);
    await budget(income.node.id, 100, year: 2027);
    await categories.archive(salary.node.id);
    final original = (await provider.read(february, _all)).annualIncome!;
    expect(original.year, 2026);
    expect(original.totalCents, BigInt.from(2880000));
    expect(original.isComplete, isTrue);
    expect(original.sourceBudgets, hasLength(36));
    expect(original.sourceBudgets.map((r) => r.id), unorderedEquals(ids));
    expect(() => original.sourceBudgets.clear(), throwsUnsupportedError);
    await categories.move(salary.node.id, parentId: expense.node.id);
    var current = (await provider.read(february, _all)).annualIncome!;
    expect(current.sourceBudgets, hasLength(12));
    expect(current.totalCents, BigInt.zero);
    expect(current.isComplete, isTrue);
    await categories.move(other.node.id, parentId: expense.node.id);
    current = (await provider.read(february, _all)).annualIncome!;
    expect(current.sourceBudgets, isEmpty);
    expect(current.pendingMonths, List.generate(12, (i) => i + 1));
    expect(original.totalCents, BigInt.from(2880000));
  });

  test(
    'Doce filas de enero solo completan enero; cero y cancelación cuentan',
    () async {
      final root = await categories.create(name: 'Ingresos', isIncome: true);
      for (var i = 0; i < 12; i++) {
        final leaf = await categories.create(
          name: 'Hoja $i',
          parentId: root.node.id,
        );
        await budget(leaf.node.id, i.isEven ? 1 : -1);
      }
      var result = (await provider.read(january, _all)).annualIncome!;
      expect(result.totalCents, BigInt.zero);
      expect(result.presentMonths, {1});
      expect(result.pendingMonths, List.generate(11, (i) => i + 2));
      for (var month = 2; month <= 12; month++) {
        await budget(root.node.id, 0, month: month);
      }
      result = (await provider.read(january, _all)).annualIncome!;
      expect(result.sourceBudgets, hasLength(23));
      expect(result.totalCents, BigInt.zero);
      expect(result.isComplete, isTrue);
    },
  );

  test(
    'Solo SELECT: consulta repetida no escribe ni modifica revisión',
    () async {
      final a = await account('Cuenta');
      await wealth.photos.setValue(january, a.id, 101);
      final income = await categories.create(name: 'Ingresos', isIncome: true);
      await budget(income.node.id, 0);
      final before = await db.readState();
      final changes =
          (await db.customSelect('SELECT total_changes() AS n').getSingle())
              .read<int>('n');
      for (var i = 0; i < 2; i++) {
        final result = await provider.read(january, _all);
        expect(result.datasetState!.revision, before.revision);
        expect(result.wealth!.liquidAssetsCents, 101);
        expect(result.annualIncome!.presentMonths, {1});
      }
      expect((await db.readState()).revision, before.revision);
      expect(
        (await db.customSelect('SELECT total_changes() AS n').getSingle())
            .read<int>('n'),
        changes,
      );
    },
  );

  test('Relee correcciones y borrados sin caché', () async {
    final a = await account('Cuenta');
    await wealth.photos.setValue(january, a.id, 100);
    final root = await categories.create(name: 'Ingresos', isIncome: true);
    final record = await budget(root.node.id, 200);
    final old = await provider.read(january, _all);
    await wealth.photos.setValue(january, a.id, 300);
    await budgets.edit(
      record.id,
      BudgetInput(
        month: BudgetMonth(2026, 1),
        categoryId: root.node.id,
        amountCents: -1,
      ),
    );
    final fresh = await provider.read(january, _all);
    expect(fresh.wealth!.liquidAssetsCents, 300);
    expect(fresh.annualIncome!.totalCents, -BigInt.one);
    expect(
      fresh.datasetState!.revision,
      greaterThan(old.datasetState!.revision),
    );
    await budgets.delete(record.id);
    expect(
      (await provider.read(january, _all)).annualIncome!.presentMonths,
      isEmpty,
    );
    expect(old.wealth!.liquidAssetsCents, 100);
    expect(old.annualIncome!.totalCents, BigInt.from(200));
  });

  test('Presupuesto suma BigInt más allá de int64 sin redondeo', () async {
    const max = 9223372036854775807;
    final root = await categories.create(name: 'Ingresos', isIncome: true);
    for (var month = 1; month <= 12; month++) {
      await budget(root.node.id, max, month: month);
    }
    final result = (await provider.read(january, _all)).annualIncome!;
    expect(result.totalCents, BigInt.from(max) * BigInt.from(12));
    expect(result.isComplete, isTrue);
    await budgets.edit(
      result.sourceBudgets.first.id,
      BudgetInput(
        month: BudgetMonth(2026, 1),
        categoryId: root.node.id,
        amountCents: -max,
      ),
    );
    expect(
      (await provider.read(january, _all)).annualIncome!.totalCents,
      BigInt.from(max) * BigInt.from(10),
    );
  });

  test(
    'Overflow patrimonial es fallo técnico, nunca líquidos envueltos',
    () async {
      final a = await account('Cuenta A');
      final b = await account('Cuenta B');
      await wealth.photos.setValue(january, a.id, 9223372036854775807);
      await wealth.photos.setValue(january, b.id, 1);
      final incomeOnly = await provider.read(january, {
        IndicatorInput.annualIncomeBudget,
      });
      expect(incomeOnly.wealth, isNull);
      expect(incomeOnly.annualIncome!.totalCents, BigInt.zero);
      await expectLater(
        provider.read(january, _all),
        throwsA(
          isA<IndicatorReadFailure>()
              .having((e) => e.code, 'código', IndicatorReadFailureCode.read)
              .having((e) => e.cause, 'causa', isA<WealthFailure>()),
        ),
      );
    },
  );

  test(
    'Solicita solo las entradas requeridas y valida el año retornado',
    () async {
      final readError = StateError('fallo sintético');
      final reader = _BudgetReader((_) async => throw readError);
      final partial = await withReader(reader)
          .read(january, {IndicatorInput.monthlyWealth});
      expect(partial.wealth!.status, WealthSnapshotStatus.absent);
      expect(partial.annualIncome, isNull);
      final empty = await withReader(reader).read(january, {});
      expect(empty.wealth, isNull);
      expect(empty.annualIncome, isNull);
      await expectLater(
        withReader(reader).read(january, _all),
        throwsA(
          isA<IndicatorReadFailure>().having(
            (e) => e.cause,
            'causa',
            same(readError),
          ),
        ),
      );
      for (final records in [
        [
          BudgetRecord(
            id: 'wrong-year',
            data: BudgetInput(
              month: BudgetMonth(2025, 1),
              categoryId: 'income',
              amountCents: 1,
            ),
          ),
        ],
        List.filled(
          2,
          BudgetRecord(
            id: 'duplicate',
            data: BudgetInput(
              month: BudgetMonth(2026, 1),
              categoryId: 'income',
              amountCents: 1,
            ),
          ),
        ),
      ]) {
        await expectLater(
          withReader(_BudgetReader((_) async => records)).read(january, _all),
          throwsA(
            isA<IndicatorReadFailure>().having(
              (e) => e.code,
              'código',
              IndicatorReadFailureCode.invalidInputs,
            ),
          ),
        );
      }
    },
  );

  test('Calendario límite no incluye otro año', () async {
    final root = await categories.create(name: 'Ingresos', isIncome: true);
    await budget(root.node.id, 1, year: 1);
    await budget(root.node.id, 9999, year: 9999, month: 12);
    final first = (await provider.read(Month(1, 1), _all)).annualIncome!;
    final last = (await provider.read(Month(9999, 12), _all)).annualIncome!;
    expect(first.totalCents, BigInt.one);
    expect(first.presentMonths, {1});
    expect(last.totalCents, BigInt.from(9999));
    expect(last.presentMonths, {12});
  });

  test(
    'SQLite WAL: bloquea escritura concurrente hasta cerrar snapshot coherente',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'indicator-snapshot-',
      );
      final file = File('${directory.path}/test.sqlite');
      final disk = LocalDatabase(
        NativeDatabase(file, setup: configureConnection),
      );
      addTearDown(() async {
        await disk.close();
        await directory.delete(recursive: true);
      });
      await disk.customStatement('PRAGMA journal_mode=WAL');
      final management = createWealthManagement(database: disk);
      final a = await management.accounts.create(
        name: 'Cuenta',
        kind: AccountKind.account,
        activeFrom: january,
        liquidity: Liquidity.liquid,
      );
      await management.photos.setValue(january, a.id, 100);
      final tree = createCategoryManagement(
        database: disk,
        invalidation: CategoryReadInvalidation(),
      );
      addTearDown(tree.invalidation.close);
      final root = await tree.create(name: 'Ingresos', isIncome: true);
      final expense = await tree.create(name: 'Salida', isIncome: false);
      final child = await tree.create(name: 'Salario', parentId: root.node.id);
      final diskBudgets = SqliteBudgetRepository(disk);
      await diskBudgets.create(
        BudgetInput(
          month: BudgetMonth(2026, 1),
          categoryId: child.node.id,
          amountCents: 200,
        ),
      );
      final before = await disk.readState();
      final external = sqlite3.open(file.path);
      addTearDown(external.close);
      configureConnection(external);
      final concurrent = RepositoryIndicatorInputProvider(
        wealth: management,
        budgets: diskBudgets,
        unitOfWork: _AfterState(SqliteReadUnitOfWork(disk), () {
          expect(
            () => external.execute('BEGIN IMMEDIATE'),
            throwsA(
              isA<SqliteException>().having(
                (e) => e.resultCode,
                'SQLITE_BUSY',
                5,
              ),
            ),
          );
        }),
      );
      final snapshot = await concurrent.read(january, _all);
      expect(snapshot.datasetState!.revision, before.revision);
      expect(snapshot.wealth!.liquidAssetsCents, 100);
      expect(snapshot.annualIncome!.totalCents, BigInt.from(200));
      external.execute('BEGIN IMMEDIATE');
      external.execute('UPDATE wealth_values SET amount_cents=999');
      external.execute('UPDATE budgets SET amount_cents=777');
      external.execute('UPDATE categories SET parent_id=? WHERE id=?', [
        expense.node.id,
        child.node.id,
      ]);
      external.execute('UPDATE database_state SET revision=revision+1');
      external.execute('COMMIT');
      final next = await createIndicatorInputProvider(database: disk)
          .read(january, _all);
      expect(next.datasetState!.revision, before.revision + 1);
      expect(next.wealth!.liquidAssetsCents, 999);
      expect(next.annualIncome!.sourceBudgets, isEmpty);
    },
  );

  test(
    'Sesión restaura y recompone proveedor con la conexión activa',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'indicator-restore-',
      );
      final session = LocalBackupSession(
        supportDirectory: () async => directory,
      );
      addTearDown(() async {
        session.controller.dispose();
        await session.categoryInvalidation.close();
        await session.store.close();
        await directory.delete(recursive: true);
      });
      expect(await session.open(), isTrue);
      final management = await session.wealth();
      final a = await management.accounts.create(
        name: 'Cuenta',
        kind: AccountKind.account,
        activeFrom: january,
        liquidity: Liquidity.liquid,
      );
      await management.photos.setValue(january, a.id, 100);
      final tree = await session.categories();
      final root = await tree.create(name: 'Ingresos', isIncome: true);
      final oldDatabase = await session.store.open();
      final record = await SqliteBudgetRepository(oldDatabase).create(
        BudgetInput(
          month: BudgetMonth(2026, 1),
          categoryId: root.node.id,
          amountCents: 200,
        ),
      );
      await session.controller.create();
      expect(session.controller.error, isNull);
      final selected = session.controller.listing!.entries.single.backupId;
      final before = await (await session.indicatorInputs()).read(
        january,
        _all,
      );
      await management.photos.setValue(january, a.id, 999);
      await SqliteBudgetRepository(oldDatabase).delete(record.id);
      final edited = await (await session.indicatorInputs()).read(
        january,
        _all,
      );
      expect(edited.wealth!.liquidAssetsCents, 999);
      expect(edited.annualIncome!.sourceBudgets, isEmpty);
      await session.controller.restore(selected, confirmed: true);
      expect(
        session.controller.restoreResult!.status,
        LocalRestoreStatus.restored,
      );
      expect(identical(await session.store.open(), oldDatabase), isFalse);
      final restored = await (await session.indicatorInputs()).read(
        january,
        _all,
      );
      expect(restored.wealth!.liquidAssetsCents, 100);
      expect(restored.annualIncome!.totalCents, BigInt.from(200));
      expect(restored.annualIncome!.sourceBudgets.single.id, record.id);
      expect(restored.datasetState!.datasetId, before.datasetState!.datasetId);
      expect(restored.datasetState!.revision, before.datasetState!.revision);
    },
  );
}
