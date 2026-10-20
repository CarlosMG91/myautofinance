import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/budget_proposal_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/import_factory.dart';
import 'package:myautofinance/app/indicator_input_factory.dart';
import 'package:myautofinance/app/wealth_management_factory.dart';
import 'package:myautofinance/features/importing/data/historical_csv_import_adapter.dart';
import 'package:myautofinance/features/importing/data/sha256_import_fingerprint.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/indicators/indicators.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'support/budget_proposal_reference_csv.dart';
import 'support/integral_reference.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LocalDatabaseStore store;
  late LocalDatabase db;
  late ImportSession session;
  late Map<String, dynamic> oracle;
  final invalidation = CategoryReadInvalidation();
  setUp(() async {
    root = await Directory.systemTemp.createTemp('ep030-t02-');
    store = LocalDatabaseStore(supportDirectory: () async => root);
    db = await store.open();
    session = await seedIntegralReference(db);
    oracle = jsonDecode(
      await File('docs/ep-030/oraculos.json').readAsString(),
    ) as Map<String, dynamic>;
  });
  tearDown(() async {
    await store.close();
    await root.delete(recursive: true);
  });
  tearDownAll(invalidation.close);

  Future<int> scalar(String sql) async =>
      (await db.customSelect(sql).getSingle()).data.values.single as int;
  Future<String> indicator(int month) async {
    final result = (await createIndicatorSource(
      database: db,
      invalidation: invalidation,
    ).engine.evaluate('colchon_emergencia', Month(2026, month))).result;
    return result is CalculatedIndicator
        ? formatCalculatedIndicator(result)
        : (result as UnavailableIndicator).code;
  }

  test('Base CSV exacta, SQLite persistente, identidad/revisión y copia consistente', () async {
    final base = oracle['base'] as Map<String, dynamic>;
    expect(
      (await File(
        'docs/ep-001/historico-ejemplo.csv',
      ).readAsString()).replaceAll('\r\n', '\n'),
      budgetProposalReferenceCsv,
    );
    expect(
      sha256.convert(utf8.encode(budgetProposalReferenceCsv)).toString(),
      oracle['files']['base.csv'],
    );
    expect(await scalar('SELECT count(*) FROM movements'), base['movements']);
    expect(await scalar('SELECT count(*) FROM budgets'), base['budgets']);
    expect(
      await scalar(
        "SELECT sum(amount_cents) FROM movements WHERE value_date LIKE '2026-01-%'",
      ),
      base['januaryReal'],
    );
    expect(
      await scalar(
        "SELECT sum(amount_cents) FROM budgets WHERE month = '2026-01-01'",
      ),
      base['januaryBudget'],
    );
    expect(
      await scalar('SELECT sum(amount_cents) FROM movements'),
      base['annualReal'],
    );
    expect(
      await scalar('SELECT sum(amount_cents) FROM budgets'),
      base['annualBudget'],
    );
    final rows = await SqliteMovementRepository(db).readMonth(2026, 1);
    final cafes = rows.where((r) => r.data.concept == 'Café').toList();
    expect(cafes, hasLength(2));
    expect(cafes[0].id, isNot(cafes[1].id));
    expect(cafes.map((r) => r.data.discretion), everyElement('Discrecional'));
    final wealth = await createWealthManagement(database: db)
        .readMonth(Month(2026, 1));
    expect(wealth.liquidAssetsCents, base['januaryLiquidAssets']);
    expect(wealth.totals!.netWorthCents, base['januaryNetWorth']);
    expect(await indicator(1), base['januaryCushionDisplay']);
    final state = await db.readState();
    final services = createImportServices(db);
    expect(
      await services.confirmer.confirm(
        ImportConfirmationRequest(
          review: await services.previewer.preview(session),
        ),
      ),
      isA<ImportAlreadyImported>(),
    );
    final copy = await store.createConsistentBackup();
    expect(copy.state.datasetId, state.datasetId);
    expect(copy.state.revision, state.revision);
    final independent = sqlite.sqlite3.open(
      copy.path,
      mode: sqlite.OpenMode.readOnly,
    );
    try {
      for (final table in independent.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT GLOB 'sqlite_*' ORDER BY name",
      )) {
        final name = table['name'] as String;
        final sql = 'SELECT * FROM "$name" ORDER BY rowid';
        expect(
          independent
              .select(sql)
              .map((r) => Map<String, Object?>.from(r))
              .toList(),
          (await db.customSelect(sql).get()).map((r) => r.data).toList(),
          reason: name,
        );
      }
    } finally {
      independent.close();
    }
    await store.close();
    db = await store.open();
    expect((await db.readState()).datasetId, state.datasetId);
    expect((await db.readState()).revision, state.revision);
    expect(await scalar('SELECT count(*) FROM movements'), 10);
    expect(
      (await db.customSelect('PRAGMA integrity_check').getSingle())
          .data
          .values
          .single,
      'ok',
    );
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });

  test('Variantes de foto aisladas: ausencia, incompleta, cero y liquidez histórica', () async {
    final wealth = createWealthManagement(database: db);
    final accounts = {for (final a in await wealth.catalog()) a.name: a.id};
    final feb = Month(2026, 2);
    expect(await indicator(2), 'foto_ausente');
    await wealth.photos.setValue(feb, accounts['Cuenta principal']!, 620000);
    await wealth.photos.setValue(feb, accounts['Deuda familiar']!, 480000);
    expect(await indicator(2), 'foto_incompleta');
    expect(
      (await wealth.readMonth(feb)).pending.map((a) => a.name),
      unorderedEquals(['Cuenta de ahorro', 'Cartera']),
    );
    await wealth.photos.setValue(feb, accounts['Cuenta de ahorro']!, 0);
    await wealth.photos.setValue(feb, accounts['Cartera']!, 1050000);
    expect((await wealth.readMonth(feb)).totals!.netWorthCents, 1190000);
    expect(await indicator(2), '2,07 meses');
    await wealth.changeLiquidity(accounts['Cartera']!, feb, Liquidity.liquid);
    expect(await indicator(2), '5,57 meses');
    expect(await indicator(1), '3,00 meses');
  });

  test(
    'Propuesta 2027 por mes equivalente y periodos vacíos sin guardar',
    () async {
      final before = await db.readState();
      final proposal = await createBudgetProposalCalculator(
        database: db,
        invalidation: invalidation,
      ).calculate(2026);
      final expected = (oracle['variants'] as List).singleWhere(
        (v) => v['id'] == 'V08',
      );
      expect(proposal.allocations, hasLength(expected['allocations'] as int));
      for (final row in proposal.sourceRows) {
        final month = row.targetMonth.value;
        expect(
          row.proposedAmountCents,
          month == '2027-01-01'
              ? expected['january'][row.categoryPath]
              : month == '2027-02-01'
              ? expected['february'][row.categoryPath]
              : 0,
        );
      }
      expect(await SqliteBudgetRepository(db).readYear(2027), isEmpty);
      expect(await SqliteMovementRepository(db).readYear(2027), isEmpty);
      expect(await SqliteMovementRepository(db).readMonth(2026, 3), isEmpty);
      expect(await SqliteMovementRepository(db).readMonth(2026, 12), isEmpty);
      expect(
        await scalar(
          "SELECT sum(amount_cents) FROM budgets WHERE month = '2026-12-01'",
        ),
        110000,
      );
      expect((await db.readState()).revision, before.revision);
    },
  );

  for (final name in [
    'categoria-pendiente.csv',
    'cuenta-sin-resolver.csv',
    'padre-incompatible.csv',
  ]) {
    test('Variante independiente: $name', () async {
      final package = Directory('${root.path}/inputs');
      final process = await Process.run('node', [
        'docs/ep-030/preparar-datos.mjs',
        '--destino',
        package.path,
      ]);
      expect(process.exitCode, 0, reason: '${process.stdout}${process.stderr}');
      final services = createImportServices(db);
      final file = ImportFile.fromBytes(
        bytes: await File('${package.path}/$name').readAsBytes(),
        fingerprint: const Sha256ImportFingerprint(),
        source: ImportSource.historicalCsv,
        originalName: name,
      );
      final variant = ImportSession(
        file: file,
        interpretation: await const HistoricalCsvImportAdapter().interpret(
          file,
        ),
      );
      final before = await db.readState();
      final review = await services.previewer.preview(variant);
      if (name == 'categoria-pendiente.csv') {
        expect(review.canRequestConfirmation, isTrue);
        expect(
          await services.confirmer.confirm(
            ImportConfirmationRequest(review: review),
          ),
          isA<ImportConfirmed>(),
        );
        expect(
          await scalar(
            'SELECT sum(amount_cents) FROM movements WHERE category_id IS NULL',
          ),
          400,
        );
      } else {
        expect(review.canRequestConfirmation, isFalse);
        expect((await db.readState()).revision, before.revision);
      }
      expect(
        await scalar('SELECT count(*) FROM movements'),
        name == 'categoria-pendiente.csv' ? 12 : 10,
      );
      expect(await scalar('SELECT count(*) FROM budgets'), 48);
      // Volver a preparar nunca sobrescribe una carpeta anterior.
      expect(
        (await Process.run('node', [
          'docs/ep-030/preparar-datos.mjs',
          '--destino',
          package.path,
        ])).exitCode,
        isNot(0),
      );
    });
  }

  for (final mode in ['incompleto', 'nulo', 'liquidos-cero']) {
    test('Variante independiente de indicador: $mode', () async {
      final budgets = SqliteBudgetRepository(db);
      final salary = await budgets.readYear(2026, incomeOnly: true);
      if (mode == 'incompleto') {
        await budgets.delete(
          salary.singleWhere((b) => b.data.month.value == '2026-03-01').id,
        );
        expect(await indicator(1), 'ingresos_incompletos');
      } else if (mode == 'nulo') {
        for (final row in salary) {
          await budgets.edit(
            row.id,
            BudgetInput(
              month: row.data.month,
              categoryId: row.data.categoryId,
              amountCents: 0,
              concept: row.data.concept,
              discretion: row.data.discretion,
            ),
          );
        }
        expect(await indicator(1), 'ingresos_nulos');
      } else {
        final wealth = createWealthManagement(database: db);
        for (final a in await wealth.catalog()) {
          if (a.name == 'Cuenta principal' || a.name == 'Cuenta de ahorro') {
            await wealth.photos.setValue(Month(2026, 1), a.id, 0);
          }
        }
        expect(await indicator(1), '0,00 meses');
        expect(
          (await wealth.readMonth(Month(2026, 1))).totals!.netWorthCents,
          500000,
        );
      }
    });
  }
}
