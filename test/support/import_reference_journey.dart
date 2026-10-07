import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/import_factory.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/data/sha256_import_fingerprint.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

import 'synthetic_import_adapter.dart';

/// Datos de los casos A/B/C/E de EP-001 expresados como fixture JSON.
/// No lee ni interpreta CSV: los futuros lectores tienen sus propios tickets.
Future<void> importReferenceJourney(Directory directory) async {
  final rows = <Map<String, Object?>>[];
  const branches = [
    ['Ingresos', 'Salario'],
    ['Vivienda', 'Alquiler'],
    ['Alimentación', 'Supermercado', 'Compra semanal'],
    ['Ahorro', 'Cuenta de ahorro'],
  ];
  const originalBudgets = [-300000, 100000, 40000, 50000];
  for (var month = 1; month <= 12; month++) {
    for (var branch = 0; branch < branches.length; branch++) {
      rows.add({
        'kind': 'PRESUPUESTO',
        'ordinal': rows.length + 2,
        'month': '2026-${month.toString().padLeft(2, '0')}',
        'concept': 'Presupuesto ${branches[branch].last}',
        'cents': originalBudgets[branch],
        'category': branches[branch],
      });
    }
  }
  const actuals = [
    ('2026-01-05', 'Nómina', 310000, 0),
    ('2026-01-06', 'Alquiler', -100000, 1),
    ('2026-01-07', 'Compra semanal', -35025, 2),
    ('2026-01-08', 'Transferencia a ahorro', -50000, 3),
    ('2026-01-09', 'Café', -1000, 4),
    ('2026-01-09', 'Café', -1000, 4),
    ('2026-02-05', 'Nómina', 302000, 0),
    ('2026-02-06', 'Alquiler', -100000, 1),
    ('2026-02-07', 'Compra semanal', -42010, 2),
    ('2026-02-08', 'Transferencia a ahorro', -50000, 3),
  ];
  for (final (date, concept, cents, branch) in actuals) {
    rows.add({
      'kind': 'REAL',
      'ordinal': rows.length + 2,
      'date': date,
      'concept': concept,
      'cents': cents,
      'account': 'Cuenta principal',
      'category': branch == 4 ? ['Ocio'] : branches[branch],
      'discretion': branch == 2 || branch == 4 ? 'Discrecional' : null,
    });
  }
  final file = ImportFile.fromBytes(
    bytes: utf8.encode(jsonEncode({'rows': rows})),
    fingerprint: const Sha256ImportFingerprint(),
    source: ImportSource.historicalCsv,
    originalName: 'referencia-ep001.json',
  );
  const adapter = SyntheticImportAdapter(ImportSource.historicalCsv);
  final session = ImportSession(
    file: file,
    interpretation: await adapter.interpret(file),
  );
  expect(session.isValid, isTrue);
  final categories = <ImportCategoryReference, ImportNewCategory>{};
  for (final row in session.interpretation.rows) {
    final reference = switch (row) {
      InterpretedMovement() => row.category!,
      InterpretedBudget() => row.category,
    };
    for (var depth = 1; depth <= reference.path.length; depth++) {
      final prefix = ImportCategoryReference(
        reference.path.take(depth).toList(),
      );
      categories[prefix] = ImportNewCategory(
        name: prefix.path.last,
        isIncome: depth == 1 ? prefix.path.first == 'Ingresos' : null,
        parent: depth == 1
            ? null
            : ImportCategoryTarget.proposed(
                ImportCategoryReference(
                  reference.path.take(depth - 1).toList(),
                ),
              ),
      );
    }
  }
  final bindings = ImportReferenceBindings(
    newAccounts: {
      ImportAccountReference.named('Cuenta principal'): ImportNewAccount(
        name: 'Cuenta principal',
        activeFrom: Month(2026, 1),
        liquidity: Liquidity.liquid,
      ),
    },
    newCategories: categories,
  );
  final store = LocalDatabaseStore(supportDirectory: () async => directory);
  try {
    var db = await store.open();
    var services = createImportServices(db);
    final before = await db.readState();
    final review = await services.previewer.preview(
      session,
      bindings: bindings,
    );
    expect(review.issues, isEmpty);
    expect(review.pendingReferences, isEmpty);
    expect(review.canRequestConfirmation, isTrue);
    expect((await db.readState()).revision, before.revision);
    for (final table in [
      'accounts',
      'categories',
      'import_batches',
      'movements',
      'budgets',
    ]) {
      expect(
        (await db.customSelect('SELECT count(*) AS n FROM $table').getSingle())
            .read<int>('n'),
        0,
      );
    }
    final result = await services.confirmer.confirm(
      ImportConfirmationRequest(review: review),
    );
    expect(result, isA<ImportConfirmed>());
    final batch = (result as ImportConfirmed).batch;
    expect(batch.movementCount, 10);
    expect(batch.budgetCount, 48);
    expect((await db.readState()).revision, before.revision + 1);
    await store.close();
    db = await store.open();
    services = createImportServices(db);
    final movements = SqliteMovementRepository(db);
    final january = await movements.readMonth(2026, 1);
    final february = await movements.readMonth(2026, 2);
    final annual = await movements.readYear(2026);
    expect(january.fold<int>(0, (n, r) => n + r.data.amountCents), 122975);
    expect(february.fold<int>(0, (n, r) => n + r.data.amountCents), 109990);
    expect(annual.fold<int>(0, (n, r) => n + r.data.amountCents), 232965);
    expect(january.where((r) => r.data.concept == 'Café'), hasLength(2));
    final budgets = SqliteBudgetRepository(db);
    var yearlyBudget = 0;
    for (var month = 1; month <= 12; month++) {
      final items = await budgets.list(BudgetMonth(2026, month));
      expect(items, hasLength(4));
      final sum = items.fold<int>(0, (n, r) => n + r.data.amountCents);
      expect(sum, 110000);
      yearlyBudget += sum;
    }
    expect(yearlyBudget, 1320000);
    expect((await services.history.listRows(batch.id)).items, hasLength(58));
    final repeatedReview = await services.previewer.preview(session);
    expect(
      await services.confirmer.confirm(
        ImportConfirmationRequest(review: repeatedReview),
      ),
      isA<ImportAlreadyImported>(),
    );
    expect((await db.readState()).revision, before.revision + 1);
  } finally {
    await store.close();
  }
}
