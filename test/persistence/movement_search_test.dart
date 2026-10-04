import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/concept_search_key.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LocalDatabaseStore store;
  late SqliteMovementRepository repo;
  late SqliteCategoryRepository categories;
  late String a1, a2, c, c1, c11, d;
  late List<MovementRecord> fixture;
  final march = ValueDate(2026, 3, 1);
  final april = ValueDate(2026, 4, 1);

  MovementInput input(
    String account,
    int day,
    String concept,
    int cents,
    String? category, {
    int month = 3,
    String? discretion,
  }) => MovementInput(
    accountId: account,
    valueDate: ValueDate(2026, month, day),
    concept: concept,
    amountCents: cents,
    categoryId: category,
    discretion: discretion,
  );

  Future<MovementPage> page({
    String? account,
    String? category,
    MovementCategoryScope scope = MovementCategoryScope.direct,
    bool unclassified = false,
    String? concept,
    MovementCursor? after,
    int limit = 100,
  }) => repo.readPage(
    from: march,
    until: april,
    accountId: account,
    categoryId: category,
    categoryScope: scope,
    unclassifiedOnly: unclassified,
    concept: concept,
    after: after,
    limit: limit,
  );

  List<String> ids(MovementPage result) =>
      result.records.map((record) => record.id).toList();

  List<String> ordered(Iterable<MovementRecord> records) {
    final sorted = records.toList()
      ..sort((a, b) {
        final byDate = b.data.valueDate.compareTo(a.data.valueDate);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
    return sorted.map((record) => record.id).toList();
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'movement-search-synthetic-',
    );
    store = LocalDatabaseStore(supportDirectory: () async => directory);
    final db = await store.open();
    repo = SqliteMovementRepository(db);
    final accounts = SqliteAccountRepository(db);
    Future<String> account() async => (await accounts.create(
      name: 'Cuenta duplicada',
      kind: AccountKind.account,
      activeFrom: Month(2026, 1),
      liquidity: Liquidity.liquid,
    )).id;
    a1 = await account();
    a2 = await account();
    categories = SqliteCategoryRepository(db);
    c = (await categories.create(name: 'Ocio')).id;
    c1 = (await categories.create(name: 'Café', parentId: c)).id;
    c11 = (await categories.create(name: 'Detalle', parentId: c1)).id;
    d = (await categories.create(name: 'Café')).id;
    final m1 = await repo.create(input(a1, 31, 'Café', 1250, c));
    await SqliteImportBatchRepository(db).create(
      sha256: '8' * 64,
      source: ImportSource.historicalCsv,
      originalName: 'sintetico.csv',
      contractVersion: '1',
      movements: [
        ImportedMovement(
          2,
          input(a1, 31, 'café', 1250, c1, discretion: 'regalo'),
        ),
        ImportedMovement(3, input(a2, 30, 'Café', -450, c11)),
      ],
    );
    final imported = await repo.readMonth(2026, 3);
    final m2 = imported.singleWhere((m) => m.sourceOrdinal == 2);
    final m3 = imported.singleWhere((m) => m.sourceOrdinal == 3);
    final m4 = await repo.create(input(a1, 1, 'Árbol', -300, d));
    final m5 = await repo.create(
      input(a2, 1, 'CAFE', -200, null, month: 4, discretion: 'capricho'),
    );
    fixture = [m1, m2, m3, m4, m5];
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('casos EP-010: filtros combinados, signos, rama y directos sin doble conteo', () async {
    Future<void> check(
      MovementPage result,
      List<int> indexes,
      int cents,
    ) async {
      expect(ids(result), ordered(indexes.map((i) => fixture[i])));
      expect(result.subtotalCents, cents);
      expect(result.nextCursor, isNull);
    }

    final before = await repo.database.readState();
    await check(await page(), [0, 1, 2, 3], 1750);
    await check(await page(account: a1), [0, 1, 3], 2200);
    await check(await page(category: c), [0], 1250);
    await check(await page(category: c1), [1], 1250);
    await check(await page(category: c11), [2], -450);
    await check(await page(category: c, scope: MovementCategoryScope.branch), [
      0,
      1,
      2,
    ], 2050);
    await check(await page(category: c1, scope: MovementCategoryScope.branch), [
      1,
      2,
    ], 800);
    await check(await page(unclassified: true), [], 0);
    await check(
      await page(
        account: a1,
        category: c,
        scope: MovementCategoryScope.branch,
        concept: 'CAFE',
      ),
      [0, 1],
      2500,
    );
    await check(await page(concept: 'arbol'), [3], -300);
    await check(await page(concept: 'regalo'), [], 0);
    await check(await page(concept: 'Cuenta duplicada'), [], 0);
    await check(await page(concept: 'Detalle'), [], 0);
    await check(await page(concept: ' \t '), [0, 1, 2, 3], 1750);
    final unclassified = await repo.readPage(
      from: april,
      until: ValueDate(2026, 5, 1),
      accountId: a2,
      unclassifiedOnly: true,
      concept: 'café',
    );
    expect(ids(unclassified), [fixture[4].id]);
    expect(unclassified.subtotalCents, -200);
    expect((await repo.database.readState()).revision, before.revision);
  });

  test(
    'literal SQL, acentos compuestos/descompuestos y case-fold Unicode',
    () async {
      final literal = await repo.create(
        input(a1, 20, "CAFÉ  100%_\\ ' OR 1=1 --", -101, null),
      );
      final decomposed = await repo.create(
        input(a1, 20, 'Cafe\u0301 Straße ΟΣ', -102, null),
      );
      for (final query in ['%', '_', '\\', "' OR 1=1 --", '100%_']) {
        expect(ids(await page(concept: query)), [literal.id]);
      }
      expect(ids(await page(concept: "%') OR 1=1 --")), isEmpty);
      expect(ids(await page(concept: '  STRASSE  ')), [decomposed.id]);
      expect(ids(await page(concept: 'ος')), [decomposed.id]);
      expect(ids(await page(concept: 'cafe')).toSet(), {
        ...fixture.take(3).map((m) => m.id),
        literal.id,
        decomposed.id,
      });
      expect(ids(await page(concept: 'café  100')), [literal.id]);
      expect(ids(await page(concept: 'café 100')), isEmpty);
      expect(conceptSearchKey('ÁRBOL'), 'arbol');
      expect(conceptSearchKey('가'), conceptSearchKey('\u1100\u1161'));
      expect(conceptSearchKey('Ａ'), isNot(conceptSearchKey('A')));
    },
  );

  test('cursor exclusivo: empates por UUID, transición de fechas y subtotal global', () async {
    // Duplicado visible legítimo, con UUID propio.
    final duplicate = await repo.create(input(a1, 31, 'Café', 1250, c));
    final expected = ordered([...fixture.take(4), duplicate]);
    for (final limit in [1, 2, 3, 5]) {
      MovementCursor? cursor;
      final visited = <String>[];
      do {
        final result = await page(after: cursor, limit: limit);
        expect(result.subtotalCents, 3000);
        expect(result.records.length, lessThanOrEqualTo(limit));
        visited.addAll(ids(result));
        cursor = result.nextCursor;
        if (cursor != null) {
          expect(cursor.id, result.records.last.id);
        }
      } while (cursor != null);
      expect(visited, expected);
      expect(visited.toSet().length, visited.length);
    }
    final exhausted = await page(
      after: MovementCursor(fixture[3].data.valueDate, fixture[3].id),
    );
    expect(exhausted.records, isEmpty);
    expect(exhausted.subtotalCents, 3000);
    expect(exhausted.nextCursor, isNull);
    final list = await repo.list(
      from: march,
      until: april,
      concept: 'CAFE',
      categoryId: c,
      categoryScope: MovementCategoryScope.branch,
      limit: 1,
    );
    expect(list.single.id, ordered([...fixture.take(3), duplicate]).first);
    final next = await repo.list(
      from: march,
      until: april,
      concept: 'CAFE',
      categoryId: c,
      categoryScope: MovementCategoryScope.branch,
      after: MovementCursor(list.single.data.valueDate, list.single.id),
    );
    expect(
      next.map((m) => m.id),
      ordered([...fixture.take(3), duplicate]).skip(1),
    );
  });

  test('histórico reubicado, nombres duplicados y referencias archivadas conservan identidad/procedencia', () async {
    final before = fixture[1];
    await categories.edit(c1, name: 'Café', parentId: d, isIncome: null);
    await categories.setArchived(c1, archived: true);
    await SqliteAccountRepository(repo.database).close(a1, Month(2026, 3));
    expect(ids(await page(category: c, scope: MovementCategoryScope.branch)), [
      fixture[0].id,
    ]);
    final moved = await page(
      category: d,
      scope: MovementCategoryScope.branch,
      concept: 'CAFE',
    );
    expect(ids(moved), ordered(fixture.skip(1).take(2)));
    expect(moved.subtotalCents, 800);
    expect(ids(await page(category: c1)), [before.id]);
    final actual = moved.records.singleWhere((m) => m.id == before.id);
    expect(actual.importRowId, before.importRowId);
    expect(actual.batchId, before.batchId);
    expect(actual.sourceOrdinal, before.sourceOrdinal);
    expect(actual.data.discretion, 'regalo');
    expect(actual.data.categoryId, c1);
    expect((await repo.readMonth(2026, 3, categoryId: c)).map((m) => m.id), [
      fixture[0].id,
    ]);
    expect(
      (await repo.readYear(2026, categoryId: d)).map((m) => m.id).toSet(),
      fixture.skip(1).take(3).map((m) => m.id).toSet(),
    );
    await store.close();
    repo = SqliteMovementRepository(await store.open());
    expect(ids(await page(category: c1, concept: 'café')), [before.id]);
  });

  test('rechaza filtros ambiguos, periodos y límites inválidos', () async {
    for (final scope in MovementCategoryScope.values) {
      await expectLater(
        page(category: c, scope: scope, unclassified: true),
        throwsA(isA<MovementFailure>()),
      );
    }
    await expectLater(
      repo.list(
        from: march,
        until: april,
        categoryId: c,
        unclassifiedOnly: true,
      ),
      throwsA(isA<MovementFailure>()),
    );
    for (final limit in [0, -1, 501]) {
      await expectLater(page(limit: limit), throwsA(isA<MovementFailure>()));
      await expectLater(
        repo.list(from: march, until: april, limit: limit),
        throwsA(isA<MovementFailure>()),
      );
    }
    for (final until in [march, ValueDate(2026, 2, 1), null]) {
      await expectLater(
        repo.readPage(from: march, until: until),
        throwsA(isA<MovementFailure>()),
      );
    }
    expect(
      (await repo.readPage(
        from: ValueDate(9999, 12, 1),
        until: null,
      )).subtotalCents,
      0,
    );
    expect((await page(category: 'inexistente')).records, isEmpty);
    expect((await page(account: "' OR 1=1 --")).records, isEmpty);
  });

  test(
    'subtotal INTEGER exacto y overflow explícito en ambos signos',
    () async {
      for (final amounts in [
        [9223372036854775807, 1],
        [-9223372036854775808, -1],
      ]) {
        final records = <MovementRecord>[];
        for (final amount in amounts) {
          records.add(
            await repo.create(input(a1, 20, 'Overflow', amount, null)),
          );
        }
        await expectLater(
          page(concept: 'Overflow', limit: 1),
          throwsA(isA<MovementFailure>()),
        );
        for (final record in records) {
          await repo.delete(record.id);
        }
      }
      await repo.create(input(a1, 20, 'Exacto', 9007199254740993, null));
      await repo.create(input(a1, 20, 'Exacto', -9007199254740992, null));
      expect((await page(concept: 'Exacto', limit: 1)).subtotalCents, 1);
      // Comprueba una compensación después de exceder int64 provisionalmente.
      await repo.create(
        input(a1, 20, 'Compensación', 9223372036854775807, null),
      );
      await repo.create(input(a1, 20, 'Compensación', 1, null));
      await repo.create(input(a1, 20, 'Compensación', -1, null));
      expect(
        (await page(concept: 'Compensación')).subtotalCents,
        9223372036854775807,
      );
    },
  );

  test('mismas funciones en conexión SQLite directa y en isolate', () async {
    final direct = LocalDatabase(
      NativeDatabase.memory(setup: configureConnection),
    );
    try {
      final account = await SqliteAccountRepository(direct).create(
        name: 'Sintética directa',
        kind: AccountKind.account,
        activeFrom: Month(2026, 1),
        liquidity: Liquidity.liquid,
      );
      final movements = SqliteMovementRepository(direct);
      final record = await movements.create(
        input(account.id, 15, 'CAFÉ', -25, null),
      );
      final result = await movements.readPage(
        from: march,
        until: april,
        concept: 'cafe',
      );
      expect(ids(result), [record.id]);
      expect(result.subtotalCents, -25);
      await movements.create(
        input(account.id, 15, 'Límite', 9223372036854775807, null),
      );
      await movements.create(input(account.id, 15, 'Límite', 1, null));
      await expectLater(
        movements.readPage(from: march, until: april, concept: 'limite'),
        throwsA(isA<MovementFailure>()),
      );
    } finally {
      await direct.close();
    }
  });

  test(
    'página por defecto 100, máximo 500 y lecturas de informes completas',
    () async {
      await repo.database.writeTransaction(() async {
        for (var i = 0; i < 520; i++) {
          await repo.database.customStatement(
            'INSERT INTO movements(id,account_id,value_date,concept,amount_cents,category_id,created_at,updated_at) '
            'VALUES(?,?,?,?,?,?,?,?)',
            [
              '00000000-0000-0000-0000-${i.toString().padLeft(12, '0')}',
              a1,
              '2026-03-15',
              'Volumen sintético',
              -1,
              c11,
              'sintetico',
              'sintetico',
            ],
          );
        }
      });
      final first = await page(concept: 'volumen');
      expect(first.records.length, 100);
      expect(first.subtotalCents, -520);
      final large = await page(concept: 'volumen', limit: 500);
      final rest = await page(
        concept: 'volumen',
        after: large.nextCursor,
        limit: 500,
      );
      expect(large.records.length, 500);
      expect(rest.records.length, 20);
      expect(rest.subtotalCents, -520);
      expect(rest.nextCursor, isNull);
      expect({...ids(large), ...ids(rest)}.length, 520);
      expect((await repo.readMonth(2026, 3, categoryId: c)).length, 523);
      expect((await repo.readYear(2026, categoryId: c)).length, 523);
      final plan = await repo.database
          .customSelect(
            "EXPLAIN QUERY PLAN SELECT id FROM movements WHERE account_id='synthetic' "
            "AND value_date>='2026-03-01' AND value_date<'2026-04-01' "
            'ORDER BY value_date DESC,id ASC LIMIT 100',
          )
          .get();
      expect(
        plan.map((row) => row.data.toString()).join(),
        contains('movements_account_date'),
      );
    },
  );
}
