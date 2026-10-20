import 'dart:convert';

import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/app/import_factory.dart';
import 'package:myautofinance/features/importing/data/historical_csv_import_adapter.dart';
import 'package:myautofinance/features/importing/data/historical_csv_reader.dart';
import 'package:myautofinance/features/importing/data/sha256_import_fingerprint.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

import 'budget_proposal_reference_csv.dart';

/// T02: soporte exclusivo de pruebas, reutilizable en host y runner nativo.
/// El llamador entrega una SQLite nueva y aislada; nunca localiza instalaciones.
Future<ImportSession> seedIntegralReference(LocalDatabase db) async {
  for (final table in [
    'accounts',
    'categories',
    'movements',
    'budgets',
    'import_batches',
  ]) {
    if ((await db.customSelect('SELECT count(*) AS n FROM $table').getSingle())
            .read<int>('n') !=
        0) {
      throw StateError('T02 solo admite una base de ensayo nueva y vacía.');
    }
  }
  final file = ImportFile.fromBytes(
    bytes: utf8.encode(budgetProposalReferenceCsv),
    fingerprint: const Sha256ImportFingerprint(),
    source: ImportSource.historicalCsv,
    originalName: 'historico-ejemplo.csv',
  );
  final session = ImportSession(
    file: file,
    interpretation: await const HistoricalCsvImportAdapter().interpret(file),
  );
  final plans = <ImportCategoryReference, ImportNewCategory>{};
  for (final row in const HistoricalCsvReader().read(file.bytes).records) {
    for (var level = 0; level < row.categoryPath.length; level++) {
      final path = row.categoryPath.take(level + 1).toList();
      plans[ImportCategoryReference(path)] = ImportNewCategory(
        name: path.last,
        isIncome: level == 0 ? path.first == 'Ingresos' : null,
        parent: level == 0
            ? null
            : ImportCategoryTarget.proposed(
                ImportCategoryReference(path.take(level).toList()),
              ),
      );
    }
  }
  final services = createImportServices(db);
  final review = await services.previewer.preview(
    session,
    bindings: ImportReferenceBindings(
      newAccounts: {
        ImportAccountReference.named('Cuenta principal'): ImportNewAccount(
          name: 'Cuenta principal',
          activeFrom: Month(2026, 1),
          liquidity: Liquidity.liquid,
        ),
      },
      newCategories: plans,
    ),
  );
  final result = await services.confirmer.confirm(
    ImportConfirmationRequest(review: review),
  );
  if (result is! ImportConfirmed) {
    throw StateError('La base T02 debe estar vacía y el CSV debe ser válido.');
  }
  final accounts = SqliteAccountRepository(db);
  final photos = SqliteWealthRepository(db);
  final jan = Month(2026, 1);
  final main = (await accounts.list()).single;
  await photos.setValue(jan, main.id, 600000);
  for (final (name, kind, liquidity, cents) in [
    ('Cuenta de ahorro', AccountKind.account, Liquidity.liquid, 300000),
    ('Cartera', AccountKind.portfolio, Liquidity.medium, 1000000),
    ('Deuda familiar', AccountKind.debt, null, 500000),
  ]) {
    final account = await accounts.create(
      name: name,
      kind: kind,
      activeFrom: jan,
      liquidity: liquidity,
    );
    await photos.setValue(jan, account.id, cents);
  }
  return session;
}
