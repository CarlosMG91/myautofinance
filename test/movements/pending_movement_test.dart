import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_preview_source.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/app/movement_management_factory.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

import '../importing/import_preview_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const missing = '00000000-0000-0000-0000-000000000000';
  late Directory directory;
  late LocalDatabaseStore store;
  late LocalDatabase db;
  late SqliteMovementRepository repo;
  late PendingMovementManagement management;
  late SqliteCategoryRepository categories;
  late String a1, a2, root, child, leaf, manual, batch1, batch2;

  MovementInput input(
    String account,
    String date,
    String concept, {
    int cents = -450,
    String? category,
  }) => MovementInput(
    accountId: account,
    valueDate: ValueDate.parse(date),
    concept: concept,
    amountCents: cents,
    categoryId: category,
    discretion: 'Discrecional sintético',
  );

  Future<Map<String, Object?>> snapshot() async {
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .get();
    return {
      for (final table in tables)
        table.read<String>('name'):
            (await db
                    .customSelect(
                      'SELECT * FROM ${table.read<String>('name')} ORDER BY 1',
                    )
                    .get())
                .map((row) => row.data)
                .toList(),
    };
  }

  Future<List<Map<String, Object?>>> otherFields() async =>
      (await db.customSelect('SELECT * FROM movements ORDER BY id').get())
          .map(
            (row) => {...row.data}
              ..remove('category_id')
              ..remove('updated_at'),
          )
          .toList();

  Future<int> revision() async => (await db.readState()).revision;
  List<String> ids(PendingMovementPage page) =>
      page.records.map((record) => record.id).toList();
  Future<LocalDatabase> secondConnection() async {
    final other = LocalDatabase(
      NativeDatabase(File(store.databasePath!), setup: configureConnection),
    );
    await other.readState();
    addTearDown(other.close);
    return other;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pending-synthetic-');
    store = LocalDatabaseStore(supportDirectory: () async => directory);
    db = await store.open();
    repo = SqliteMovementRepository(db);
    management = createPendingMovementManagement(database: db);
    categories = SqliteCategoryRepository(db);
    final accounts = SqliteAccountRepository(db);
    Future<String> account() async => (await accounts.create(
      name: 'Cuenta duplicada sintética',
      kind: AccountKind.account,
      activeFrom: Month(1, 1),
      liquidity: Liquidity.liquid,
    )).id;
    a1 = await account();
    a2 = await account();
    root = (await categories.create(name: 'Duplicada')).id;
    child = (await categories.create(name: 'Duplicada', parentId: root)).id;
    leaf = (await categories.create(name: 'Duplicada', parentId: child)).id;
    final batches = SqliteImportBatchRepository(db);
    batch1 = (await batches.create(
      sha256: 'a' * 64,
      source: ImportSource.historicalCsv,
      originalName: 'sintetico.csv',
      contractVersion: '1',
      movements: [
        ImportedMovement(2, input(a1, '2026-03-31', 'CAFÉ%_')),
        ImportedMovement(3, input(a1, '2026-03-31', 'CAFÉ%_')),
        ImportedMovement(4, input(a2, '2026-04-01', 'Árbol', cents: 1200)),
        ImportedMovement(5, input(a1, '2025-12-31', 'cafe%_')),
        ImportedMovement(6, input(a1, '2026-03-31', 'CAFÉ%_', category: root)),
        ImportedMovement(7, input(a1, '0001-01-01', 'Antiguo')),
        ImportedMovement(8, input(a1, '9999-12-31', 'Futuro')),
      ],
      budgets: [
        ImportedBudget(
          9,
          BudgetInput(
            month: BudgetMonth(2026, 3),
            categoryId: root,
            amountCents: -2000,
          ),
        ),
      ],
    )).id;
    batch2 = (await batches.create(
      sha256: 'b' * 64,
      source: ImportSource.bankXls,
      originalName: 'sintetico.xls',
      contractVersion: '1',
      movements: [
        ImportedMovement(2, input(a1, '2026-03-31', 'Cafe %_')),
        ImportedMovement(3, input(a2, '2026-04-02', "Café ' \\")),
      ],
    )).id;
    manual = (await repo.create(input(a1, '2026-03-31', 'CAFÉ%_'))).id;
    await SqliteWealthRepository(db).setValue(Month(2026, 3), a1, 12345);
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('Todos los periodos: solo REAL importado pendiente, orden estable y total SQL', () async {
    final before = await snapshot();
    final first = await management.readPage(limit: 2);
    expect(first.totalCount, 8);
    expect(first.records, hasLength(2));
    expect(first.records.first.data.valueDate.value, '9999-12-31');
    final seen = <MovementRecord>[];
    var page = first;
    while (true) {
      expect(page.totalCount, 8);
      expect(page.records.length, lessThanOrEqualTo(2));
      seen.addAll(page.records);
      if (page.nextCursor == null) break;
      page = await repo.readPendingPage(after: page.nextCursor, limit: 2);
    }
    expect(seen, hasLength(8));
    expect(seen.map((r) => r.id).toSet(), hasLength(8));
    expect(
      seen.every((r) => r.importRowId != null && r.data.categoryId == null),
      isTrue,
    );
    expect(seen.map((r) => r.id), isNot(contains(manual)));
    expect(seen.last.data.valueDate.value, '0001-01-01');
    final sorted = [...seen]
      ..sort((a, b) {
        final date = b.data.valueDate.compareTo(a.data.valueDate);
        return date == 0 ? a.id.compareTo(b.id) : date;
      });
    expect(seen.map((r) => r.id), sorted.map((r) => r.id));
    final exhausted = await repo.readPendingPage(
      after: MovementCursor(seen.last.data.valueDate, seen.last.id),
      limit: 2,
    );
    expect(exhausted.totalCount, 8);
    expect(exhausted.records, isEmpty);
    expect(exhausted.nextCursor, isNull);
    expect(await snapshot(), before);
  });

  test(
    'Filtros combinados por lote/cuenta/fechas y texto Unicode literal',
    () async {
      final page = await repo.readPendingPage(
        query: PendingMovementQuery(
          batchId: batch1,
          accountId: a1,
          from: ValueDate(2026, 3, 1),
          until: ValueDate(2026, 4, 1),
          concept: '  cafe%_  ',
        ),
        limit: 1,
      );
      expect(page.totalCount, 2);
      expect(page.records, hasLength(1));
      expect(page.records.single.batchId, batch1);
      final next = await repo.readPendingPage(
        query: PendingMovementQuery(
          batchId: batch1,
          accountId: a1,
          from: ValueDate(2026, 3, 1),
          until: ValueDate(2026, 4, 1),
          concept: 'cafe\u0301%_',
        ),
        after: page.nextCursor,
        limit: 1,
      );
      expect(next.totalCount, 2);
      expect(ids(next), isNot(ids(page)));
      expect(next.nextCursor, isNull);
      expect(
        (await repo.readPendingPage(
          query: PendingMovementQuery(batchId: batch2, concept: '%_'),
        )).totalCount,
        1,
      );
      expect(
        (await repo.readPendingPage(
          query: PendingMovementQuery(
            batchId: batch2,
            accountId: a2,
            concept: "' \\",
          ),
        )).totalCount,
        1,
      );
      expect(
        (await repo.readPendingPage(
          query: PendingMovementQuery(accountId: a2, concept: 'arbol'),
        )).totalCount,
        1,
      );
      expect(
        (await repo.readPendingPage(
          query: PendingMovementQuery(concept: 'cafe %_'),
        )).totalCount,
        1,
      );
      expect(
        (await repo.readPendingPage(
          query: PendingMovementQuery(batchId: missing),
        )).totalCount,
        0,
      );
      expect(
        (await repo.readPendingPage(
          query: PendingMovementQuery(until: ValueDate(2026, 1, 1)),
        )).totalCount,
        2,
      );
      expect(
        (await repo.readPendingPage(
          query: PendingMovementQuery(from: ValueDate(2026, 4, 1)),
        )).totalCount,
        3,
      );
    },
  );

  test(
    'Página 100/500: total distinto de tamaño, sin cargar todos ni omitir UUID',
    () async {
      await SqliteImportBatchRepository(db).create(
        sha256: 'c' * 64,
        source: ImportSource.bankXls,
        originalName: 'muchos-sinteticos.xls',
        contractVersion: '1',
        movements: [
          for (var i = 0; i < 520; i++)
            ImportedMovement(i + 2, input(a1, '2026-03-31', 'Muchos')),
        ],
      );
      final first = await repo.readPendingPage();
      expect(first.records, hasLength(100));
      expect(first.totalCount, 528);
      final rest = await repo.readPendingPage(
        after: first.nextCursor,
        limit: 500,
      );
      expect(rest.records, hasLength(428));
      expect(rest.totalCount, 528);
      expect(rest.nextCursor, isNull);
      expect({...ids(first), ...ids(rest)}, hasLength(528));
    },
  );

  test('Asignación de página/individual preserva campos, huella, presupuestos y fotos', () async {
    final page = await management.readPage(limit: 2);
    final selected = page.selectPage();
    final fields = await otherFields();
    final unrelated = await snapshot()
      ..remove('movements')
      ..remove('database_state');
    final before = await revision();
    await management.assignCategory(selected, leaf);
    expect(await revision(), before + 1);
    expect((await management.readPage()).totalCount, 6);
    expect(await otherFields(), fields);
    expect(
      await snapshot()
        ..remove('movements')
        ..remove('database_state'),
      unrelated,
    );
    for (final id in selected.movements.ids) {
      expect((await repo.get(id))!.data.categoryId, leaf);
    }
    expect((await repo.get(manual))!.data.categoryId, isNull);
    final next = await management.readPage();
    final explicitIds = [next.records.first.id, next.records.first.id];
    final single = next.select(explicitIds);
    explicitIds.clear();
    expect(single.movements.ids, hasLength(1));
    await management.assignCategory(single, child);
    expect(await revision(), before + 2);
    expect((await management.readPage()).totalCount, 5);
    final state = await snapshot();
    await store.close();
    db = await store.open();
    repo = SqliteMovementRepository(db);
    expect(await snapshot(), state);
    expect((await repo.readPendingPage()).totalCount, 5);
    await expectLater(
      SqliteImportBatchRepository(db).create(
        sha256: 'a' * 64,
        source: ImportSource.historicalCsv,
        originalName: 'sintetico.csv',
        contractVersion: '1',
        movements: [ImportedMovement(2, input(a1, '2026-03-31', 'CAFÉ%_'))],
      ),
      throwsA(isA<MovementFailure>()),
    );
    expect(await snapshot(), state);
  });

  test(
    'Validaciones de periodo/límite/UUID y selección no amplían el alcance',
    () async {
      final before = await snapshot();
      for (final limit in [0, 501]) {
        await expectLater(
          repo.readPendingPage(limit: limit),
          throwsA(isA<MovementFailure>()),
        );
      }
      expect(
        () => PendingMovementQuery(
          from: ValueDate(2026, 3, 1),
          until: ValueDate(2026, 3, 1),
        ),
        throwsA(isA<MovementFailure>()),
      );
      expect(
        () => PendingMovementQuery(batchId: 'invalid'),
        throwsA(isA<MovementFailure>()),
      );
      expect(
        () => PendingMovementQuery(accountId: 'invalid'),
        throwsA(isA<MovementFailure>()),
      );
      final page = await repo.readPendingPage(limit: 1);
      expect(() => page.select([]), throwsA(isA<MovementFailure>()));
      expect(() => page.select([manual]), throwsA(isA<MovementFailure>()));
      expect(
        () => PendingMovementSelection(
          ids: ['invalid'],
          databaseIdentity: db,
          datasetId: page.datasetId,
        ),
        throwsA(isA<MovementFailure>()),
      );
      await expectLater(
        management.assignCategory(page.selectPage(), 'invalid'),
        throwsA(isA<MovementFailure>()),
      );
      expect(await snapshot(), before);
    },
  );

  for (final change in [
    'category',
    'delete',
    'manual',
    'missing',
    'archive',
    'destination',
  ]) {
    test('Revalida $change: rechaza TODO y conserva cambios ajenos', () async {
      final page = await repo.readPendingPage(limit: 2);
      var selection = page.selectPage();
      var target = leaf;
      switch (change) {
        case 'category':
          await createMovementManagement(database: db)
              .assignCategory([page.records.last.id], child);
        case 'delete':
          await repo.delete(page.records.last.id);
        case 'manual':
          selection = PendingMovementSelection(
            ids: [page.records.first.id, manual],
            databaseIdentity: db,
            datasetId: page.datasetId,
          );
        case 'missing':
          selection = PendingMovementSelection(
            ids: [page.records.first.id, missing],
            databaseIdentity: db,
            datasetId: page.datasetId,
          );
        case 'archive':
          await categories.setArchived(root, archived: true);
        case 'destination':
          target = missing;
      }
      final before = await snapshot();
      await expectLater(
        management.assignCategory(selection, target),
        throwsA(isA<MovementFailure>()),
      );
      expect(await snapshot(), before);
      await expectLater(
        repo.assignPendingCategory(selection, target),
        throwsA(isA<MovementFailure>()),
      );
      expect(await snapshot(), before);
    });
  }

  for (final failure in ['ABORT', 'IGNORE', 'revision']) {
    test('Fallo $failure revierte categorías, timestamps y revisión', () async {
      final page = await repo.readPendingPage(limit: 2);
      final event = failure == 'revision'
          ? 'UPDATE OF revision ON database_state'
          : 'UPDATE OF category_id ON movements';
      final when = failure == 'revision'
          ? ''
          : "WHEN OLD.id='${page.records.last.id}'";
      final raise = failure == 'IGNORE' ? 'IGNORE' : "ABORT,'fallo sintético'";
      await db.customStatement(
        'CREATE TEMP TRIGGER pending_failure BEFORE $event $when BEGIN SELECT RAISE($raise); END',
      );
      final before = await snapshot();
      await expectLater(
        management.assignCategory(page.selectPage(), leaf),
        throwsA(isA<MovementFailure>()),
      );
      expect(await snapshot(), before);
      await expectLater(
        repo.assignPendingCategory(page.selectPage(), leaf),
        throwsA(isA<Exception>()),
      );
      expect(await snapshot(), before);
    });
  }

  test('Otra conexión categoriza/elimina/archiva tras seleccionar: nunca sobrescribe', () async {
    final other = await secondConnection();
    final otherRepo = SqliteMovementRepository(other);
    final page = await repo.readPendingPage(limit: 2);
    await otherRepo.setCategoryBatch([page.records.last.id], child);
    var before = await snapshot();
    await expectLater(
      management.assignCategory(page.selectPage(), leaf),
      throwsA(isA<MovementFailure>()),
    );
    expect(await snapshot(), before);
    final next = await repo.readPendingPage(limit: 2);
    await otherRepo.delete(next.records.last.id);
    before = await snapshot();
    await expectLater(
      management.assignCategory(next.selectPage(), leaf),
      throwsA(isA<MovementFailure>()),
    );
    expect(await snapshot(), before);
    final last = await repo.readPendingPage(limit: 2);
    await SqliteCategoryRepository(other).setArchived(root, archived: true);
    before = await snapshot();
    await expectLater(
      management.assignCategory(last.selectPage(), leaf),
      throwsA(isA<MovementFailure>()),
    );
    expect(await snapshot(), before);
  });

  test('Dos asignaciones simultáneas SQLite: un éxito, una revisión, sin reemplazo', () async {
    final other = await secondConnection();
    final otherManagement = createPendingMovementManagement(database: other);
    final first = (await management.readPage(limit: 2)).selectPage();
    final second = (await otherManagement.readPage(limit: 2)).selectPage();
    expect(first.movements.ids, second.movements.ids);
    final before = await revision();
    Future<bool> assign(
      PendingMovementManagement service,
      PendingMovementSelection selection,
      String category,
    ) async {
      try {
        await service.assignCategory(selection, category);
        return true;
      } on MovementFailure {
        return false;
      }
    }

    final results = await Future.wait([
      assign(management, first, child),
      assign(otherManagement, second, leaf),
    ]);
    expect(results.where((success) => success), hasLength(1));
    expect(await revision(), before + 1);
    final winner = results.first ? child : leaf;
    for (final id in first.movements.ids) {
      expect((await repo.get(id))!.data.categoryId, winner);
    }
    expect((await repo.readPendingPage()).totalCount, 6);
  });

  test('Edición ajena no invalida pendientes válidos y operación general sigue reemplazando', () async {
    final page = await repo.readPendingPage(limit: 2);
    final other = await secondConnection();
    await SqliteMovementRepository(other).setDiscretion(manual, 'Corregido');
    final before = await revision();
    await management.assignCategory(page.selectPage(), child);
    expect(await revision(), before + 1);
    await createMovementManagement(database: db)
        .assignCategory(ids(page), leaf);
    for (final id in ids(page)) {
      expect((await repo.get(id))!.data.categoryId, leaf);
    }
    expect((await repo.get(manual))!.data.discretion, 'Corregido');
  });

  test('Restaurar la misma imagen/revisión invalida UUID capturados por conexión antigua', () async {
    final copy = await store.createConsistentBackup();
    final page = await management.readPage(limit: 2);
    final before = await snapshot();
    await store.exclusivelyForRestore(() async {
      await store.close();
      await File(copy.path).copy(store.databasePath!);
      db = await store.open();
    });
    repo = SqliteMovementRepository(db);
    management = createPendingMovementManagement(database: db);
    expect(await snapshot(), before);
    expect((await repo.readPendingPage()).datasetId, page.datasetId);
    await expectLater(
      management.assignCategory(page.selectPage(), leaf),
      throwsA(isA<MovementFailure>()),
    );
    expect(await snapshot(), before);
    await management.assignCategory(
      (await repo.readPendingPage(limit: 2)).selectPage(),
      leaf,
    );
    expect((await repo.readPendingPage()).totalCount, 6);
  });

  test('Originales y huella EP-012 permanecen intactos al categorizar y repetir archivo', () async {
    final session = fixture.draft(
      [fixture.real(), fixture.real(ordinal: 3), fixture.budget(ordinal: 4)],
      bytes: const [9, 8, 7],
    );
    final batches = SqliteImportBatchRepository(db);
    final review =
        await ValidatingImportPreviewer(SqliteImportPreviewSource(db)).preview(
          session,
          bindings: ImportReferenceBindings(
            accounts: {fixture.accountRef: a1},
            categories: {fixture.rootRef: root},
          ),
        );
    expect(review.canRequestConfirmation, isTrue);
    final result = await batches.confirm(
      ImportConfirmationRequest(
        review: review,
        reviewedOverlapKeys: review.overlaps
            .map((overlap) => overlap.key)
            .toSet(),
      ),
    ) as ImportConfirmed;
    final page = await repo.readPendingPage(
      query: PendingMovementQuery(batchId: result.batch.id),
    );
    expect(page.totalCount, 2);
    final before = await snapshot()
      ..remove('movements')
      ..remove('database_state');
    expect(before['import_row_originals'], isNot(isEmpty));
    expect(before['import_batch_metadata'], isNot(isEmpty));
    final fields = await otherFields();
    await management.assignCategory(page.selectPage(), leaf);
    expect(await otherFields(), fields);
    expect(
      await snapshot()
        ..remove('movements')
        ..remove('database_state'),
      before,
    );
    final assigned = await snapshot();
    expect(
      await batches.confirm(
        ImportConfirmationRequest(
          review: review,
          reviewedOverlapKeys: review.overlaps
              .map((overlap) => overlap.key)
              .toSet(),
        ),
      ),
      isA<ImportAlreadyImported>(),
    );
    expect(await snapshot(), assigned);
    expect(
      (await repo.readPendingPage(
        query: PendingMovementQuery(batchId: result.batch.id),
      )).totalCount,
      0,
    );
  });

  test(
    'Cambio de dataset en la conexión invalida la selección anterior',
    () async {
      final page = await repo.readPendingPage(limit: 2);
      await db.customStatement(
        "UPDATE database_state SET dataset_id='$missing'",
      );
      final before = await snapshot();
      await expectLater(
        management.assignCategory(page.selectPage(), leaf),
        throwsA(isA<MovementFailure>()),
      );
      expect(await snapshot(), before);
    },
  );
}
