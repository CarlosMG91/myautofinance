import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/import_factory.dart';
import 'package:myautofinance/app/pending_movement_factory.dart';
import 'package:myautofinance/features/importing/data/sha256_import_fingerprint.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/movements/presentation/pending_movement_controller.dart';

import '../support/pending_reference_fixture.dart';
import '../support/synthetic_import_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LocalDatabaseStore store;
  late LocalDatabase db;
  late PendingReferenceFixture fixture;
  late CategoryReadInvalidation invalidation;
  late PendingMovementController controller;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pending-138-reference-');
    addTearDown(() => directory.delete(recursive: true));
    store = LocalDatabaseStore(supportDirectory: () async => directory);
    addTearDown(store.close);
    db = await store.open();
    fixture = PendingReferenceFixture();
    await fixture.seed(db);
    invalidation = CategoryReadInvalidation();
    addTearDown(invalidation.close);
    controller = PendingMovementController(
      load: () async => createPendingMovementSource(db, invalidation),
      pageSize: 2,
    );
    addTearDown(controller.dispose);
  });

  test(
    'MA-TSK-137: siete consultas, todas las páginas y selección UUID visible',
    () async {
      final ids = fixture.ids;
      final tied = ['r02', 'r03']..sort((a, b) => ids[a]!.compareTo(ids[b]!));
      final cases = [
        (PendingMovementQuery(), ['r01', ...tied, 'r04', 'r05']),
        (PendingMovementQuery(batchId: ids['l1']), ['r01', ...tied]),
        (PendingMovementQuery(accountId: ids['a1']), ['r01', 'r02', 'r05']),
        (
          PendingMovementQuery(
            from: ValueDate(2026, 6, 29),
            until: ValueDate(2026, 7, 1),
          ),
          ['r01', ...tied],
        ),
        (PendingMovementQuery(concept: 'cafe'), ['r01', ...tied]),
        (
          PendingMovementQuery(batchId: ids['l2'], accountId: ids['a2']),
          ['r04'],
        ),
        (PendingMovementQuery(concept: 'imposible'), <String>[]),
      ];
      final before = await fixture.image(db);
      for (final (query, expected) in cases) {
        await controller.apply(query);
        final seen = <String>[];
        while (true) {
          final page = controller.page!;
          expect(page.totalCount, expected.length);
          final visible = page.records.map((r) => r.id).toSet();
          seen.addAll(visible.map(fixture.key));
          controller.selectPage();
          expect(controller.selected, visible);
          controller.toggle(ids['r07']!, true);
          expect(controller.selected, visible);
          for (final key in expected.where(
            (key) => !visible.contains(ids[key]),
          )) {
            controller.toggle(ids[key]!, true);
          }
          expect(controller.selected, visible);
          if (page.nextCursor == null) break;
          await controller.next();
          expect(controller.selected, isEmpty);
        }
        expect(seen, expected);
        expect(seen.toSet().length, seen.length);
        if (controller.pageIndex > 0) {
          await controller.previous();
          expect(controller.selected, isEmpty);
          expect(controller.page!.totalCount, expected.length);
        }
      }
      expect(await fixture.image(db), before);
    },
  );

  for (final conflict in ['category', 'deleted', 'archived', 'write failure']) {
    test('Archivo SQLite: $conflict rechaza todo y mantiene contexto', () async {
      final query = PendingMovementQuery(
        batchId: fixture.ids['l1'],
        concept: 'cafe',
      );
      await controller.apply(query);
      controller.selectPage();
      final selection = controller.selected.toList();
      final request = controller.beginAssignment()!;
      final other = LocalDatabase(
        NativeDatabase(File(store.databasePath!), setup: configureConnection),
      );
      try {
        await other.readState();
        switch (conflict) {
          case 'category':
            await SqliteMovementRepository(
              other,
            ).setCategoryBatch([selection.last], fixture.ids['c-transporte']);
          case 'deleted':
            await SqliteMovementRepository(other).delete(selection.last);
          case 'archived':
            await SqliteCategoryRepository(other)
                .setArchived(fixture.ids['c-alimentacion']!, archived: true);
          case 'write failure':
            await db.customStatement(
              "CREATE TEMP TRIGGER pending_138_failure BEFORE UPDATE OF category_id ON movements WHEN OLD.id='${selection.last}' BEGIN SELECT RAISE(ABORT,'sintético'); END",
            );
        }
        final before = await fixture.image(db);
        expect(
          await controller.assign(request, fixture.ids['c-alimentacion']!),
          isFalse,
        );
        expect(await fixture.image(db), before);
        expect(controller.query, same(query));
        expect(controller.selected, selection.toSet());
        expect(controller.error, isNotNull);
        expect(controller.notice, isNull);
        expect(controller.requiresRefresh, conflict != 'write failure');
        if (conflict == 'write failure') {
          await db.customStatement('DROP TRIGGER pending_138_failure');
          final retry = controller.beginAssignment()!;
          expect(
            await controller.assign(retry, fixture.ids['c-alimentacion']!),
            isTrue,
          );
          expect(controller.selected, isEmpty);
          expect(controller.page!.totalCount, 1);
          expect(
            fixture.preserved(await fixture.image(db), allowed: selection),
            fixture.preserved(before, allowed: selection),
          );
        } else {
          expect(controller.beginAssignment(), isNull);
          await controller.update();
          expect(controller.selected, isEmpty);
          expect(controller.query, same(query));
        }
      } finally {
        await other.close();
      }
    });
  }

  test(
    'Dos filas idénticas conservan identidad y categorización independientes',
    () async {
      final file = ImportFile.fromBytes(
        bytes: utf8.encode(
          jsonEncode({
            'rows': [
              for (final ordinal in [2, 3])
                {
                  'kind': 'REAL',
                  'ordinal': ordinal,
                  'account': 'a1',
                  'date': '2026-07-01',
                  'concept': 'Duplicado legítimo',
                  'cents': -1234,
                  'discretion': 'Conservar',
                  'fields': [
                    {'name': 'original', 'value': 'idéntico'},
                  ],
                },
            ],
          }),
        ),
        fingerprint: const Sha256ImportFingerprint(),
        source: ImportSource.historicalCsv,
        originalName: 'duplicados-138-sinteticos.json',
      );
      final services = createImportServices(db);
      final review = await services.previewer.preview(
        ImportSession(
          file: file,
          interpretation: await const SyntheticImportAdapter(
            ImportSource.historicalCsv,
          ).interpret(file),
        ),
        bindings: ImportReferenceBindings(
          accounts: {ImportAccountReference.named('a1'): fixture.ids['a1']!},
        ),
      );
      final imported = await services.confirmer.confirm(
        ImportConfirmationRequest(review: review),
      );
      expect(imported, isA<ImportConfirmed>());
      final batch = (imported as ImportConfirmed).batch;
      final query = PendingMovementQuery(batchId: batch.id);
      await controller.apply(query);
      final first = controller.page!.records.first.id;
      final second = controller.page!.records.last.id;
      expect(first, isNot(second));
      expect(controller.page!.totalCount, 2);
      final original = await fixture.image(db);
      final revision = (await db.readState()).revision;
      expect(
        await controller.assign(
          controller.beginAssignment(id: first)!,
          fixture.ids['c-hogar']!,
        ),
        isTrue,
      );
      expect(controller.page!.records.single.id, second);
      expect(controller.page!.totalCount, 1);
      expect(controller.selected, isEmpty);
      expect(controller.query, same(query));
      expect((await db.readState()).revision, revision + 1);
      expect(
        fixture.preserved(await fixture.image(db), allowed: [first]),
        fixture.preserved(original, allowed: [first]),
      );
      final assigned = await fixture.image(db);
      expect(
        await services.confirmer.confirm(
          ImportConfirmationRequest(review: review),
        ),
        isA<ImportAlreadyImported>(),
      );
      expect(await fixture.image(db), assigned);
      final originals = (await services.history.listRows(batch.id)).items;
      expect(originals.map((row) => row.sourceOrdinal), [2, 3]);
      expect(originals.map((row) => row.currentMovement!.id).toSet(), {
        first,
        second,
      });
    },
  );

  test(
    'Restaurar misma imagen invalida selección y exige nuevos UUID visibles',
    () async {
      await controller.apply(PendingMovementQuery(batchId: fixture.ids['l1']));
      controller.selectPage();
      final request = controller.beginAssignment()!;
      final before = await fixture.image(db);
      final copy = await store.createConsistentBackup();
      await store.exclusivelyForRestore(() async {
        await store.close();
        await File(copy.path).copy(store.databasePath!);
        db = await store.open();
      });
      expect(
        await controller.assign(request, fixture.ids['c-hogar']!),
        isFalse,
      );
      expect(await fixture.image(db), before);
      expect(controller.requiresRefresh, isTrue);
      await controller.update();
      expect(controller.selected, isEmpty);
      expect(controller.pageIndex, 0);
      expect(controller.page!.totalCount, 3);
      expect(controller.beginAssignment(), isNull);
      controller.selectPage();
      expect(
        await controller.assign(
          controller.beginAssignment()!,
          fixture.ids['c-hogar']!,
        ),
        isTrue,
      );
      expect(controller.page!.totalCount, 1);
      expect(
        fixture.preserved(
          await fixture.image(db),
          allowed: request.movements.ids,
        ),
        fixture.preserved(before, allowed: request.movements.ids),
      );
    },
  );
}
