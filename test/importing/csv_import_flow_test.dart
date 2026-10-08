import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/csv_import_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/import_factory.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/importing/presentation/import_controller.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

const header =
    'fecha;concepto;importe_eur;tipo;categoria;subcategoria;subsubcategoria;cuenta_origen;discrecionalidad';
const validCsv =
    '$header\n2026-01-03;Café;-2.50;REAL;;;;Cuenta;\n2026-01-01;Presupuesto;40.00;PRESUPUESTO;Ocio;;;;\n';

LocalCsvSelected csv(String content, [String name = 'histórico.csv']) =>
    LocalCsvSelected(
      name: name,
      bytes: Uint8List.fromList(utf8.encode(content)),
    );

class QueueCsvSelector implements LocalCsvSelector {
  final pending = <Future<LocalCsvSelection>>[];
  int calls = 0;
  @override
  Future<LocalCsvSelection> select() {
    calls++;
    return pending.removeAt(0);
  }

  void add(LocalCsvSelection value) => pending.add(Future.value(value));
}

Future<void> resolveCsv(ImportController c) async {
  await c.bindAccount(
    ImportAccountReference.named('Cuenta'),
    plan: ImportNewAccount(
      name: 'Cuenta',
      activeFrom: Month(2026, 1),
      liquidity: Liquidity.liquid,
    ),
  );
  await c.bindCategory(
    ImportCategoryReference(['Ocio']),
    plan: const ImportNewCategory(name: 'Ocio', isIncome: false),
  );
}

class DelayedCsvAdapter implements ImportAdapter {
  final entered = Completer<void>();
  final gate = Completer<ImportInterpretation>();
  int calls = 0;
  @override
  ImportSource get source => ImportSource.historicalCsv;
  @override
  Future<ImportInterpretation> interpret(ImportFile file) {
    if (calls++ == 0) {
      entered.complete();
      return gate.future;
    }
    return const BackgroundHistoricalCsvAdapter().interpret(file);
  }
}

void main() {
  late LocalDatabase db;
  late ImportServices services;
  late QueueCsvSelector selector;
  late ImportController c;
  setUp(() {
    db = LocalDatabase(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys=ON'),
      ),
    );
    services = createImportServices(db);
    selector = QueueCsvSelector();
    c = createCsvImportController(() async => services, selector: selector);
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> select({bool replace = true}) =>
      c.selectCsv(approveReplacement: () async => replace);
  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
          .read<int>('n');

  test('CSV real mixto: revisión sin escrituras, signo único, SQLite, historial y repetición renombrada', () async {
    selector.add(csv(validCsv));
    await select();
    expect(c.phase, ImportPhase.review);
    expect(c.review!.movementCount, 1);
    expect(c.review!.budgetCount, 1);
    expect(
      c.review!.totalCents(budgets: true, original: true),
      BigInt.from(4000),
    );
    expect(
      c.review!.totalCents(budgets: true, original: false),
      BigInt.from(-4000),
    );
    expect(await count('import_batches'), 0);
    await resolveCsv(c);
    expect(c.canConfirm, isTrue);
    expect(await count('accounts'), 0);
    await c.confirm();
    expect(c.phase, ImportPhase.imported);
    final batch = (c.result as ImportConfirmed).batch;
    expect((await services.history.listRows(batch.id)).items.length, 2);
    expect(
      (await db.customSelect('SELECT amount_cents FROM budgets').getSingle())
          .read<int>('amount_cents'),
      -4000,
    );
    selector.add(csv(validCsv, 'renombrado.csv'));
    await select();
    expect(c.phase, ImportPhase.alreadyImported);
    expect((c.result as ImportAlreadyImported).batch.id, batch.id);
    expect(c.canConfirm, isFalse);
    expect(await count('import_batches'), 1);
    expect(await count('movements'), 1);
    expect(await count('budgets'), 1);
  });

  test('Cancelación, lectura fallida y descarte rechazado conservan bytes y decisiones', () async {
    selector.add(csv(validCsv));
    await select();
    await resolveCsv(c);
    final session = c.session, bindings = c.review!.bindings;
    for (final value in [
      const LocalCsvCancelled(),
      const LocalCsvFailed(LocalCsvFailureCode.accessDenied),
      const LocalCsvFailed(LocalCsvFailureCode.unavailable),
    ]) {
      selector.add(value);
      await select();
      expect(c.session, same(session));
      expect(c.review!.bindings, same(bindings));
      expect(c.canConfirm, isTrue);
    }
    selector.add(csv('$header\n'));
    await select(replace: false);
    expect(c.session, same(session));
    expect(c.review!.bindings, same(bindings));
    expect(await count('import_batches'), 0);
  });

  test('Reemplazo recalcula huella y elimina decisiones y marcas; todos los errores bloquean', () async {
    selector.add(csv(validCsv));
    await select();
    await resolveCsv(c);
    final digest = c.session!.file.sha256;
    c.reviewedOverlaps.add('viejo');
    selector.add(csv('$header\n2026-02-30;;0.00;REAL;;;;;\n'));
    await select();
    expect(c.session!.file.sha256, isNot(digest));
    expect(c.reviewedOverlaps, isEmpty);
    expect(c.review!.bindings.newAccounts, isEmpty);
    expect(c.session!.interpretation.rows, isEmpty);
    expect(c.review!.issues.length, greaterThan(2));
    expect(
      c.review!.issues.any((i) => i.field == 'fecha' && i.sourceOrdinal == 2),
      isTrue,
    );
    expect(c.canConfirm, isFalse);
    await c.confirm();
    expect(await count('import_batches'), 0);
  });

  test('Resultados tardíos de selector cancelado y preparación reemplazada no pisan la nueva sesión', () async {
    final lateSelection = Completer<LocalCsvSelection>();
    selector.pending.add(lateSelection.future);
    final old = select();
    c.cancelSelection();
    selector.add(csv(validCsv));
    await select();
    final session = c.session;
    lateSelection.complete(csv('incorrecto'));
    await old;
    expect(c.session, same(session));
    c.dispose();
    final lateFile = Completer<ImportFile>();
    var preparations = 0;
    c = ImportController(
      () async => services,
      csvSelector: selector,
      csvAdapter: const BackgroundHistoricalCsvAdapter(),
      prepareCsv: (s) =>
          preparations++ == 0 ? lateFile.future : prepareHistoricalCsvFile(s),
    );
    selector.add(csv('incorrecto'));
    final preparing = select();
    await Future<void>.delayed(Duration.zero);
    selector.add(csv(validCsv));
    await select();
    final current = c.session;
    lateFile.complete(await prepareHistoricalCsvFile(csv('incorrecto')));
    await preparing;
    expect(c.session, same(current));
    expect(c.phase, ImportPhase.review);
  });

  test(
    'Parseo y lectura SQLite tardíos no mezclan sesiones reemplazadas',
    () async {
      c.dispose();
      final adapter = DelayedCsvAdapter();
      c = ImportController(
        () async => services,
        csvSelector: selector,
        prepareCsv: prepareHistoricalCsvFile,
        csvAdapter: adapter,
      );
      selector.add(csv('incorrecto'));
      final parsing = select();
      await adapter.entered.future;
      selector.add(csv(validCsv));
      await select();
      final session = c.session;
      adapter.gate.complete(
        ImportInterpretation(
          formatVersion: '1',
          issues: const [
            ImportIssue(code: ImportIssueCode.invalidFile, reason: 'viejo'),
          ],
        ),
      );
      await parsing;
      expect(c.session, same(session));
      expect(c.phase, ImportPhase.review);
      c.dispose();
      final entered = Completer<void>();
      final oldServices = Completer<ImportServices>();
      var loads = 0;
      c = createCsvImportController(() {
        if (loads++ == 0) {
          entered.complete();
          return oldServices.future;
        }
        return Future.value(services);
      }, selector: selector);
      selector.add(csv('$header\n'));
      final reading = select();
      await entered.future;
      selector.add(csv(validCsv));
      await select();
      final current = c.session;
      oldServices.complete(services);
      await reading;
      expect(c.session, same(current));
      expect(c.review!.session, same(current));
      expect(c.phase, ImportPhase.review);
      expect(await count('import_batches'), 0);
    },
  );

  test(
    'Los diagnósticos CSV siguen accesibles aunque falle la lectura SQLite',
    () async {
      c.dispose();
      c = createCsvImportController(
        () async => throw StateError('synthetic read failure'),
        selector: selector,
      );
      selector.add(csv('$header\n2026-02-30;;0.00;REAL;;;;;\n'));
      await select();
      expect(c.phase, ImportPhase.error);
      expect(c.review!.issues, containsAll(c.session!.issues));
      expect(c.review!.issues.any((i) => i.field == 'fecha'), isTrue);
      expect(c.canConfirm, isFalse);
      expect(await count('import_batches'), 0);
    },
  );

  test('Confirmación revalida y fallo SQLite conserva sesión sin altas parciales; reintento y doble envío', () async {
    selector.add(csv(validCsv));
    await select();
    await resolveCsv(c);
    await db.customStatement(
      "CREATE TRIGGER fail_import BEFORE INSERT ON movements BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
    );
    final session = c.session;
    await Future.wait([c.confirm(), c.confirm()]);
    expect(c.phase, ImportPhase.error);
    expect(c.session, same(session));
    expect(await count('accounts'), 0);
    expect(await count('import_batches'), 0);
    expect(await count('categories'), 0);
    expect(await count('budgets'), 0);
    await db.customStatement('DROP TRIGGER fail_import');
    await Future.wait([c.confirm(), c.confirm()]);
    expect(c.phase, ImportPhase.imported);
    expect(await count('import_batches'), 1);
  });

  test('Otro archivo solapado exige revisar cada aviso antes de conservar los dos reales', () async {
    final realOnly = '$header\n2026-01-03;Café;-2.50;REAL;;;;Cuenta;\n';
    selector.add(csv(realOnly));
    await select();
    await c.bindAccount(
      ImportAccountReference.named('Cuenta'),
      plan: ImportNewAccount(
        name: 'Cuenta',
        activeFrom: Month(2026, 1),
        liquidity: Liquidity.liquid,
      ),
    );
    await c.confirm();
    selector.add(csv(realOnly.replaceAll('\n', '\r\n')));
    await select();
    expect(c.review!.overlaps.length, 1);
    expect(c.canConfirm, isFalse);
    c.markOverlap(c.review!.overlaps.single.key, true);
    expect(c.canConfirm, isTrue);
    await c.confirm();
    expect(await count('movements'), 2);
  });
}
