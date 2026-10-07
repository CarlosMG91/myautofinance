import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/import_factory.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/importing/presentation/import_controller.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

import '../support/import_ui_fixture.dart';
import 'import_preview_test.dart' as fixture;

class DelayedConfirmer implements ImportConfirmer {
  DelayedConfirmer(this.inner);
  final ImportConfirmer inner;
  final gate = Completer<void>();
  int calls = 0;
  @override
  Future<ImportConfirmationResult> confirm(
    ImportConfirmationRequest request,
  ) async {
    calls++;
    await gate.future;
    return inner.confirm(request);
  }
}

class DelayedAdapter extends SyntheticUiAdapter {
  DelayedAdapter(super.rows);
  final gate = Completer<void>();
  bool fail = false;
  @override
  Future<ImportInterpretation> interpret(ImportFile file) async {
    await gate.future;
    if (fail) throw StateError('Error de lectura sintético');
    return super.interpret(file);
  }
}

void main() {
  late LocalDatabase db;
  late ImportServices services;
  late ImportController c;
  late String accountId, categoryId;
  setUp(() async {
    db = LocalDatabase(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys=ON'),
      ),
    );
    accountId = (await SqliteAccountRepository(db).create(
      name: 'Cuenta',
      kind: AccountKind.account,
      activeFrom: Month(2026, 1),
      liquidity: Liquidity.liquid,
    )).id;
    categoryId = (await SqliteCategoryRepository(
      db,
    ).create(name: 'Gastos', isIncome: false)).id;
    services = createImportServices(db);
    c = ImportController(() async => services);
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  test(
    'Cancelar lectura pendiente descarta su resultado sin escribir',
    () async {
      final adapter = DelayedAdapter([fixture.real()]);
      final operation = c.start(fixture.draft(adapter.rows).file, adapter);
      expect(c.phase, ImportPhase.reading);
      c.discard();
      adapter.gate.complete();
      await operation;
      expect(c.phase, ImportPhase.idle);
      expect(c.session, isNull);
      expect((await services.history.listBatches()).items, isEmpty);
    },
  );
  test('Error leyendo conserva entrada para reintentar', () async {
    final adapter = DelayedAdapter([fixture.real()])..fail = true;
    adapter.gate.complete();
    await c.start(fixture.draft(adapter.rows).file, adapter);
    expect(c.phase, ImportPhase.error);
    expect(c.hasSession, isTrue);
    adapter.fail = false;
    await c.retryRead();
    expect(c.canConfirm, isTrue);
  });
  test(
    'Invalida consumidores después del commit, nunca al revisar o repetir',
    () async {
      var notifications = 0;
      services = createImportServices(db, onConfirmed: () => notifications++);
      await c.start(
        fixture.draft([fixture.real()]).file,
        SyntheticUiAdapter([fixture.real()]),
      );
      expect(notifications, 0);
      await c.confirm();
      expect(notifications, 1);
      c.discard();
      await c.start(
        fixture.draft([fixture.real()]).file,
        SyntheticUiAdapter([fixture.real()]),
      );
      await c.confirm();
      expect(notifications, 1);
    },
  );
  Future<void> start(
    List<InterpretedImportRow> rows, {
    List<int> bytes = const [1],
    List<ImportIssue> issues = const [],
  }) => c.start(
    fixture.draft(rows, bytes: bytes).file,
    SyntheticUiAdapter(rows, issues: issues),
  );

  test(
    'Estados, revisión sin escritura, confirmación SQLite e historial',
    () async {
      final phases = <ImportPhase>[];
      c.addListener(() => phases.add(c.phase));
      final before = (await db.readState()).revision;
      await start([
        fixture.real(),
        fixture.real(ordinal: 3),
        fixture.budget(ordinal: 4),
        fixture.budget(ordinal: 5, month: 2, amount: 0),
      ]);
      expect(c.phase, ImportPhase.review);
      expect(c.canConfirm, isTrue);
      expect((await db.readState()).revision, before);
      await c.confirm();
      expect(c.phase, ImportPhase.imported);
      expect(
        phases,
        containsAllInOrder([
          ImportPhase.reading,
          ImportPhase.review,
          ImportPhase.confirming,
          ImportPhase.imported,
        ]),
      );
      expect((await db.readState()).revision, before + 1);
      final batch = (c.result as ImportConfirmed).batch;
      final rows = (await services.history.listRows(batch.id)).items;
      expect(rows.map((r) => r.sourceOrdinal), [2, 3, 4, 5]);
      expect(rows[0].currentMovement!.id, isNot(rows[1].currentMovement!.id));
      expect(rows[2].currentBudget!.data.amountCents, -1000);
      expect(rows[3].currentBudget!.data.amountCents, 0);
    },
  );
  test(
    'Cuenta global pendiente, alta preparada y cancelar no escriben',
    () async {
      final before = (await db.readState()).revision;
      const ref = ImportAccountReference.selectedAccount();
      await start([fixture.real(account: ref)]);
      expect(c.canConfirm, isFalse);
      await c.bindAccount(
        ref,
        plan: ImportNewAccount(
          name: 'Nueva',
          activeFrom: Month(2026, 1),
          liquidity: Liquidity.liquid,
        ),
      );
      expect(c.canConfirm, isTrue);
      expect((await SqliteAccountRepository(db).list()).length, 1);
      expect(c.discard(), isTrue);
      expect((await db.readState()).revision, before);
      expect((await services.history.listBatches()).items, isEmpty);
    },
  );
  test('Error de fila y lote vacío impiden confirmar todo', () async {
    await start(
      [fixture.real()],
      issues: const [
        ImportIssue(
          code: ImportIssueCode.invalidField,
          sourceOrdinal: 3,
          field: 'fecha',
          reason: 'Fecha imposible',
        ),
      ],
    );
    expect(c.phase, ImportPhase.error);
    await c.confirm();
    expect((await services.history.listBatches()).items, isEmpty);
    c.discard();
    await start([]);
    expect(c.canConfirm, isFalse);
    expect(c.review!.issues.single.code, ImportIssueCode.emptyBatch);
  });
  test('Solapamiento explícito por ordinal; cambiar asignación invalida revisiones', () async {
    await start([fixture.real()]);
    await c.confirm();
    c.discard();
    await start([fixture.real(), fixture.real(ordinal: 3)], bytes: [2]);
    expect(c.review!.overlaps.length, 2);
    expect(c.canConfirm, isFalse);
    for (final overlap in c.review!.overlaps) {
      c.markOverlap(overlap.key, true);
    }
    expect(c.canConfirm, isTrue);
    await c.bindAccount(fixture.accountRef, id: accountId);
    expect(c.reviewedOverlaps, isEmpty);
    expect(c.canConfirm, isFalse);
    for (final overlap in c.review!.overlaps) {
      c.markOverlap(overlap.key, true);
    }
    await c.confirm();
    expect(c.phase, ImportPhase.imported);
  });
  test(
    'Rechazo por base cambiada conserva sesión y reintento seguro',
    () async {
      await start([fixture.real(category: fixture.rootRef)]);
      await db.blockWritesForRestore();
      await c.confirm();
      expect(c.phase, ImportPhase.error);
      expect(c.session, isNotNull);
      expect(c.failures, isNotEmpty);
      expect(c.reviewedOverlaps, isEmpty);
      expect((await services.history.listBatches()).items, isEmpty);
      db.resumeWritesAfterRestore();
      await c.confirm();
      expect(c.phase, ImportPhase.imported);
    },
  );
  test('Catálogo borrado después de revisar invalida lote entero', () async {
    await start([fixture.real()]);
    await db.customStatement('DELETE FROM account_liquidity_periods');
    await db.customStatement('DELETE FROM accounts');
    await c.confirm();
    expect(c.phase, ImportPhase.error);
    expect(c.canConfirm, isFalse);
    expect(c.session, isNotNull);
    expect((await services.history.listBatches()).items, isEmpty);
  });
  test('Dos confirmaciones y descartar durante transacción no duplican ni cancelan', () async {
    final delayed = DelayedConfirmer(services.confirmer);
    services = ImportServices(
      source: services.source,
      previewer: services.previewer,
      confirmer: delayed,
      history: services.history,
    );
    await start([fixture.real()]);
    final pending = c.confirm();
    await Future<void>.delayed(Duration.zero);
    await c.confirm();
    expect(c.discard(), isFalse);
    expect(delayed.calls, 1);
    await c.bindAccount(fixture.accountRef, id: 'otro');
    delayed.gate.complete();
    await pending;
    expect(c.phase, ImportPhase.imported);
    expect((await services.history.listBatches()).items.length, 1);
  });
  test(
    'Repetición renombrada conserva originales tras borrar el destino',
    () async {
      await start([fixture.real()]);
      await c.confirm();
      final id = (c.result as ImportConfirmed).batch.id;
      await db.customStatement('DELETE FROM movements');
      c.discard();
      await c.start(
        fixture.draft([fixture.real()], name: 'renombrado.csv').file,
        SyntheticUiAdapter([fixture.real()]),
      );
      await c.confirm();
      expect(c.phase, ImportPhase.alreadyImported);
      expect((c.result as ImportAlreadyImported).batch.id, id);
      expect(
        (await services.history.listRows(id)).items.single.isDeleted,
        isTrue,
      );
    },
  );
  test(
    'Categoría nueva exige marca explícita y solo nace al confirmar',
    () async {
      final ref = ImportCategoryReference(['Nueva']);
      await start([fixture.budget(category: ref)]);
      await c.bindCategory(ref, plan: const ImportNewCategory(name: 'Nueva'));
      expect(c.canConfirm, isFalse);
      await c.bindCategory(
        ref,
        plan: const ImportNewCategory(name: 'Nueva', isIncome: false),
      );
      expect((await SqliteCategoryRepository(db).list()).length, 1);
      await c.confirm();
      expect((await SqliteCategoryRepository(db).list()).length, 2);
      expect(categoryId, isNotEmpty);
    },
  );
  test('Fallo de lectura no permite confirmar una revisión anterior', () async {
    await start([fixture.real()]);
    final valid = services;
    c.dispose();
    var fail = false;
    c = ImportController(() async {
      if (fail) throw StateError('Disco');
      return valid;
    });
    await start([fixture.real()]);
    fail = true;
    await c.refresh();
    expect(c.canConfirm, isFalse);
    expect(c.session, isNotNull);
    fail = false;
    await c.refresh();
    expect(c.canConfirm, isTrue);
  });
}
