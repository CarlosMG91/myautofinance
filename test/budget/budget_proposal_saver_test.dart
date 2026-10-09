import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/budget_proposal_factory.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/data/historical_csv_reader.dart';
import 'package:myautofinance/features/importing/historical_csv.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  final multipleDatabaseWarning =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  setUpAll(() {
    // Cada conexión de estas pruebas tiene su propio executor SQLite.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        multipleDatabaseWarning;
  });
  late Directory directory;
  late File file;
  late LocalDatabase db;
  late CategoryReadInvalidation invalidation;
  late CategoryManagement categories;
  late SqliteBudgetRepository budgets;
  late SqliteMovementRepository movements;
  late BudgetProposalCalculator calculator;
  late BudgetProposalSaver saver;
  late String root, child, leaf, sibling, other, account;
  final jan = BudgetMonth(2027, 1), feb = BudgetMonth(2027, 2);

  LocalDatabase open() => LocalDatabase(
    NativeDatabase(
      file,
      setup: (sqlite) => sqlite.execute('PRAGMA foreign_keys=ON'),
    ),
  );

  void compose() {
    categories = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    budgets = SqliteBudgetRepository(db);
    movements = SqliteMovementRepository(db);
    calculator = createBudgetProposalCalculator(
      database: db,
      invalidation: invalidation,
    );
    saver = createBudgetProposalSaver(database: db, invalidation: invalidation);
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'proposal-save-synthetic-',
    );
    file = File('${directory.path}/test.sqlite');
    db = open();
    invalidation = CategoryReadInvalidation();
    compose();
    root = (await categories.create(name: 'Alimentación')).node.id;
    child = (await categories.create(
      name: 'Supermercado',
      parentId: root,
    )).node.id;
    leaf = (await categories.create(
      name: 'Compra semanal',
      parentId: child,
    )).node.id;
    sibling = (await categories.create(
      name: 'Supermercado',
      parentId: root,
    )).node.id;
    other = (await categories.create(name: 'Ingresos', isIncome: true)).node.id;
    account = (await SqliteAccountRepository(db).create(
      name: 'Cuenta sintética',
      kind: AccountKind.account,
      activeFrom: Month(2025, 1),
      liquidity: Liquidity.liquid,
    )).id;
  });
  tearDown(() async {
    await invalidation.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<BudgetRecord> item(
    String id, {
    BudgetMonth? month,
    int amount = -100,
  }) => budgets.create(
    BudgetInput(month: month ?? jan, categoryId: id, amountCents: amount),
  );
  Future<MovementRecord> real(String? id, int cents, {int year = 2026}) =>
      movements.create(
        MovementInput(
          accountId: account,
          valueDate: ValueDate(year, 1, 15),
          concept: 'Real sintético',
          categoryId: id,
          amountCents: cents,
        ),
      );
  BudgetProposalDraft copy(
    BudgetProposalDraft d, {
    Iterable<BudgetInput>? allocations,
    Iterable<BudgetProposalScope>? scopes,
    bool? signsReviewed,
    Iterable<BudgetProposalRow>? sourceRows,
  }) => BudgetProposalDraft(
    sourceYear: d.sourceYear,
    targetYear: d.targetYear,
    sourceRows: sourceRows ?? d.sourceRows,
    allocations: allocations ?? d.allocations,
    includedScopes: scopes ?? d.includedScopes,
    excludedReals: d.excludedReals,
    basis: d.basis,
    signsReviewed: signsReviewed ?? d.signsReviewed,
  );
  BudgetProposalDraft select(
    BudgetProposalDraft d, {
    List<BudgetMonth>? months,
  }) {
    final selected = (months ?? [jan]).map((m) => m.value).toSet();
    return copy(
      d,
      allocations: d.allocations.where(
        (a) => a.categoryId == root && selected.contains(a.month.value),
      ),
      scopes: d.includedScopes.where(
        (s) => s.rootId == root && selected.contains(s.month.value),
      ),
    );
  }

  Future<Map<String, Object?>> snapshot() async {
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
        )
        .get();
    return {
      for (final table in tables)
        table.read<String>(
          'name',
        ): (await db
                .customSelect(
                  'SELECT * FROM "${table.read<String>('name')}" ORDER BY rowid',
                )
                .get())
            .map((r) => Map<String, Object?>.from(r.data))
            .toList(),
    };
  }

  Matcher failure(BudgetProposalSaveFailureCode code) =>
      isA<BudgetProposalSaveFailure>().having((e) => e.code, 'code', code);
  Future<BudgetProposalSaveResult> save(BudgetProposalReview review) =>
      saver.save(review, confirmation: review.requiredConfirmation);

  test(
    'Caso H: guarda año nuevo, signos normalizados, ceros y acuse único',
    () async {
      final csv = const HistoricalCsvReader().read(
        File('docs/ep-001/historico-ejemplo.csv').readAsBytesSync(),
      );
      expect(csv.isValid, isTrue);
      final nodes = {for (final c in await categories.list()) c.path: c};
      for (final row in csv.records) {
        String? parent;
        for (var i = 0; i < row.categoryPath.length; i++) {
          final path = row.categoryPath.take(i + 1).join(' / ');
          parent = (nodes[path] ??= await categories.create(
            name: row.categoryPath[i],
            parentId: parent,
            isIncome: parent == null
                ? row.categoryPath.first == 'Ingresos'
                : null,
          )).node.id;
        }
        if (row.type == HistoricalCsvType.real) {
          await movements.create(
            MovementInput(
              accountId: account,
              valueDate: ValueDate.parse(row.date),
              concept: row.concept,
              categoryId: parent,
              amountCents: row.csvAmountCents,
            ),
          );
        } else {
          await budgets.create(
            BudgetInput.fromHistoricalCsv(
              month: BudgetMonth.parse(row.date),
              categoryId: parent!,
              csvAmountCents: row.csvAmountCents,
            ),
          );
        }
      }
      await SqliteWealthRepository(db)
          .setValue(Month(2026, 1), account, 600000);
      await SqliteWealthRepository(db)
          .setValue(Month(2027, 1), account, 650000);
      final editor = BudgetProposalEditor(await calculator.calculate(2026));
      editor.editAmount(month: jan, categoryId: root, amountCents: -37000);
      editor.split(
        month: jan,
        parentCategoryId: root,
        allocations: [
          BudgetProposalSplitAllocation(categoryId: child, amountCents: -37000),
        ],
      );
      final before = await snapshot();
      final revision = (await db.readState()).revision;
      final review = await saver.review(editor.validatedDraft());
      expect(review.requiresReplacement, isFalse);
      expect(review.confirmationLabel, 'Guardar propuesta');
      expect(review.plan.before, isEmpty);
      expect(await snapshot(), before);
      final results = await Future.wait([save(review), save(review)]);
      expect(identical(results[0], results[1]), isTrue);
      expect((await db.readState()).revision, revision + 1);
      final after = await snapshot();
      expect(
        {...after}
          ..remove('budgets')
          ..remove('database_state'),
        {...before}
          ..remove('budgets')
          ..remove('database_state'),
      );
      expect((await budgets.readYear(2026)).length, 48);
      final january = await budgets.list(jan);
      expect(
        january.singleWhere((r) => r.data.categoryId == other).data.amountCents,
        310000,
      );
      expect(
        january.singleWhere((r) => r.data.categoryId == child).data.amountCents,
        -37000,
      );
      expect(january.any((r) => r.data.categoryId == root), isFalse);
      expect(
        (await budgets.list(feb))
            .singleWhere((r) => r.data.categoryId == root)
            .data
            .amountCents,
        -43000,
      );
      expect(
        (await budgets.list(BudgetMonth(2027, 3)))
            .every((r) => r.data.amountCents == 0),
        isTrue,
      );
      expect(identical(await save(review), results.first), isTrue);
      expect(await snapshot(), after);
      await db.close();
      db = open();
      compose();
      expect(await snapshot(), after);
    },
  );

  test('Comparación completa, retiradas archivadas, rutas repetidas y ámbito exacto', () async {
    final parent = await item(root);
    final desc = await item(leaf, month: feb);
    final march = BudgetMonth(2027, 3);
    final archived = await item(child, month: march);
    await categories.archive(child);
    await item(root, month: BudgetMonth(2027, 4));
    await item(other);
    final editor = BudgetProposalEditor(
      select(await calculator.calculate(2026), months: [jan, feb, march]),
    );
    editor.split(
      month: jan,
      parentCategoryId: root,
      allocations: [
        BudgetProposalSplitAllocation(categoryId: sibling, amountCents: 0),
      ],
    );
    final draft = editor.validatedDraft();
    final before = await snapshot();
    final review = await saver.review(draft);
    expect(
      review.plan.before.map((r) => r.id),
      unorderedEquals([parent.id, desc.id, archived.id]),
    );
    expect(
      review.changes
          .where((c) => c.kind == BudgetProposalChangeKind.removed)
          .length,
      3,
    );
    expect(
      review.changes
          .where((c) => c.kind == BudgetProposalChangeKind.added)
          .length,
      3,
    );
    expect(
      review.changes.singleWhere((c) => c.categoryId == leaf).categoryPath,
      'Alimentación / Supermercado / Compra semanal',
    );
    expect(review.confirmationLabel, 'Sustituir partidas');
    expect(await snapshot(), before);
    await expectLater(
      saver.save(review, confirmation: BudgetProposalConfirmation.saveProposal),
      throwsA(failure(BudgetProposalSaveFailureCode.confirmationRequired)),
    );
    expect(await snapshot(), before);
    // Cambios concurrentes de meses/raíces ajenos no invalidan la revisión.
    final outsider = await item(
      root,
      month: BudgetMonth(2027, 5),
      amount: -777,
    );
    final beforeSave = await snapshot();
    await save(review);
    expect((await budgets.get(outsider.id))!.data.amountCents, -777);
    final after = await snapshot();
    final oldRows = beforeSave['budgets']! as List<Map<String, Object?>>;
    final newRows = after['budgets']! as List<Map<String, Object?>>;
    expect(
      newRows.where(
        (r) =>
            ![jan.value, feb.value, march.value].contains(r['month']) ||
            r['category_id'] == other,
      ),
      oldRows.where(
        (r) =>
            ![jan.value, feb.value, march.value].contains(r['month']) ||
            r['category_id'] == other,
      ),
    );
    expect(
      (await budgets.list(jan))
          .singleWhere((r) => r.data.categoryId != other)
          .data
          .categoryId,
      sibling,
    );
    expect((await budgets.list(feb)).single.data.categoryId, root);
    expect((await budgets.list(march)).single.data.categoryId, root);
    expect(() => review.changes.clear(), throwsUnsupportedError);
    expect(() => review.plan.after.clear(), throwsUnsupportedError);
  });

  test('Actualizar mismo nodo conserva ID, alta, textos y procedencia; CSV retirado no resucita', () async {
    final batches = SqliteImportBatchRepository(db);
    Future<ImportBatch> import() => batches.create(
      sha256: 'a' * 64,
      source: ImportSource.historicalCsv,
      originalName: 'sintetico.csv',
      contractVersion: '1',
      budgets: [
        ImportedBudget(
          2,
          BudgetInput.fromHistoricalCsv(
            month: jan,
            categoryId: root,
            csvAmountCents: 2500,
            concept: '  Histórico  ',
            discretion: ' Necesario ',
          ),
        ),
        ImportedBudget(
          3,
          BudgetInput.fromHistoricalCsv(
            month: feb,
            categoryId: leaf,
            csvAmountCents: 5000,
          ),
        ),
      ],
    );
    final batch = await import();
    final old = (await budgets.list(jan)).single;
    final retired = (await budgets.list(feb)).single;
    await real(root, -35025);
    final draft = select(await calculator.calculate(2026), months: [jan, feb]);
    final before = await snapshot();
    final review = await saver.review(draft);
    final change = review.changes.singleWhere(
      (c) => c.categoryId == root && c.month.value == jan.value,
    );
    expect(change.kind, BudgetProposalChangeKind.updated);
    expect(change.before!.data.amountCents, -2500);
    expect(change.after!.amountCents, -36000);
    expect(change.after!.concept, '  Histórico  ');
    await save(review);
    final updated = (await budgets.get(old.id))!;
    expect(updated.id, old.id);
    expect(updated.data.amountCents, -36000);
    expect(updated.data.concept, old.data.concept);
    expect(updated.data.discretion, old.data.discretion);
    expect(updated.importRowId, old.importRowId);
    expect(updated.batchId, batch.id);
    expect(updated.sourceOrdinal, 2);
    expect(await budgets.get(retired.id), isNull);
    final after = await snapshot();
    expect(
      (after['budgets']! as List<Map<String, Object?>>).singleWhere(
        (r) => r['id'] == old.id,
      )['created_at'],
      (before['budgets']! as List<Map<String, Object?>>).singleWhere(
        (r) => r['id'] == old.id,
      )['created_at'],
    );
    expect(after['import_rows'], before['import_rows']);
    expect(after['import_batches'], before['import_batches']);
    await expectLater(import(), throwsA(isA<MovementFailure>()));
    expect(await snapshot(), after);
  });

  test('Igual importe muestra existente y exige sustitución sin mutación ni timestamp', () async {
    await item(root, amount: 0);
    final review = await saver.review(select(await calculator.calculate(2026)));
    expect(review.changes.single.kind, BudgetProposalChangeKind.unchanged);
    final before = await snapshot();
    await expectLater(
      saver.save(review, confirmation: BudgetProposalConfirmation.saveProposal),
      throwsA(failure(BudgetProposalSaveFailureCode.confirmationRequired)),
    );
    await save(review);
    expect(await snapshot(), before);
  });

  test('Revisión de otra sesión rechazada y reintento exitoso no pisa ediciones posteriores', () async {
    final review = await saver.review(select(await calculator.calculate(2026)));
    final otherSaver = createBudgetProposalSaver(
      database: db,
      invalidation: invalidation,
    );
    await expectLater(
      otherSaver.save(review, confirmation: review.requiredConfirmation),
      throwsA(failure(BudgetProposalSaveFailureCode.invalidReview)),
    );
    final result = await save(review);
    await budgets.edit(
      result.records.single.id,
      BudgetInput(month: jan, categoryId: root, amountCents: -999),
    );
    final before = await snapshot();
    expect(identical(await save(review), result), isTrue);
    expect(await snapshot(), before);
  });

  test('Valida signos fuente reales aunque constructor oculte filas y permite revisión explícita', () async {
    await real(root, 200);
    final draft = select(await calculator.calculate(2026));
    final forged = copy(
      draft,
      sourceRows: [],
      allocations: [
        BudgetInput(month: jan, categoryId: root, amountCents: -100),
      ],
    );
    final before = await snapshot();
    await expectLater(
      saver.review(forged),
      throwsA(
        isA<BudgetProposalEditFailure>().having(
          (e) => e.code,
          'code',
          BudgetProposalEditFailureCode.signsNotReviewed,
        ),
      ),
    );
    expect(await snapshot(), before);
    final editor = BudgetProposalEditor(draft);
    editor.setSignsReviewed(true);
    final review = await saver.review(editor.validatedDraft());
    await save(review);
    expect((await budgets.list(jan)).single.data.amountCents, 1000);
  });

  test('Rechaza borradores inválidos, categorías archivadas y padre/descendiente sin cambios', () async {
    await categories.archive(leaf);
    final draft = select(await calculator.calculate(2026));
    final before = await snapshot();
    for (final allocations in [
      [
        BudgetInput(month: jan, categoryId: root, amountCents: 0),
        BudgetInput(month: jan, categoryId: child, amountCents: 0),
      ],
      [
        BudgetInput(month: jan, categoryId: root, amountCents: 0),
        BudgetInput(month: jan, categoryId: root, amountCents: 0),
      ],
      [BudgetInput(month: jan, categoryId: leaf, amountCents: 0)],
      [BudgetInput(month: jan, categoryId: 'missing', amountCents: 0)],
      [
        BudgetInput(
          month: BudgetMonth(2026, 1),
          categoryId: root,
          amountCents: 0,
        ),
      ],
      [BudgetInput(month: jan, categoryId: other, amountCents: 0)],
    ]) {
      await expectLater(
        saver.review(copy(draft, allocations: allocations)),
        throwsA(isA<BudgetProposalEditFailure>()),
      );
      expect(await snapshot(), before);
    }
    await expectLater(
      saver.review(
        copy(
          draft,
          allocations: [
            BudgetInput(
              month: jan,
              categoryId: root,
              amountCents: 0,
              concept: ' ',
            ),
          ],
        ),
      ),
      throwsA(isA<BudgetFailure>()),
    );
    expect(await snapshot(), before);
  });

  test(
    'Una revisión invalidada no vuelve a servir aunque los datos se restauren',
    () async {
      final old = await item(root, amount: -100);
      final draft = select(await calculator.calculate(2026));
      final review = await saver.review(draft);
      await budgets.edit(
        old.id,
        BudgetInput(month: jan, categoryId: root, amountCents: -200),
      );
      await expectLater(
        save(review),
        throwsA(failure(BudgetProposalSaveFailureCode.staleReview)),
      );
      await budgets.edit(old.id, old.data);
      final before = await snapshot();
      await expectLater(
        save(review),
        throwsA(failure(BudgetProposalSaveFailureCode.staleReview)),
      );
      expect(await snapshot(), before);
      final freshReview = await saver.review(
        select(await calculator.calculate(2026)),
      );
      await save(freshReview);
      expect((await budgets.get(old.id))!.data.amountCents, 0);
    },
  );

  test('Fuente concurrente que desborda exige revisión nueva sin guardar cifras antiguas', () async {
    final source = await real(root, -500);
    final review = await saver.review(select(await calculator.calculate(2026)));
    await db.run(
      () => db.customStatement(
        'UPDATE movements SET amount_cents=? WHERE id=?',
        [-9223372036854775808, source.id],
      ),
    );
    final before = await snapshot();
    await expectLater(
      save(review),
      throwsA(failure(BudgetProposalSaveFailureCode.staleReview)),
    );
    expect(await snapshot(), before);
  });

  for (final operation in ['DELETE', 'UPDATE', 'INSERT', 'REVISION']) {
    test(
      'Fallo SQLite $operation revierte TODAS las escrituras y revisión; reintento intacto',
      () async {
        await item(child);
        await item(root, month: feb, amount: -200);
        final draft = select(
          await calculator.calculate(2026),
          months: [feb, jan],
        );
        // Garantiza UPDATE previo al INSERT, además de DELETE inicial.
        final reviewedDraft = copy(
          draft,
          allocations: draft.allocations.reversed,
        );
        final review = await saver.review(reviewedDraft);
        final before = await snapshot();
        final target = operation == 'REVISION'
            ? 'UPDATE ON database_state'
            : '$operation ON budgets';
        await db.customStatement(
          "CREATE TEMP TRIGGER fail_save AFTER $target BEGIN SELECT RAISE(ABORT, 'synthetic write failure'); END",
        );
        await expectLater(
          save(review),
          throwsA(failure(BudgetProposalSaveFailureCode.persistence)),
        );
        expect(await snapshot(), before);
        expect(identical(review.plan.draft, reviewedDraft), isTrue);
        expect(review.plan.before.length, 2);
        await db.customStatement('DROP TRIGGER fail_save');
        final revision = (await db.readState()).revision;
        await save(review);
        expect((await db.readState()).revision, revision + 1);
        expect((await budgets.list(jan)).single.data.categoryId, root);
        expect((await budgets.list(feb)).single.data.amountCents, 0);
      },
    );
  }

  for (final mutation in [
    'importe fuente',
    'fecha fuente',
    'categoría fuente',
    'alta fuente',
    'baja fuente',
    'excluido',
    'neto igual',
    'nombre árbol',
    'archivo árbol',
    'alta árbol',
    'importe destino',
    'texto destino',
    'alta destino',
    'baja destino',
    'dataset',
  ]) {
    test(
      'Dos conexiones: $mutation exige revisión nueva sin sobrescribir datos ajenos',
      () async {
        final first = await real(child, -500);
        final second = await real(child, 500);
        final excluded = await real(null, -123);
        final existing = await item(child);
        final draft = select(await calculator.calculate(2026));
        final review = await saver.review(draft);
        final writer = open();
        addTearDown(writer.close);
        await writer.readState();
        await writer.run(() async {
          switch (mutation) {
            case 'importe fuente':
              await writer.customStatement(
                'UPDATE movements SET amount_cents=-600 WHERE id=?',
                [first.id],
              );
            case 'fecha fuente':
              await writer.customStatement(
                "UPDATE movements SET value_date='2026-02-15' WHERE id=?",
                [first.id],
              );
            case 'categoría fuente':
              await writer.customStatement(
                'UPDATE movements SET category_id=? WHERE id=?',
                [sibling, first.id],
              );
            case 'alta fuente':
              await SqliteMovementRepository(writer).create(
                MovementInput(
                  accountId: account,
                  valueDate: ValueDate(2026, 1, 20),
                  concept: 'Alta concurrente',
                  categoryId: root,
                  amountCents: -1,
                ),
              );
            case 'baja fuente':
              await writer.customStatement('DELETE FROM movements WHERE id=?', [
                first.id,
              ]);
            case 'excluido':
              await writer.customStatement(
                'UPDATE movements SET amount_cents=-124 WHERE id=?',
                [excluded.id],
              );
            case 'neto igual':
              await writer.customStatement(
                'UPDATE movements SET amount_cents=-400 WHERE id=?',
                [first.id],
              );
              await writer.customStatement(
                'UPDATE movements SET amount_cents=400 WHERE id=?',
                [second.id],
              );
            case 'nombre árbol':
              await writer.customStatement(
                "UPDATE categories SET name='Renombrada' WHERE id=?",
                [child],
              );
            case 'archivo árbol':
              await writer.customStatement(
                'UPDATE categories SET archived=1 WHERE id IN (?,?)',
                [child, leaf],
              );
            case 'alta árbol':
              final management = createCategoryManagement(
                database: writer,
                invalidation: invalidation,
              );
              await management.create(name: 'Nueva raíz');
            case 'importe destino':
              await writer.customStatement(
                'UPDATE budgets SET amount_cents=-200 WHERE id=?',
                [existing.id],
              );
            case 'texto destino':
              await writer.customStatement(
                "UPDATE budgets SET concept='Metadato concurrente' WHERE id=?",
                [existing.id],
              );
            case 'alta destino':
              await SqliteBudgetRepository(writer).create(
                BudgetInput(month: jan, categoryId: sibling, amountCents: 0),
              );
            case 'baja destino':
              await SqliteBudgetRepository(writer).delete(existing.id);
            case 'dataset':
              await writer.customStatement(
                "UPDATE database_state SET dataset_id='12345678-1234-4234-8234-123456789012'",
              );
          }
        });
        final before = await snapshot();
        await expectLater(
          save(review),
          throwsA(failure(BudgetProposalSaveFailureCode.staleReview)),
        );
        expect(await snapshot(), before);
        await expectLater(
          save(review),
          throwsA(failure(BudgetProposalSaveFailureCode.staleReview)),
        );
        await expectLater(
          saver.review(draft),
          throwsA(failure(BudgetProposalSaveFailureCode.staleReview)),
        );
        expect(await snapshot(), before);
        expect(identical(review.plan.draft, draft), isTrue);
      },
    );
  }

  test(
    'Cambios relevantes sin incremento de revisión también se detectan',
    () async {
      final old = await item(root);
      final review = await saver.review(
        select(await calculator.calculate(2026)),
      );
      final state = await db.readState();
      final writer = open();
      addTearDown(writer.close);
      await writer.readState();
      await writer.customStatement(
        'UPDATE budgets SET amount_cents=-999 WHERE id=?',
        [old.id],
      );
      expect((await db.readState()).revision, state.revision);
      final before = await snapshot();
      await expectLater(
        save(review),
        throwsA(failure(BudgetProposalSaveFailureCode.staleReview)),
      );
      expect(await snapshot(), before);
    },
  );

  test('Presupuesto fuente, otros años, fotos y concepto real no invalidan comparación', () async {
    final source = await real(child, -500);
    final draft = select(await calculator.calculate(2026));
    final review = await saver.review(draft);
    await item(root, month: BudgetMonth(2026, 1));
    await real(root, -888, year: 2025);
    await SqliteWealthRepository(db).setValue(Month(2026, 1), account, 555000);
    await db.run(
      () => db.customStatement(
        "UPDATE movements SET concept='Corrección de texto' WHERE id=?",
        [source.id],
      ),
    );
    final before = await snapshot();
    await save(review);
    final after = await snapshot();
    expect(
      {...after}
        ..remove('budgets')
        ..remove('database_state'),
      {...before}
        ..remove('budgets')
        ..remove('database_state'),
    );
    expect((await budgets.list(jan)).single.data.amountCents, -1000);
  });

  test(
    'Carrera WAL después de releer: transacción excluye otra escritura',
    () async {
      await db.customStatement('PRAGMA journal_mode=WAL');
      final old = await item(child);
      final writer = open();
      addTearDown(writer.close);
      await writer.readState();
      final hook = _BeforeWriteBudgetRepository(budgets);
      final raceSaver = BudgetProposalSaver(
        calculator: calculator,
        budgets: hook,
        unitOfWork: db,
      );
      final review = await raceSaver.review(
        select(await calculator.calculate(2026)),
      );
      var writerBlocked = false;
      hook.beforeWrite = () async {
        try {
          await SqliteBudgetRepository(writer).edit(
            old.id,
            BudgetInput(month: jan, categoryId: child, amountCents: -9876),
          );
          fail('La transacción debe excluir la escritura concurrente');
        } on SqliteException catch (e) {
          expect(e.resultCode, 5); // SQLITE_BUSY de BEGIN IMMEDIATE.
          writerBlocked = true;
        }
        return null;
      };
      final revision = (await db.readState()).revision;
      final result = await raceSaver.save(
        review,
        confirmation: review.requiredConfirmation,
      );
      expect(writerBlocked, isTrue);
      expect((await db.readState()).revision, revision + 1);
      expect(await budgets.get(old.id), isNull);
      expect((await budgets.list(jan)).length, 1);
      // Tras el commit puede entrar la otra conexión. Repetir el acuse anterior
      // no vuelve a aplicar la propuesta sobre esa edición posterior.
      await SqliteBudgetRepository(writer).edit(
        result.records.single.id,
        BudgetInput(month: jan, categoryId: root, amountCents: -9876),
      );
      final before = await snapshot();
      expect(
        identical(
          await raceSaver.save(
            review,
            confirmation: review.requiredConfirmation,
          ),
          result,
        ),
        isTrue,
      );
      expect(await snapshot(), before);
    },
  );

  test('Dos revisiones simultáneas del mismo destino no duplican ni borran la ganadora', () async {
    final draft = select(await calculator.calculate(2026));
    final first = await saver.review(draft);
    final second = await saver.review(draft);
    final outcomes = await Future.wait([
      save(first),
      save(second).then<Object>((r) => r, onError: (Object e) => e),
    ]);
    expect(outcomes.first, isA<BudgetProposalSaveResult>());
    expect(outcomes.last, failure(BudgetProposalSaveFailureCode.staleReview));
    expect((await budgets.list(jan)).length, 1);
    expect(
      (await budgets.list(jan)).single.id,
      (outcomes.first as BudgetProposalSaveResult).records.single.id,
    );
  });
}

/// Solo controla el instante de una carrera; las escrituras siguen siendo SQLite real.
final class _BeforeWriteBudgetRepository implements BudgetRepository {
  _BeforeWriteBudgetRepository(this.inner);
  final BudgetRepository inner;
  Future<Object?> Function()? beforeWrite;
  Future<void> _before() async {
    final hook = beforeWrite;
    beforeWrite = null;
    if (hook != null) await hook();
  }

  @override
  Future<BudgetRecord> create(BudgetInput data) async {
    await _before();
    return inner.create(data);
  }

  @override
  Future<void> delete(String id) async {
    await _before();
    await inner.delete(id);
  }

  @override
  Future<BudgetRecord> edit(String id, BudgetInput data) async {
    await _before();
    return inner.edit(id, data);
  }

  @override
  Future<BudgetRecord?> get(String id) => inner.get(id);
  @override
  Future<List<BudgetRecord>> list(BudgetMonth month) => inner.list(month);
  @override
  Future<List<BudgetRecord>> readYear(int year, {bool incomeOnly = false}) =>
      inner.readYear(year, incomeOnly: incomeOnly);
}
