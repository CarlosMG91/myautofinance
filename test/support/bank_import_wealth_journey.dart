import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/app/import_factory.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/data/sha256_import_fingerprint.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

/// Contrato bankXls de EP-012 sobre SQLite; no interpreta un extracto Openbank.
/// Los bytes y campos arbitrarios NO caracterizan ningún formato bancario.
Future<void> bankImportWealthJourney(Directory directory) async {
  final store = LocalDatabaseStore(supportDirectory: () async => directory);
  var db = await store.open();
  var services = createImportServices(db);
  const selected = ImportAccountReference.selectedAccount();
  try {
    final accounts = SqliteAccountRepository(db);
    final destination = await accounts.create(
      name: 'Destino sintético',
      kind: AccountKind.account,
      activeFrom: Month(2026, 1),
      liquidity: Liquidity.liquid,
    );
    final other = await accounts.create(
      name: 'Otra cuenta sintética',
      kind: AccountKind.account,
      activeFrom: Month(2026, 1),
      liquidity: Liquidity.liquid,
    );
    final portfolio = await accounts.create(
      name: 'Cartera sintética',
      kind: AccountKind.portfolio,
      activeFrom: Month(2026, 1),
      liquidity: Liquidity.medium,
    );
    final debt = await accounts.create(
      name: 'Deuda sintética',
      kind: AccountKind.debt,
      activeFrom: Month(2026, 1),
    );
    final category = await SqliteCategoryRepository(db)
        .create(name: 'Gasto sintético', isIncome: false);
    await SqliteBudgetRepository(db).create(
      BudgetInput(
        month: BudgetMonth(2026, 1),
        categoryId: category.id,
        amountCents: -40000,
        concept: 'Presupuesto previo protegido',
      ),
    );
    final wealth = SqliteWealthRepository(db);
    for (final entry in {
      destination.id: 600000,
      other.id: 0,
      portfolio.id: 1000000,
      debt.id: 500000,
    }.entries) {
      await wealth.setValue(Month(2026, 1), entry.key, entry.value);
    }
    await wealth.setValue(Month(2026, 2), destination.id, 620000);
    expect(
      (await wealth.read(Month(2026, 1))).status,
      WealthSnapshotStatus.complete,
    );
    expect(
      (await wealth.read(Month(2026, 2))).status,
      WealthSnapshotStatus.incomplete,
    );
    expect(
      (await wealth.read(Month(2026, 3))).status,
      WealthSnapshotStatus.absent,
    );

    Future<Map<String, Object?>> image({bool all = false}) async {
      final tables = all
          ? (await db
                    .customSelect(
                      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
                    )
                    .get())
                .map((row) => row.read<String>('name'))
                .toList()
          : ['wealth_snapshots', 'wealth_values', 'budgets'];
      return {
        for (final table in tables)
          table:
              (await db
                      .customSelect('SELECT * FROM "$table" ORDER BY rowid')
                      .get())
                  .map((row) => row.data)
                  .toList(),
        if (all)
          'local_mutation':
              (await db.customSelect('SELECT * FROM local_mutation').get())
                  .map((row) => row.data)
                  .toList(),
      };
    }

    final protected = await image();
    final bindings = ImportReferenceBindings(
      accounts: {selected: destination.id},
    );
    InterpretedMovement movement(
      int ordinal, {
      String concept = 'Café',
      int cents = -1250,
    }) => InterpretedMovement(
      sourceOrdinal: ordinal,
      originalFields: const [
        ImportOriginalField('dato sintético', 'texto original'),
        ImportOriginalField('saldo sintético informativo', '999999.99'),
        ImportOriginalField('dato sintético', ''),
      ],
      concept: concept,
      amount: ImportAmount.economic(cents),
      valueDate: ValueDate(2026, 1, 5),
      account: selected,
    );
    ImportSession session(
      int byte,
      List<InterpretedImportRow> rows, {
      String name = 'contrato-sintetico.bin',
      List<ImportIssue> issues = const [],
    }) => ImportSession(
      file: ImportFile.fromBytes(
        bytes: [byte],
        fingerprint: const Sha256ImportFingerprint(),
        source: ImportSource.bankXls,
        originalName: name,
      ),
      interpretation: ImportInterpretation(
        formatVersion: 'synthetic-contract-131',
        rows: rows,
        issues: issues,
      ),
    );
    Future<ImportReview> review(ImportSession session) =>
        services.previewer.preview(session, bindings: bindings);
    Future<ImportConfirmationResult> confirm(
      ImportReview review, {
      bool overlaps = false,
    }) => services.confirmer.confirm(
      ImportConfirmationRequest(
        review: review,
        reviewedOverlapKeys: overlaps
            ? review.overlaps.map((o) => o.key).toSet()
            : {},
      ),
    );

    final initial = await image(all: true);
    debugPrint(
      'MA-TSK-131: fotos completas, incompletas y presupuesto poblados.',
    );
    final first = session(1, [
      movement(2),
      movement(3),
      movement(4, concept: 'Entrada', cents: 30000),
    ]);
    final pending = await services.previewer.preview(first);
    expect(pending.canRequestConfirmation, isFalse);
    expect(() => ImportConfirmationRequest(review: pending), throwsStateError);
    expect(await image(all: true), initial);
    final ready = await review(first);
    expect(ready.canRequestConfirmation, isTrue);
    expect(ready.movementCount, 3);
    expect(
      ready.totalCents(budgets: false, original: false),
      BigInt.from(27500),
    );
    // Cancelar la revisión consiste en descartarla, sin confirmar ni escribir.
    expect(await image(all: true), initial);
    final result = await confirm(ready) as ImportConfirmed;
    expect(result.movementCount, 3);
    expect(result.budgetCount, 0);
    expect(await image(), protected);
    debugPrint(
      'MA-TSK-131: cuenta explícita, tres REAL y ordinales conservados.',
    );
    final originals = (await services.history.listRows(result.batch.id)).items;
    expect(originals.map((row) => row.sourceOrdinal), [2, 3, 4]);
    expect(
      originals.map((row) => row.currentMovement!.id).toSet(),
      hasLength(3),
    );
    for (final row in originals) {
      expect(row.currentMovement!.data.accountId, destination.id);
      expect(row.currentMovement!.data.categoryId, isNull);
      expect(row.currentMovement!.data.valueDate.value, '2026-01-05');
      final original = row.original! as InterpretedMovement;
      expect(original.originalFields.map((f) => (f.name, f.value)), [
        ('dato sintético', 'texto original'),
        ('saldo sintético informativo', '999999.99'),
        ('dato sintético', ''),
      ]);
    }
    expect(
      originals.take(2).map((row) => row.currentMovement!.data.amountCents),
      [-1250, -1250],
    );

    // Reabrir antes de categorizar, manteniendo origen y duplicados legítimos.
    await store.close();
    db = await store.open();
    services = createImportServices(db);
    final reopened = (await services.history.listRows(result.batch.id)).items;
    expect(reopened.map((r) => r.id), originals.map((r) => r.id));
    final current = reopened.first.currentMovement!;
    await SqliteMovementRepository(db)
        .setCategoryBatch([current.id], category.id);
    final categorized = (await services.history.getRow(reopened.first.id))!;
    expect(categorized.currentMovement!.data.categoryId, category.id);
    expect((categorized.original! as InterpretedMovement).category, isNull);
    expect(await image(), protected);

    final beforeRepeat = await image(all: true);
    final renamed = session(
      1,
      first.interpretation.rows,
      name: 'renombrado.xls',
    );
    expect(await confirm(await review(renamed)), isA<ImportAlreadyImported>());
    expect(await image(all: true), beforeRepeat);
    final overlap = await review(session(2, [movement(2)]));
    expect(overlap.overlaps, isNotEmpty);
    expect(() => ImportConfirmationRequest(review: overlap), throwsStateError);
    expect(await image(all: true), beforeRepeat);
    expect(await confirm(overlap, overlaps: true), isA<ImportConfirmed>());
    expect(await SqliteMovementRepository(db).readYear(2026), hasLength(4));
    expect(await image(), protected);
    debugPrint(
      'MA-TSK-131: repetición cero altas; solapamiento conserva ambos.',
    );

    final beforeError = await image(all: true);
    final invalid = await review(
      session(
        3,
        [movement(2)],
        issues: const [
          ImportIssue(
            code: ImportIssueCode.invalidFile,
            reason:
                'Error sintético del contrato; no es un diagnóstico Openbank.',
          ),
        ],
      ),
    );
    expect(invalid.canRequestConfirmation, isFalse);
    expect(() => ImportConfirmationRequest(review: invalid), throwsStateError);
    expect(await image(all: true), beforeError);

    // Un escritor independiente introduce un solapamiento después de revisar.
    final staleSession = session(4, [movement(2, concept: 'Concurrente')]);
    final stale = await review(staleSession);
    final second = LocalDatabase(
      NativeDatabase(File(store.databasePath!), setup: configureConnection),
    );
    try {
      final otherServices = createImportServices(second);
      final concurrent = await otherServices.previewer.preview(
        session(5, [movement(2, concept: 'Concurrente')]),
        bindings: bindings,
      );
      expect(
        await otherServices.confirmer.confirm(
          ImportConfirmationRequest(review: concurrent),
        ),
        isA<ImportConfirmed>(),
      );
    } finally {
      await second.close();
    }
    final afterConcurrent = await image(all: true);
    expect(await confirm(stale), isA<ImportRejected>());
    expect(await image(all: true), afterConcurrent);
    final refreshed = await review(staleSession);
    expect(refreshed.overlaps, isNotEmpty);
    expect(await confirm(refreshed, overlaps: true), isA<ImportConfirmed>());
    expect(await image(), protected);

    // Fallo tardío, después de crear una cuenta y movimientos: rollback total.
    final planned = ImportReferenceBindings(
      newAccounts: {
        selected: ImportNewAccount(
          name: 'Cuenta a revertir',
          activeFrom: Month(2026, 1),
          liquidity: Liquidity.liquid,
        ),
      },
    );
    final beforePlanned = await image(all: true);
    final failing = await services.previewer.preview(
      session(6, [
        movement(2, concept: 'Rollback'),
        movement(3, concept: 'Rollback legítimo'),
      ]),
      bindings: planned,
    );
    // Descartar una revisión con un alta preparada tampoco crea referencias.
    expect(failing.canRequestConfirmation, isTrue);
    expect(await image(all: true), beforePlanned);
    final invalidPlanned = await services.previewer.preview(
      invalid.session,
      bindings: planned,
    );
    expect(invalidPlanned.canRequestConfirmation, isFalse);
    expect(await image(all: true), beforePlanned);
    await db.customStatement(
      "CREATE TEMP TRIGGER injected_131 BEFORE INSERT ON import_batch_metadata BEGIN SELECT RAISE(ABORT,'synthetic-131'); END",
    );
    final beforeFailure = await image(all: true);
    expect(await confirm(failing), isA<ImportRejected>());
    expect(await image(all: true), beforeFailure);
    await db.customStatement('DROP TRIGGER injected_131');
    expect(await confirm(failing), isA<ImportConfirmed>());
    expect(await image(), protected);
    debugPrint('MA-TSK-131: concurrencia y fallo tardío sin altas parciales.');
    final persisted = await image(all: true)
      ..remove('local_mutation');
    await store.close();
    db = await store.open();
    expect(
      await image(all: true)
        ..remove('local_mutation'),
      persisted,
    );
    expect(await image(), protected);
    debugPrint(
      'MA-TSK-131: fotos y presupuesto idénticos tras reapertura final.',
    );
  } finally {
    await store.close();
  }
}
