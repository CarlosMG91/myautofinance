import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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

import 'budget_proposal_reference_csv.dart';

/// Mismo contrato financiero en el host, Windows y Android. Solo usa el archivo
/// desechable del llamador, nunca la base ni las credenciales de la aplicación.
Future<void> budgetProposalAcceptanceJourney(Directory directory) async {
  final previousWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  // La segunda conexión usa un executor independiente para ejercer concurrencia.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final file = File('${directory.path}/proposal-156.sqlite');
  LocalDatabase open() => LocalDatabase(
    NativeDatabase(
      file,
      setup: (sqlite) => sqlite.execute('PRAGMA foreign_keys=ON'),
    ),
  );
  var db = open();
  final invalidation = CategoryReadInvalidation();
  final jan = BudgetMonth(2027, 1), feb = BudgetMonth(2027, 2);
  try {
    final categories = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    final account = (await SqliteAccountRepository(db).create(
      name: 'Cuenta sintética EP-001',
      kind: AccountKind.account,
      activeFrom: Month(2025, 1),
      liquidity: Liquidity.liquid,
    )).id;
    final bytes = utf8.encode(budgetProposalReferenceCsv);
    final csv = const HistoricalCsvReader().read(bytes);
    expect(csv.isValid, isTrue);
    final nodes = <String, String>{};
    final importedReals = <ImportedMovement>[];
    final importedBudgets = <ImportedBudget>[];
    var ordinal = 1;
    for (final row in csv.records) {
      ordinal++;
      String? parent;
      for (var level = 0; level < row.categoryPath.length; level++) {
        final path = row.categoryPath.take(level + 1).join(' / ');
        parent = nodes[path] ??= (await categories.create(
          name: row.categoryPath[level],
          parentId: parent,
          isIncome: parent == null
              ? row.categoryPath.first == 'Ingresos'
              : null,
        )).node.id;
      }
      if (row.type == HistoricalCsvType.real) {
        importedReals.add(
          ImportedMovement(
            ordinal,
            MovementInput(
              accountId: account,
              valueDate: ValueDate.parse(row.date),
              categoryId: parent,
              concept: row.concept,
              amountCents: row.csvAmountCents,
            ),
          ),
        );
      } else {
        importedBudgets.add(
          ImportedBudget(
            ordinal,
            BudgetInput.fromHistoricalCsv(
              month: BudgetMonth.parse(row.date),
              categoryId: parent!,
              csvAmountCents: row.csvAmountCents,
              concept: row.concept,
            ),
          ),
        );
      }
    }
    await SqliteImportBatchRepository(db).create(
      sha256: sha256.convert(bytes).toString(),
      source: ImportSource.historicalCsv,
      originalName: 'historico-ejemplo.csv',
      contractVersion: '1',
      movements: importedReals,
      budgets: importedBudgets,
    );
    expect(importedReals, hasLength(10));
    expect(importedBudgets, hasLength(48));
    final food = nodes['Alimentación']!;
    final child = nodes['Alimentación / Supermercado']!;
    final income = nodes['Ingresos']!;
    var budgets = SqliteBudgetRepository(db);
    var calculator = createBudgetProposalCalculator(
      database: db,
      invalidation: invalidation,
    );
    var saver = createBudgetProposalSaver(
      database: db,
      invalidation: invalidation,
    );
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

    final base = await snapshot();
    final h = await calculator.calculate(2026);
    const expected = {
      'Ingresos': [310000, 302000],
      'Vivienda': [-100000, -100000],
      'Alimentación': [-36000, -43000],
      'Ahorro': [-50000, -50000],
      'Ocio': [-2000, 0],
    };
    expect(h.allocations, hasLength(60));
    for (final row in h.sourceRows) {
      expect(
        row.proposedAmountCents,
        row.targetMonth.value == jan.value
            ? expected[row.categoryPath]![0]
            : row.targetMonth.value == feb.value
            ? expected[row.categoryPath]![1]
            : 0,
      );
    }
    expect(h.requiresSignReview, isFalse);
    final cancelled = BudgetProposalEditor(h);
    cancelled.editAmount(month: jan, categoryId: food, amountCents: -37000);
    cancelled.cancel();
    expect(await snapshot(), base);
    expect(
      (await calculator.calculate(2026)).allocations
          .singleWhere(
            (a) => a.categoryId == food && a.month.value == jan.value,
          )
          .amountCents,
      -36000,
    );
    // Destino previamente importado: actualización de un nodo y retirada de
    // otro; la huella y sus filas siguen existiendo después de la sustitución.
    final targetBytes = utf8.encode('fixture sintética destino EP-018 v1');
    Future<ImportBatch> importTarget() =>
        SqliteImportBatchRepository(db).create(
          sha256: sha256.convert(targetBytes).toString(),
          source: ImportSource.historicalCsv,
          originalName: 'destino-sintetico.csv',
          contractVersion: '1',
          budgets: [
            ImportedBudget(
              2,
              BudgetInput.fromHistoricalCsv(
                month: jan,
                categoryId: food,
                csvAmountCents: 50000,
              ),
            ),
            ImportedBudget(
              3,
              BudgetInput.fromHistoricalCsv(
                month: jan,
                categoryId: income,
                csvAmountCents: -90000,
                concept: '  Concepto importado  ',
                discretion: ' Necesario ',
              ),
            ),
            ImportedBudget(
              4,
              BudgetInput.fromHistoricalCsv(
                month: feb,
                categoryId: child,
                csvAmountCents: 44000,
              ),
            ),
          ],
        );
    await importTarget();
    final originalIncome = (await budgets.list(jan))
        .singleWhere((r) => r.data.categoryId == income);
    final archived = (await categories.create(name: 'Archivada')).node.id;
    await budgets.create(
      BudgetInput(month: jan, categoryId: archived, amountCents: -77777),
    );
    final archivedChild = (await categories.create(
      name: 'Hija archivada',
      parentId: food,
    )).node.id;
    final movements = SqliteMovementRepository(db);
    Future<void> real(String? id, int cents, int month) async {
      await movements.create(
        MovementInput(
          accountId: account,
          valueDate: ValueDate(2026, month, 15),
          categoryId: id,
          concept: 'Real sintético',
          amountCents: cents,
        ),
      );
    }

    await real(archived, -4321, 1);
    await real(null, 1234, 1);
    await categories.archive(archived);
    await real(archivedChild, -10001, 3);
    await real(child, 10000, 3); // Neto -0,01: redondear después de sumar.
    await categories.archive(archivedChild);
    await real(child, -500, 4);
    await real(child, 500, 4); // Cero por compensación, distinto de ausencia.
    await real(child, 1, 5); // Salida positiva: revisión obligatoria.
    await real(income, -1, 5); // Ingreso negativo: revisión obligatoria.
    await budgets.create(
      BudgetInput(
        month: BudgetMonth(2027, 3),
        categoryId: food,
        amountCents: -88888,
      ),
    );
    await budgets.create(
      BudgetInput(
        month: BudgetMonth(2028, 1),
        categoryId: food,
        amountCents: -99999,
      ),
    );
    await SqliteWealthRepository(db).setValue(Month(2026, 1), account, 600000);
    await SqliteWealthRepository(db).setValue(Month(2027, 1), account, 650000);
    BudgetProposalDraft selected(
      BudgetProposalDraft d, {
      Iterable<BudgetInput>? allocations,
    }) => BudgetProposalDraft(
      sourceYear: d.sourceYear,
      targetYear: d.targetYear,
      sourceRows: d.sourceRows,
      excludedReals: d.excludedReals,
      basis: d.basis,
      signsReviewed: d.signsReviewed,
      includedScopes: d.includedScopes.where(
        (s) =>
            (s.rootId == food &&
                [jan.value, feb.value].contains(s.month.value)) ||
            (s.rootId == income && s.month.value == jan.value),
      ),
      allocations:
          allocations ??
          d.allocations.where(
            (a) =>
                (a.categoryId == food &&
                    [jan.value, feb.value].contains(a.month.value)) ||
                (a.categoryId == income && a.month.value == jan.value),
          ),
    );
    final extended = await calculator.calculate(2026);
    final foodRows = extended.sourceRows
        .where((r) => r.categoryId == food)
        .toList();
    expect(foodRows[2].sourceAmountCents, -1);
    expect(foodRows[2].proposedAmountCents, -1000);
    expect(foodRows[3].sourceMovementCount, 2);
    expect(foodRows[3].proposedAmountCents, 0);
    expect(foodRows[5].hasSourceReals, isFalse);
    expect(foodRows[5].proposedAmountCents, 0);
    expect(
      extended.excludedReals.map((e) => e.reason),
      unorderedEquals([
        BudgetProposalExclusionReason.unclassified,
        BudgetProposalExclusionReason.archivedRoot,
      ]),
    );
    expect(
      extended.allocations.any(
        (a) => [archived, archivedChild].contains(a.categoryId),
      ),
      isFalse,
    );
    final editor = BudgetProposalEditor(selected(extended));
    final beforeReview = await snapshot();
    await expectLater(
      saver.review(editor.draft),
      throwsA(
        isA<BudgetProposalEditFailure>().having(
          (e) => e.code,
          'code',
          BudgetProposalEditFailureCode.signsNotReviewed,
        ),
      ),
    );
    expect(await snapshot(), beforeReview);
    editor.setSignsReviewed(true);
    editor.editAmount(month: jan, categoryId: food, amountCents: -37000);
    expect(editor.draft.signsReviewed, isFalse);
    expect(
      editor
          .splitOptions(month: jan, parentCategoryId: food)
          .any((o) => o.node.id == archivedChild),
      isFalse,
    );
    editor.split(
      month: jan,
      parentCategoryId: food,
      allocations: [
        BudgetProposalSplitAllocation(categoryId: child, amountCents: -37000),
      ],
    );
    expect(
      editor.draft.allocations.any(
        (a) => a.month.value == jan.value && a.categoryId == food,
      ),
      isFalse,
    );
    expect(
      editor.draft.allocations
          .singleWhere(
            (a) => a.month.value == feb.value && a.categoryId == food,
          )
          .amountCents,
      -43000,
    );
    editor.setSignsReviewed(true);
    final draft = editor.validatedDraft();
    final invalid = selected(
      draft,
      allocations: [
        ...draft.allocations,
        BudgetInput(month: jan, categoryId: food, amountCents: -37000),
      ],
    );
    await expectLater(
      saver.review(invalid),
      throwsA(
        isA<BudgetProposalEditFailure>().having(
          (e) => e.code,
          'code',
          BudgetProposalEditFailureCode.ancestorDescendantConflict,
        ),
      ),
    );
    expect(await snapshot(), beforeReview);
    final review = await saver.review(draft);
    expect(review.changes, hasLength(5));
    expect(
      review.changes.where((c) => c.kind == BudgetProposalChangeKind.removed),
      hasLength(2),
    );
    expect(review.plan.before, hasLength(3));
    expect(review.plan.after, hasLength(3));
    expect(review.confirmationLabel, 'Sustituir partidas');
    expect(await snapshot(), beforeReview); // Cancelar comparación no escribe.
    await expectLater(
      saver.save(review, confirmation: BudgetProposalConfirmation.saveProposal),
      throwsA(
        isA<BudgetProposalSaveFailure>().having(
          (e) => e.code,
          'code',
          BudgetProposalSaveFailureCode.confirmationRequired,
        ),
      ),
    );
    expect(await snapshot(), beforeReview);
    // Una segunda conexión cambia un dato pertinente sin incrementar revisión.
    // La revalidación debe leer los datos, incluso con la misma revisión global.
    final writer = open();
    try {
      await writer.readState();
      await writer.customStatement(
        'UPDATE budgets SET amount_cents=-50100 WHERE month=? AND category_id=?',
        [jan.value, food],
      );
    } finally {
      await writer.close();
    }
    expect((await db.readState()).revision, draft.basis.datasetState.revision);
    final concurrent = await snapshot();
    await expectLater(
      saver.save(review, confirmation: review.requiredConfirmation),
      throwsA(
        isA<BudgetProposalSaveFailure>().having(
          (e) => e.code,
          'code',
          BudgetProposalSaveFailureCode.staleReview,
        ),
      ),
    );
    expect(await snapshot(), concurrent);
    expect(
      editor.draft.allocations
          .singleWhere((a) => a.categoryId == child)
          .amountCents,
      -37000,
    );
    // Regenerar es explícito; repetir edición y revisión conserva -370 exacto.
    final freshEditor = BudgetProposalEditor(
      selected(await calculator.calculate(2026)),
    );
    freshEditor.editAmount(month: jan, categoryId: food, amountCents: -37000);
    freshEditor.split(
      month: jan,
      parentCategoryId: food,
      allocations: [
        BudgetProposalSplitAllocation(categoryId: child, amountCents: -37000),
      ],
    );
    freshEditor.setSignsReviewed(true);
    final freshReview = await saver.review(freshEditor.validatedDraft());
    final beforeSave = await snapshot();
    // Se borran las retiradas antes de que falle una alta real de SQLite.
    // El fallo real de SQLite debe revertirlo todo, incluida su revisión.
    await db.customStatement(
      "CREATE TEMP TRIGGER fail_proposal AFTER INSERT ON budgets BEGIN SELECT RAISE(ABORT,'synthetic-156'); END",
    );
    await expectLater(
      saver.save(freshReview, confirmation: freshReview.requiredConfirmation),
      throwsA(
        isA<BudgetProposalSaveFailure>().having(
          (e) => e.code,
          'code',
          BudgetProposalSaveFailureCode.persistence,
        ),
      ),
    );
    expect(await snapshot(), beforeSave);
    await db.customStatement('DROP TRIGGER fail_proposal');
    final revision = (await db.readState()).revision;
    final outcomes = await Future.wait([
      saver.save(freshReview, confirmation: freshReview.requiredConfirmation),
      saver.save(freshReview, confirmation: freshReview.requiredConfirmation),
    ]);
    expect(identical(outcomes[0], outcomes[1]), isTrue);
    expect((await db.readState()).revision, revision + 1);
    final afterSave = await snapshot();
    expect(
      {...afterSave}
        ..remove('budgets')
        ..remove('database_state'),
      {...beforeSave}
        ..remove('budgets')
        ..remove('database_state'),
    );
    bool outside(Map<String, Object?> r) =>
        !(r['category_id'] == income && r['month'] == jan.value) &&
        !([food, child].contains(r['category_id']) &&
            [jan.value, feb.value].contains(r['month']));
    expect(
      (afterSave['budgets']! as List<Map<String, Object?>>).where(outside),
      (beforeSave['budgets']! as List<Map<String, Object?>>).where(outside),
    );
    final updated = (await budgets.get(originalIncome.id))!;
    expect(updated.data.amountCents, 310000);
    expect(updated.importRowId, originalIncome.importRowId);
    expect(updated.batchId, originalIncome.batchId);
    expect(updated.sourceOrdinal, originalIncome.sourceOrdinal);
    expect(updated.data.concept, originalIncome.data.concept);
    expect(updated.data.discretion, originalIncome.data.discretion);
    expect(
      (await budgets.list(jan))
          .singleWhere((b) => b.data.categoryId == child)
          .data
          .amountCents,
      -37000,
    );
    expect(
      (await budgets.list(jan)).any((b) => b.data.categoryId == food),
      isFalse,
    );
    expect((await budgets.list(feb)).single.data.amountCents, -43000);
    await expectLater(importTarget(), throwsA(isA<MovementFailure>()));
    expect(await snapshot(), afterSave);
    expect(
      identical(
        await saver.save(
          freshReview,
          confirmation: freshReview.requiredConfirmation,
        ),
        outcomes[0],
      ),
      isTrue,
    );
    expect(await snapshot(), afterSave);
    // EP-011: el guardado ordinario sigue rechazando padre+hijo sin tocar nada.
    await expectLater(
      budgets.create(
        BudgetInput(month: jan, categoryId: food, amountCents: -37000),
      ),
      throwsA(isA<BudgetFailure>()),
    );
    expect(await snapshot(), afterSave);
    await db.close();
    db = open();
    budgets = SqliteBudgetRepository(db);
    calculator = createBudgetProposalCalculator(
      database: db,
      invalidation: invalidation,
    );
    saver = createBudgetProposalSaver(database: db, invalidation: invalidation);
    expect(await snapshot(), afterSave);
    expect((await budgets.readYear(2026)), hasLength(48));
    final reopened = await calculator.calculate(2026);
    expect(
      reopened.allocations
          .singleWhere(
            (a) => a.categoryId == food && a.month.value == jan.value,
          )
          .amountCents,
      -36000,
    );
    expect(reopened.signsReviewed, isFalse); // No se persiste el borrador.
  } finally {
    await invalidation.close();
    await db.close();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
  }
}
