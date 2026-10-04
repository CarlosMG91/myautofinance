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
  const absentId = '00000000-0000-0000-0000-000000000000';
  late Directory directory;
  late LocalDatabaseStore store;
  late LocalDatabase db;
  late MovementManagement management;
  late SqliteMovementRepository repository;
  late SqliteCategoryRepository categories;
  late SqliteImportBatchRepository batches;
  late String accountId, rootId, childId, leafId;
  late List<String> ids;
  late List<ImportedMovement> imported;

  Future<int> revision() async => (await db.readState()).revision;
  Future<Map<String, Object?>> snapshot() async => {
    for (final table in [
      'categories',
      'accounts',
      'account_liquidity_periods',
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
  Future<List<Map<String, Object?>>> otherFields() async =>
      (await db.customSelect('SELECT * FROM movements ORDER BY id').get())
          .map(
            (row) => {...row.data}
              ..remove('category_id')
              ..remove('updated_at'),
          )
          .toList();
  Future<Map<String, Object?>> nonMovements() async => await snapshot()
    ..remove('movements')
    ..remove('database_state');
  Future<ImportBatch> import() => batches.create(
    sha256: 'a' * 64,
    source: ImportSource.historicalCsv,
    originalName: 'sintetico.csv',
    contractVersion: '1',
    movements: imported,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'movement-batch-synthetic-',
    );
    store = LocalDatabaseStore(supportDirectory: () async => directory);
    db = await store.open();
    repository = SqliteMovementRepository(db);
    management = createMovementManagement(database: db);
    categories = SqliteCategoryRepository(db);
    batches = SqliteImportBatchRepository(db);
    accountId = (await SqliteAccountRepository(db).create(
      name: 'Cuenta sintética',
      kind: AccountKind.account,
      activeFrom: Month(2026, 3),
      liquidity: Liquidity.liquid,
    )).id;
    rootId = (await categories.create(name: 'Ocio sintético')).id;
    childId = (await categories.create(name: 'Café', parentId: rootId)).id;
    leafId = (await categories.create(name: 'Terraza', parentId: childId)).id;
    imported = [
      for (var i = 0; i < 2; i++)
        ImportedMovement(
          i + 2,
          MovementInput(
            accountId: accountId,
            valueDate: ValueDate(2026, 3, 31 - i),
            concept: 'Café',
            amountCents: i == 0 ? 1250 : -450,
            categoryId: rootId,
            discretion: i == 0 ? 'regalo' : null,
          ),
        ),
    ];
    await import();
    ids = (await repository.readMonth(2026, 3)).map((r) => r.id).toList();
    for (var i = 0; i < 2; i++) {
      ids.add(
        (await management.create(
          accountId: accountId,
          valueDate: i == 0 ? '2026-03-01' : '2026-04-01',
          concept: i == 0 ? 'Árbol' : 'CAFE',
          amount: i == 0 ? '-3' : '-2',
          categoryId: i == 0 ? childId : null,
          discretion: 'capricho',
        )).id,
      );
    }
    await SqliteBudgetRepository(db).create(
      BudgetInput(
        month: BudgetMonth(2026, 3),
        categoryId: rootId,
        amountCents: -2000,
      ),
    );
    await SqliteWealthRepository(db).setValue(Month(2026, 3), accountId, 12345);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'Asignar/quitar solo categoría, una revisión, procedencia y reapertura',
    () async {
      final fields = await otherFields();
      final unrelated = await nonMovements();
      final before = await revision();
      for (final target in [childId, leafId, rootId]) {
        final previous = await revision();
        await management.assignCategory([ids[0], ids[1], ids[0]], target);
        expect(await revision(), previous + 1);
        for (final id in ids.take(2)) {
          final movement = await management.get(id);
          expect(movement.data.categoryId, target);
          expect(movement.importRowId, isNotNull);
          expect(movement.batchId, isNotNull);
          expect(movement.sourceOrdinal, anyOf(2, 3));
        }
        expect(await otherFields(), fields);
        expect(await nonMovements(), unrelated);
      }
      await management.removeCategory([ids[0], ids[1], ids[0]]);
      expect(await revision(), before + 4);
      expect(await otherFields(), fields);
      expect(await nonMovements(), unrelated);
      final noOp = await snapshot();
      await management.removeCategory([ids[0], ids[1]]);
      expect(await snapshot(), noOp);
      await store.close();
      db = await store.open();
      management = createMovementManagement(database: db);
      expect(await snapshot(), noOp);
      for (final id in ids.take(2)) {
        expect((await management.get(id)).data.categoryId, isNull);
      }
    },
  );

  test(
    'Página visible captura UUID: conserva resultados restantes y otros meses',
    () async {
      final page = await repository.readPage(
        from: ValueDate(2026, 3, 1),
        until: ValueDate(2026, 4, 1),
        limit: 2,
      );
      expect(page.nextCursor, isNotNull);
      final selected = page.records.map((r) => r.id).toList();
      final unselected = ids.where((id) => !selected.contains(id)).toList();
      final untouched = {
        for (final id in unselected)
          id:
              (await db
                      .customSelect("SELECT * FROM movements WHERE id='$id'")
                      .getSingle())
                  .data,
      };
      final before = await revision();
      final operation = management.assignCategory(selected, leafId);
      selected.clear();
      selected.addAll(unselected);
      await operation;
      expect(await revision(), before + 1);
      for (final record in page.records) {
        expect((await management.get(record.id)).data.categoryId, leafId);
      }
      for (final id in unselected) {
        expect(
          (await db
                  .customSelect("SELECT * FROM movements WHERE id='$id'")
                  .getSingle())
              .data,
          untouched[id],
        );
      }
      final noOp = await snapshot();
      await management.assignCategory(
        page.records.map((r) => r.id).toList(),
        leafId,
      );
      expect(await snapshot(), noOp);
    },
  );

  test('Borrar UUID explícitos deduplicados conserva importación e impide resurrección', () async {
    final unrelated = await nonMovements();
    final before = await revision();
    await management.deleteBatch([ids[0], ids[2], ids[0]]);
    expect(await revision(), before + 1);
    expect(await repository.get(ids[0]), isNull);
    expect(await repository.get(ids[2]), isNull);
    expect(await repository.get(ids[1]), isNotNull);
    expect(await repository.get(ids[3]), isNotNull);
    expect(await nonMovements(), unrelated);
    final deleted = await snapshot();
    await expectLater(import(), throwsA(isA<MovementFailure>()));
    expect(await snapshot(), deleted);
    await store.close();
    db = await store.open();
    expect(await snapshot(), deleted);
  });

  test(
    'Selección desaparecida rechaza asignar, retirar y borrar sin cambios',
    () async {
      final selected = [ids[0], ids[1]];
      await management.delete(ids[1]);
      final before = await snapshot();
      for (final action in <Future<void> Function()>[
        () => management.assignCategory(selected, childId),
        () => management.removeCategory(selected),
        () => management.deleteBatch(selected),
      ]) {
        await expectLater(action(), throwsA(isA<MovementFailure>()));
        expect(await snapshot(), before);
      }
    },
  );

  test(
    'Categoría desaparecida/archivada rechaza entero, incluso no-op histórico',
    () async {
      await categories.setArchived(rootId, archived: true);
      final before = await snapshot();
      for (final target in [absentId, rootId, childId, leafId]) {
        await expectLater(
          management.assignCategory([ids[0], ids[1], ids[3]], target),
          throwsA(isA<MovementFailure>()),
        );
        expect(await snapshot(), before);
      }
      await expectLater(
        management.assignCategory([ids[0], ids[1]], rootId),
        throwsA(isA<MovementFailure>()),
      );
      expect(await snapshot(), before);
      // Retirar sigue permitido en movimientos históricos archivados.
      final previous = await revision();
      await management.removeCategory([ids[0], ids[1]]);
      expect(await revision(), previous + 1);
    },
  );

  test(
    'Lotes vacíos, UUID inválidos y desconocidos nunca amplían selección',
    () async {
      final before = await snapshot();
      for (final selection in <List<String>>[
        [],
        [ids[0], 'invalid'],
        [ids[0], absentId],
      ]) {
        for (final action in <Future<void> Function()>[
          () => management.assignCategory(selection, childId),
          () => management.removeCategory(selection),
          () => management.deleteBatch(selection),
          () async => repository.setCategoryBatch(selection, childId),
          () async => repository.setCategoryBatch(selection, null),
          () async => repository.deleteBatch(selection),
        ]) {
          await expectLater(action(), throwsA(isA<MovementFailure>()));
          expect(await snapshot(), before);
        }
      }
      await expectLater(
        management.assignCategory(ids, 'invalid'),
        throwsA(isA<MovementFailure>()),
      );
      expect(await snapshot(), before);
    },
  );

  for (final operation in ['asignar', 'retirar', 'borrar']) {
    for (final failure in ['ABORT', 'IGNORE']) {
      test('$operation: fallo $failure en segunda fila revierte lote y revisión', () async {
        final event = operation == 'borrar'
            ? 'DELETE'
            : 'UPDATE OF category_id';
        await db.customStatement(
          'CREATE TEMP TRIGGER synthetic_batch_failure BEFORE $event ON movements '
          "WHEN OLD.id='${ids[1]}' BEGIN SELECT RAISE($failure${failure == 'ABORT' ? ",'synthetic failure'" : ''}); END",
        );
        final before = await snapshot();
        Future<void> run({required bool direct}) {
          final selection = [ids[0], ids[1]];
          return switch (operation) {
            'asignar' =>
              direct
                  ? repository.setCategoryBatch(selection, childId)
                  : management.assignCategory(selection, childId),
            'retirar' =>
              direct
                  ? repository.setCategoryBatch(selection, null)
                  : management.removeCategory(selection),
            _ =>
              direct
                  ? repository.deleteBatch(selection)
                  : management.deleteBatch(selection),
          };
        }

        for (final direct in [false, true]) {
          if (failure == 'IGNORE' || !direct) {
            await expectLater(
              run(direct: direct),
              throwsA(isA<MovementFailure>()),
            );
          } else {
            await expectLater(run(direct: direct), throwsA(isA<Exception>()));
          }
          // Todas las tablas financieras, procedencia, timestamps y revisión.
          expect(await snapshot(), before);
        }
        await db.customStatement('DROP TRIGGER synthetic_batch_failure');
        final previous = await revision();
        await run(direct: true);
        expect(await revision(), previous + 1);
        expect(
          await nonMovements(),
          {...before}
            ..remove('movements')
            ..remove('database_state'),
        );
      });
    }
  }

  test(
    'Lote mixto con no-op conserva timestamps y cuenta una única revisión',
    () async {
      final untouched = await db
          .customSelect("SELECT * FROM movements WHERE id='${ids[2]}'")
          .getSingle();
      final fields = await otherFields();
      final before = await revision();
      // ids[2] ya pertenece a childId; ids[0] cambia desde la raíz.
      await management.assignCategory([ids[2], ids[0]], childId);
      expect(await revision(), before + 1);
      expect((await management.get(ids[0])).data.categoryId, childId);
      expect(
        (await db
                .customSelect("SELECT * FROM movements WHERE id='${ids[2]}'")
                .getSingle())
            .data,
        untouched.data,
      );
      expect(await otherFields(), fields);
    },
  );

  test(
    'Fallo al confirmar revisión revierte también todas las filas del lote',
    () async {
      await db.customStatement(
        "CREATE TEMP TRIGGER synthetic_revision_failure BEFORE UPDATE OF revision ON database_state BEGIN SELECT RAISE(ABORT,'synthetic failure'); END",
      );
      final before = await snapshot();
      for (final action in <Future<void> Function()>[
        () => management.assignCategory([ids[0], ids[1]], leafId),
        () => management.removeCategory([ids[0], ids[1]]),
        () => management.deleteBatch([ids[0], ids[1]]),
      ]) {
        await expectLater(action(), throwsA(isA<MovementFailure>()));
        expect(await snapshot(), before);
      }
    },
  );
}
