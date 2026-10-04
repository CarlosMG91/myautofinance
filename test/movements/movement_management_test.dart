import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/app/movement_management_factory.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Importes exactos con coma/punto, signos y límites int64', () {
    for (final entry in {
      '1': 100,
      '+1,2': 120,
      '-1.23': -123,
      ' 0,01 ': 1,
      '92233720368547758.07': 9223372036854775807,
      '-92233720368547758,08': -9223372036854775808,
    }.entries) {
      expect(parseMovementAmount(entry.key), entry.value);
    }
    for (final invalid in [
      '',
      '0',
      '-0.00',
      '1.234',
      '1,234',
      '1,000.00',
      '1.000,00',
      '1 000',
      '1e2',
      'NaN',
      '.12',
      '1.',
      '--1',
      '92233720368547758.08',
      '-92233720368547758.09',
    ]) {
      expect(
        () => parseMovementAmount(invalid),
        throwsA(isA<MovementFailure>()),
        reason: invalid,
      );
    }
  });

  late Directory directory;
  late LocalDatabaseStore store;
  late LocalDatabase db;
  late MovementManagement management;
  late String accountId, categoryId;

  Future<int> revision() async => (await db.readState()).revision;
  Future<MovementRecord> create({String? category, String? discretion}) =>
      management.create(
        accountId: accountId,
        valueDate: '2026-03-31',
        concept: 'Café',
        amount: '-12,50',
        categoryId: category,
        discretion: discretion,
      );
  Future<Map<String, Object?>> snapshot() async => {
    for (final table in [
      'movements',
      'import_rows',
      'import_batches',
      'budgets',
      'wealth_snapshots',
      'wealth_values',
      'database_state',
    ])
      table: (await db.customSelect('SELECT * FROM $table ORDER BY 1').get())
          .map((r) => r.data)
          .toList(),
  };

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'movement-management-synthetic-',
    );
    store = LocalDatabaseStore(supportDirectory: () async => directory);
    db = await store.open();
    management = createMovementManagement(database: db);
    accountId = (await SqliteAccountRepository(db).create(
      name: 'Cuenta sintética',
      kind: AccountKind.account,
      activeFrom: Month(2026, 3),
      liquidity: Liquidity.liquid,
    )).id;
    categoryId = (await SqliteCategoryRepository(
      db,
    ).create(name: 'Ocio sintético')).id;
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'Altas idénticas legítimas, edición parcial, retirada y no-op',
    () async {
      final before = await revision();
      final a = await create(category: categoryId, discretion: '  capricho  ');
      final b = await create(category: categoryId, discretion: 'capricho');
      expect(a.id, isNot(b.id));
      expect(await revision(), before + 2);
      final changed = await management.edit(
        a.id,
        concept: 'Concepto corregido',
        discretion: const MovementChange('  regalo  '),
      );
      expect(await revision(), before + 3);
      expect(changed.id, a.id);
      expect(changed.data.accountId, a.data.accountId);
      expect(changed.data.valueDate.value, '2026-03-31');
      expect(changed.data.amountCents, -1250);
      expect(changed.data.categoryId, categoryId);
      expect(changed.data.discretion, 'regalo');
      expect(
        (await management.edit(a.id, amount: '+1.25')).data.discretion,
        'regalo',
      );
      final noOp = await snapshot();
      await management.edit(a.id);
      await management.edit(
        a.id,
        amount: '1,25',
        discretion: const MovementChange(' regalo '),
      );
      expect(await snapshot(), noOp);
      final removed = await management.edit(
        a.id,
        category: const MovementChange(null),
        discretion: const MovementChange(null),
      );
      expect(removed.data.categoryId, isNull);
      expect(removed.data.discretion, isNull);
      expect(removed.data.amountCents, 125);
      await management.setDiscretion(a.id, 'texto');
      expect(
        (await management.setDiscretion(a.id, '  ')).data.discretion,
        isNull,
      );
      await store.close();
      db = await store.open();
      management = createMovementManagement(database: db);
      expect((await management.get(a.id)).data.amountCents, 125);
      expect((await management.get(b.id)).data.discretion, 'capricho');
      final deleteBefore = await revision();
      await management.delete(a.id);
      expect(await revision(), deleteBefore + 1);
      final deleted = await snapshot();
      await expectLater(
        management.delete(a.id),
        throwsA(isA<MovementFailure>()),
      );
      expect(await snapshot(), deleted);
    },
  );

  test('Rechazos de alta/edición preservan datos y revisión, sin tocar fotos/presupuesto', () async {
    await SqliteWealthRepository(db).setValue(Month(2026, 3), accountId, 12345);
    await SqliteBudgetRepository(db).create(
      BudgetInput(
        month: BudgetMonth(2026, 3),
        categoryId: categoryId,
        amountCents: -2000,
      ),
    );
    final a = await create(discretion: 'conservar');
    final accounts = SqliteAccountRepository(db);
    await accounts.close(accountId, Month(2026, 3));
    final wrongAccounts = <String>[];
    for (final kind in [AccountKind.debt, AccountKind.portfolio]) {
      wrongAccounts.add(
        (await accounts.create(
          name: 'Ficha sintética',
          kind: kind,
          activeFrom: Month(2026, 3),
          liquidity: kind == AccountKind.debt ? null : Liquidity.medium,
        )).id,
      );
    }
    final before = await snapshot();
    final actions = <Future<Object?> Function()>[
      () => management.edit(a.id, valueDate: '2026-02-29'),
      () => management.edit(a.id, valueDate: '2026-04-01'),
      () => management.edit(a.id, valueDate: '2026-02-28'),
      () => management.edit(a.id, concept: '  '),
      () => management.edit(a.id, amount: '0'),
      () => management.edit(a.id, amount: '1.234'),
      () => management.edit(
        a.id,
        category: const MovementChange('00000000-0000-0000-0000-000000000000'),
      ),
      () => management.edit(
        a.id,
        accountId: '00000000-0000-0000-0000-000000000000',
      ),
      () => management.edit('invalid', concept: 'otro'),
      () => management.edit(
        '00000000-0000-0000-0000-000000000000',
        concept: 'otro',
      ),
      for (final id in wrongAccounts)
        () => management.edit(
          a.id,
          accountId: id,
          discretion: const MovementChange('cambiar'),
        ),
      for (final date in [
        '2026-02-30',
        '2026-02-28',
        '2026-04-01',
        '0000-01-01',
        '2026-13-01',
      ])
        () => management.create(
          accountId: accountId,
          valueDate: date,
          concept: 'Alta',
          amount: '1',
        ),
      for (final id in wrongAccounts)
        () => management.create(
          accountId: id,
          valueDate: '2026-03-01',
          concept: 'Alta',
          amount: '1',
        ),
      () => management.create(
        accountId: accountId,
        valueDate: '2026-03-01',
        concept: '\t',
        amount: '1',
      ),
      () => management.create(
        accountId: accountId,
        valueDate: '2026-03-01',
        concept: 'Alta',
        amount: '0',
      ),
    ];
    for (final action in actions) {
      await expectLater(action(), throwsA(isA<MovementFailure>()));
      expect(await snapshot(), before);
    }
    final nonMovement = {...before}
      ..remove('movements')
      ..remove('database_state');
    await management.edit(
      a.id,
      concept: 'Correcto',
      amount: '2',
      discretion: const MovementChange('editada'),
    );
    await management.delete(a.id);
    final after = await snapshot();
    after.remove('movements');
    after.remove('database_state');
    expect(after, nonMovement);
  });

  test(
    'Categoría archivada conservable, nuevas asignaciones rechazadas',
    () async {
      final a = await create(category: categoryId);
      final b = await create();
      await SqliteCategoryRepository(db)
          .setArchived(categoryId, archived: true);
      expect(
        (await management.edit(a.id, concept: 'Corregido')).data.categoryId,
        categoryId,
      );
      final before = await snapshot();
      await expectLater(
        create(category: categoryId),
        throwsA(isA<MovementFailure>()),
      );
      await expectLater(
        management.edit(b.id, category: MovementChange(categoryId)),
        throwsA(isA<MovementFailure>()),
      );
      expect(await snapshot(), before);
      await management.edit(a.id, category: const MovementChange(null));
      await expectLater(
        management.edit(a.id, category: MovementChange(categoryId)),
        throwsA(isA<MovementFailure>()),
      );
    },
  );

  test(
    'Fallo de discrecionalidad después de editar revierte todo y la revisión',
    () async {
      final a = await create(discretion: 'original');
      await db.customStatement(
        "CREATE TEMP TRIGGER synthetic_discretion_failure BEFORE UPDATE OF discretion ON movements BEGIN SELECT RAISE(ABORT,'synthetic failure'); END",
      );
      final before = await snapshot();
      await expectLater(
        management.edit(
          a.id,
          concept: 'No guardar',
          amount: '100',
          discretion: const MovementChange('nueva'),
        ),
        throwsA(isA<MovementFailure>()),
      );
      expect(await snapshot(), before);
    },
  );

  test('Edición mantiene procedencia; borrado conserva identidad e impide resurrección', () async {
    final batches = SqliteImportBatchRepository(db);
    final imported = MovementInput(
      accountId: accountId,
      valueDate: ValueDate(2026, 3, 31),
      concept: 'Importado sintético',
      amountCents: -1250,
      discretion: 'original',
    );
    Future<ImportBatch> import() => batches.create(
      sha256: 'a' * 64,
      source: ImportSource.historicalCsv,
      originalName: 'sintetico.csv',
      contractVersion: '1',
      movements: [ImportedMovement(2, imported)],
    );
    final batch = await import();
    final a = (await SqliteMovementRepository(db).readMonth(2026, 3)).single;
    final before = await revision();
    final changed = await management.edit(
      a.id,
      amount: '5,25',
      concept: 'Corregido',
      discretion: const MovementChange('editada'),
    );
    expect(await revision(), before + 1);
    expect(changed.id, a.id);
    expect(changed.importRowId, a.importRowId);
    expect(changed.batchId, batch.id);
    expect(changed.sourceOrdinal, 2);
    final provenance = await db.customSelect('SELECT * FROM import_rows').get();
    await management.delete(a.id);
    expect(await revision(), before + 2);
    expect(
      (await db.customSelect('SELECT * FROM import_rows').get()).map(
        (r) => r.data,
      ),
      provenance.map((r) => r.data),
    );
    final deleted = await snapshot();
    await expectLater(import(), throwsA(isA<MovementFailure>()));
    expect(await snapshot(), deleted);
    expect(await SqliteMovementRepository(db).get(a.id), isNull);
  });
}
