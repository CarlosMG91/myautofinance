import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_history_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_preview_source.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/importing/data/historical_csv_import_adapter.dart';
import 'package:myautofinance/features/importing/data/historical_csv_reader.dart';
import 'package:myautofinance/features/importing/data/sha256_import_fingerprint.dart';
import 'package:myautofinance/features/importing/historical_csv.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

import 'import_preview_test.dart' as fixture;

const ImportAdapter _adapter = HistoricalCsvImportAdapter();
final _header = historicalCsvColumns.join(';');
const _real = '2026-01-03;Café;-10.00;REAL;Ocio;;;Cuenta principal;';
const _budget = '2026-01-01;Presupuesto;100.00;PRESUPUESTO;Ocio;;;;';

ImportFile _file(
  List<int> bytes, {
  String name = 'historico.csv',
  ImportSource source = ImportSource.historicalCsv,
}) => ImportFile.fromBytes(
  bytes: bytes,
  fingerprint: const Sha256ImportFingerprint(),
  source: source,
  originalName: name,
);

Future<ImportSession> _session(String records) =>
    _fromFile(_file(utf8.encode('$_header\n$records')));

Future<ImportSession> _fromFile(ImportFile file) async =>
    ImportSession(file: file, interpretation: await _adapter.interpret(file));

Future<ImportSession> _template() => _fromFile(
  _file(File('docs/ep-001/historico-ejemplo.csv').readAsBytesSync()),
);

void _blocked(ImportReview review) {
  expect(review.canRequestConfirmation, isFalse);
  expect(() => ImportConfirmationRequest(review: review), throwsStateError);
}

ImportReferenceBindings _templatePlans(ImportSession session) {
  final categories = <ImportCategoryReference, ImportNewCategory>{};
  for (final row in session.interpretation.rows) {
    final category = switch (row) {
      InterpretedMovement() => row.category,
      InterpretedBudget() => row.category,
    };
    if (category == null) continue;
    for (var depth = 1; depth <= category.path.length; depth++) {
      final reference = ImportCategoryReference(
        category.path.take(depth).toList(),
      );
      categories[reference] = ImportNewCategory(
        name: reference.path.last,
        parent: depth == 1
            ? null
            : ImportCategoryTarget.proposed(
                ImportCategoryReference(category.path.take(depth - 1).toList()),
              ),
        // Elección explícita de los casos de referencia, nunca por importe.
        isIncome: depth == 1 ? reference.path.first == 'Ingresos' : null,
      );
    }
  }
  return ImportReferenceBindings(
    newAccounts: {
      ImportAccountReference.named('Cuenta principal'): ImportNewAccount(
        name: 'Cuenta principal',
        activeFrom: Month(2026, 1),
        liquidity: Liquidity.liquid,
      ),
    },
    newCategories: categories,
  );
}

void main() {
  test(
    'Plantilla: versiones, conteos, totales CSV/internos y ordinales',
    () async {
      final session = await _template();
      expect(_adapter.source, ImportSource.historicalCsv);
      expect(session.file.source, _adapter.source);
      expect(session.interpretation.formatVersion, '1');
      expect(session.interpretation.contractVersion, importContractVersion);
      expect(session.isValid, isTrue);
      final review = ImportReview(session: session);
      expect(review.movementCount, 10);
      expect(review.budgetCount, 48);
      for (final original in [true, false]) {
        expect(
          review.totalCents(budgets: false, original: original),
          BigInt.from(232965),
        );
        expect(
          review.totalCents(budgets: true, original: original),
          BigInt.from(original ? -1320000 : 1320000),
        );
      }
      final rows = session.interpretation.rows;
      expect(rows.map((r) => r.sourceOrdinal), List.generate(58, (i) => i + 2));
      final coffees = rows.whereType<InterpretedMovement>().where(
        (r) => r.concept == 'Café',
      );
      expect(coffees.map((r) => r.sourceOrdinal), [54, 55]);
      expect(coffees.map((r) => r.amount.internalCents), [-1000, -1000]);
      expect(
        rows
            .whereType<InterpretedMovement>()
            .where((r) => r.valueDate.value.startsWith('2026-01'))
            .fold(0, (sum, r) => sum + r.amount.internalCents),
        122975,
      );
      _blocked(review); // Solo interpretar no resuelve referencias.
    },
  );

  for (final entry in [
    ('REAL', '-12.50', -1250, -1250),
    ('REAL', '12.50', 1250, 1250),
    ('PRESUPUESTO', '-12.50', -1250, 1250),
    ('PRESUPUESTO', '12.50', 1250, -1250),
    ('PRESUPUESTO', '0.00', 0, 0),
    ('PRESUPUESTO', '-0.00', 0, 0),
  ]) {
    test(
      '${entry.$1} ${entry.$2}: signo único hasta la entrada del repositorio',
      () async {
        final account = entry.$1 == 'REAL' ? 'Cuenta principal' : '';
        final session = await _session(
          '2026-01-01;Concepto;${entry.$2};${entry.$1};Ocio;;;$account;',
        );
        expect(session.isValid, isTrue);
        final row = session.interpretation.rows.single;
        expect(row.amount.originalCents, entry.$3);
        expect(row.amount.internalCents, entry.$4);
        expect(row.originalFields[2].value, entry.$2);
        final amount = switch (row) {
          InterpretedMovement() =>
            row
                .toMovementInput(accountId: 'account', categoryId: 'category')
                .amountCents,
          InterpretedBudget() =>
            row.toBudgetInput(categoryId: 'category').amountCents,
        };
        expect(amount, entry.$4);
        // Volver a interpretar no invierte un importe interno anterior.
        expect(
          (await _adapter.interpret(session.file))
              .rows
              .single
              .amount
              .internalCents,
          amount,
        );
      },
    );
  }

  test(
    'Valores tratados y originales, multilínea, ruta completa y Sin clasificar',
    () async {
      final session = await _session(
        '2026-01-03;"  Compra; ""semanal""\r\nsegunda línea  ";-012.50; real ; Alimentación ; Supermercado ; Compra semanal ; Cuenta principal ;  Discrecional  \n'
        '2026-01-03;Sin clasificar;1.00;REAL;;;;Cuenta principal;\n'
        '2026-01-01;  Plan  ;-0.00; presupuesto ;Ocio;;;;  Legado  ',
      );
      expect(session.isValid, isTrue);
      final row = session.interpretation.rows.first as InterpretedMovement;
      expect(row.sourceOrdinal, 2);
      expect(row.valueDate.value, '2026-01-03');
      expect(row.concept, 'Compra; "semanal"\r\nsegunda línea');
      expect(row.discretion, 'Discrecional');
      expect(row.account.name, 'Cuenta principal');
      expect(row.category!.path, [
        'Alimentación',
        'Supermercado',
        'Compra semanal',
      ]);
      expect(row.originalFields.map((f) => f.name), historicalCsvColumns);
      expect(
        row.originalFields[1].value,
        '  Compra; "semanal"\r\nsegunda línea  ',
      );
      expect(row.originalFields[2].value, '-012.50');
      expect(row.originalFields[7].value, ' Cuenta principal ');
      expect(row.originalFields[8].value, '  Discrecional  ');
      final unclassified =
          session.interpretation.rows[1] as InterpretedMovement;
      expect(unclassified.sourceOrdinal, 3); // No es la línea física 4.
      expect(unclassified.category, isNull);
      expect(unclassified.discretion, '');
      expect(unclassified.toMovementInput(accountId: 'a').categoryId, isNull);
      final budget = session.interpretation.rows.last as InterpretedBudget;
      expect(budget.sourceOrdinal, 4);
      expect(budget.month.value, '2026-01-01');
      expect(budget.concept, 'Plan');
      expect(budget.discretion, 'Legado');
      expect(budget.originalFields[7].value, '');
      expect(() => row.originalFields.clear(), throwsUnsupportedError);
    },
  );

  test('Totales BigInt fuera de int64, sin perder céntimos', () async {
    final session = await _session(
      '2026-01-01;Máximo;92233720368547758.07;REAL;;;;Cuenta principal;\n'
      '2026-01-01;Máximo;92233720368547758.07;REAL;;;;Cuenta principal;\n'
      '2026-01-01;Máximo;-92233720368547758.07;PRESUPUESTO;Ocio;;;;\n'
      '2026-02-01;Máximo;-92233720368547758.07;PRESUPUESTO;Ocio;;;;',
    );
    expect(session.isValid, isTrue);
    final review = ImportReview(session: session);
    final total = BigInt.parse('18446744073709551614');
    expect(review.totalCents(budgets: false, original: true), total);
    expect(review.totalCents(budgets: false, original: false), total);
    expect(review.totalCents(budgets: true, original: true), -total);
    expect(review.totalCents(budgets: true, original: false), total);
    final minimum = await _session(
      '0001-01-01;Mínimo;-92233720368547758.08;REAL;;;;Cuenta principal;',
    );
    expect(minimum.isValid, isTrue);
    expect(
      minimum.interpretation.rows.single.amount.internalCents,
      -9223372036854775808,
    );
  });

  final invalidFiles = <String, List<int>>{
    'UTF-8': [0xff],
    'cabecera': utf8.encode('Fecha${_header.substring(5)}\n$_real'),
    'columnas': utf8.encode('$_header\n$_real;extra'),
    'comillas': utf8.encode('$_header\n2026-01-03;"abierto'),
    'CR aislado': utf8.encode('$_header\r$_real'),
    'fila vacía': utf8.encode('$_header\n$_real\n\n'),
    'campos y registros': utf8.encode(
      '$_header\n$_real\n'
      '2026-02-30; ;0.00;REAL;;Hija;; ;\n'
      '2026-01-15;Plan;1,00;PRESUPUESTO;;;;Cuenta;',
    ),
    'presupuesto int64 mínimo': utf8.encode(
      '$_header\n2026-01-01;Plan;-92233720368547758.08;PRESUPUESTO;Ocio;;;;',
    ),
  };
  for (final entry in invalidFiles.entries) {
    test('Errores de ${entry.key}: conserva todos los diagnósticos y bloquea el lote', () async {
      final diagnostics = const HistoricalCsvReader()
          .read(entry.value)
          .diagnostics;
      expect(diagnostics, isNotEmpty);
      final session = await _fromFile(_file(entry.value));
      final interpretation = session.interpretation;
      expect(interpretation.rows, isEmpty);
      expect(interpretation.issues, hasLength(diagnostics.length));
      for (var i = 0; i < diagnostics.length; i++) {
        final issue = interpretation.issues[i];
        expect(issue.sourceOrdinal, diagnostics[i].sourceOrdinal);
        expect(issue.field, diagnostics[i].field);
        final diagnostic = diagnostics[i];
        expect(
          issue.reason,
          '${diagnostic.reason}'
          '${diagnostic.physicalLine == null ? '' : ' · línea física ${diagnostic.physicalLine}'}'
          '${diagnostic.byteOffset == null ? '' : ' · byte ${diagnostic.byteOffset}'}',
        );
        expect(
          issue.code,
          entry.key == 'campos y registros' ||
                  entry.key == 'presupuesto int64 mínimo'
              ? ImportIssueCode.invalidField
              : ImportIssueCode.invalidFile,
        );
      }
      _blocked(ImportReview(session: session));
    });
  }

  test('Origen ajeno y cabecera sin registros son errores de lote', () async {
    final foreign = await _fromFile(
      _file(utf8.encode('$_header\n$_real'), source: ImportSource.bankXls),
    );
    expect(foreign.interpretation.rows, isEmpty);
    expect(
      foreign.interpretation.issues.single.code,
      ImportIssueCode.invalidFile,
    );
    _blocked(ImportReview(session: foreign));
    final empty = await _session('');
    expect(empty.interpretation.issues, isEmpty);
    expect(empty.issues.single.code, ImportIssueCode.emptyBatch);
    _blocked(ImportReview(session: empty));
  });

  test(
    'SHA sobre bytes originales: nombre, BOM y saltos no se normalizan',
    () async {
      final bytes = utf8.encode('$_header\n$_real');
      final plain = _file(bytes);
      final renamed = _file(bytes, name: 'renombrado.csv');
      final bom = _file([0xef, 0xbb, 0xbf, ...bytes]);
      final crlf = _file(utf8.encode('$_header\r\n$_real'));
      for (final file in [plain, renamed, bom, crlf]) {
        final before = file.sha256;
        expect((await _fromFile(file)).isValid, isTrue);
        expect(file.sha256, before);
        expect(
          file.matchesFingerprint(const Sha256ImportFingerprint()),
          isTrue,
        );
      }
      expect(plain.bytes, bytes);
      expect(plain.sha256, renamed.sha256);
      expect(plain.sha256, isNot(bom.sha256));
      expect(plain.sha256, isNot(crlf.sha256));
    },
  );

  test('Ambigüedades y asignación para todas las filas las resuelve EP-012', () async {
    final session = await _session(
      '$_real\n${_real.replaceAll('Ocio', ' ocio ').replaceAll('Cuenta principal', ' CUENTA PRINCIPAL ')}',
    );
    final previewer = ValidatingImportPreviewer(
      fixture.FixtureSource(
        fixture.snapshot(
          accounts: [
            fixture.account(id: 'a', name: 'Cuenta principal'),
            fixture.account(id: 'b', name: 'cuenta principal'),
          ],
          categories: [
            fixture.node('c', name: 'Ocio'),
            fixture.node('d', name: 'ocio'),
          ],
        ),
      ),
    );
    final pending = await previewer.preview(session);
    _blocked(pending);
    expect(pending.pendingReferences, hasLength(2));
    for (final reference in pending.pendingReferences) {
      expect(reference.sourceOrdinals, [2, 3]);
      expect(reference.candidateIds, hasLength(2));
    }
    final resolved = await previewer.preview(
      session,
      bindings: ImportReferenceBindings(
        accounts: {ImportAccountReference.named(' cuenta principal '): 'b'},
        categories: {
          ImportCategoryReference(['OCIO']): 'd',
        },
      ),
    );
    expect(resolved.canRequestConfirmation, isTrue);
    for (final row in session.interpretation.rows.cast<InterpretedMovement>()) {
      expect(resolved.bindings.accounts[row.account], 'b');
      expect(resolved.bindings.categories[row.category], 'd');
    }
  });

  group('Integración del CSV con SQLite y servicios reales EP-012', () {
    late LocalDatabase db;
    late ValidatingImportPreviewer previewer;
    late SqliteImportBatchRepository confirmer;
    setUp(() async {
      db = LocalDatabase(
        NativeDatabase.memory(
          setup: (raw) => raw.execute('PRAGMA foreign_keys=ON'),
        ),
      );
      await db.readState();
      previewer = ValidatingImportPreviewer(SqliteImportPreviewSource(db));
      confirmer = SqliteImportBatchRepository(db);
    });
    tearDown(() => db.close());

    Future<Map<String, Object?>> image() async {
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
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
              .map((r) => r.data)
              .toList(),
      };
    }

    Future<ImportConfirmed> importTemplate() async {
      final session = await _template();
      final review = await previewer.preview(
        session,
        bindings: _templatePlans(session),
      );
      expect(review.issues, isEmpty);
      expect(review.pendingReferences, isEmpty);
      return await confirmer.confirm(ImportConfirmationRequest(review: review))
          as ImportConfirmed;
    }

    test('Plantilla: altas aprobadas, una transacción, historial y repetición renombrada', () async {
      final session = await _template();
      final before = await image();
      final pending = await previewer.preview(session);
      _blocked(pending);
      expect(pending.pendingReferences, isNotEmpty);
      final review = await previewer.preview(
        session,
        bindings: _templatePlans(session),
      );
      expect(review.canRequestConfirmation, isTrue);
      expect(await image(), before);
      final revision = (await db.readState()).revision;
      final result = await confirmer.confirm(
        ImportConfirmationRequest(review: review),
      ) as ImportConfirmed;
      expect(result.movementCount, 10);
      expect(result.budgetCount, 48);
      expect(result.batch.source, ImportSource.historicalCsv);
      expect(result.batch.formatVersion, '1');
      expect(result.batch.sha256, session.file.sha256);
      expect((await db.readState()).revision, revision + 1);
      final movements = await SqliteMovementRepository(db).readYear(2026);
      expect(movements.fold(0, (sum, r) => sum + r.data.amountCents), 232965);
      expect(
        movements
            .where((r) => r.data.concept == 'Café')
            .map((r) => r.sourceOrdinal),
        unorderedEquals([54, 55]),
      );
      final budgets = [
        for (var month = 1; month <= 12; month++)
          ...await SqliteBudgetRepository(db).list(BudgetMonth(2026, month)),
      ];
      expect(budgets, hasLength(48));
      expect(budgets.fold(0, (sum, r) => sum + r.data.amountCents), 1320000);
      final history = await SqliteImportHistoryRepository(db)
          .listRows(result.batch.id);
      expect(history.items, hasLength(58));
      for (var i = 0; i < history.items.length; i++) {
        final original = history.items[i].original!;
        final input = session.interpretation.rows[i];
        expect(original.sourceOrdinal, input.sourceOrdinal);
        expect(
          original.originalFields.map((f) => (f.name, f.value)),
          input.originalFields.map((f) => (f.name, f.value)),
        );
        expect(original.concept, input.concept);
        expect(original.discretion, input.discretion);
        expect(original.amount.originalCents, input.amount.originalCents);
        expect(original.amount.internalCents, input.amount.internalCents);
      }
      final after = await image();
      final renamed = await _fromFile(
        _file(session.file.bytes, name: 'otra-copia.csv'),
      );
      final again = await confirmer.confirm(
        ImportConfirmationRequest(review: await previewer.preview(renamed)),
      );
      expect(again, isA<ImportAlreadyImported>());
      expect((again as ImportAlreadyImported).batch.id, result.batch.id);
      expect(await image(), after);
    });

    test(
      'Archivo mixto inválido no admite confirmación parcial ni altera la base',
      () async {
        final before = await image();
        final session = await _session(
          '$_real\n$_budget\n2026-02-30;Error;1.00;REAL;;;;Cuenta principal;',
        );
        final review = await previewer.preview(session);
        _blocked(review);
        expect(
          review.issues.any((i) => i.sourceOrdinal == 4 && i.field == 'fecha'),
          isTrue,
        );
        expect(session.interpretation.rows, isEmpty);
        expect(await image(), before);
      },
    );

    for (final record in [
      '2026-01-01;Plan;0.00;PRESUPUESTO;Vivienda;;;;',
      '2026-01-01;Plan;0.00;PRESUPUESTO;Vivienda;Alquiler;;;',
    ]) {
      test('Conflicto presupuestario resuelto por núcleo: $record', () async {
        await importTemplate();
        final before = await image();
        final review = await previewer.preview(await _session(record));
        _blocked(review);
        expect(
          review.issues.any((i) => i.code == ImportIssueCode.budgetConflict),
          isTrue,
        );
        expect(await image(), before);
      });
    }

    test(
      'Un padre y su descendiente pasan el lector y se rechazan tras asignar',
      () async {
        final session = await _session(
          '$_budget\n2026-01-01;Plan;0.00;PRESUPUESTO;Ocio;Cine;;;',
        );
        expect(session.isValid, isTrue);
        final parent = ImportCategoryReference(['Ocio']);
        final child = ImportCategoryReference(['Ocio', 'Cine']);
        final review = await previewer.preview(
          session,
          bindings: ImportReferenceBindings(
            newCategories: {
              parent: const ImportNewCategory(name: 'Ocio', isIncome: false),
              child: ImportNewCategory(
                name: 'Cine',
                parent: ImportCategoryTarget.proposed(parent),
              ),
            },
          ),
        );
        _blocked(review);
        expect(
          review.issues
              .where((i) => i.code == ImportIssueCode.budgetConflict)
              .map((i) => i.sourceOrdinal),
          [2, 3],
        );
      },
    );

    test('Bytes distintos exigen revisión de cada solapamiento y conservan los duplicados', () async {
      await importTemplate();
      final coffee = _real.replaceFirst('2026-01-03', '2026-01-09');
      final session = await _session('$coffee\n$coffee');
      final review = await previewer.preview(session);
      expect(
        review.overlaps,
        hasLength(4),
      ); // Dos filas por dos Café existentes.
      expect(() => ImportConfirmationRequest(review: review), throwsStateError);
      expect(
        () => ImportConfirmationRequest(
          review: review,
          reviewedOverlapKeys: {review.overlaps.first.key},
        ),
        throwsStateError,
      );
      final result = await confirmer.confirm(
        ImportConfirmationRequest(
          review: review,
          reviewedOverlapKeys: review.overlaps.map((o) => o.key).toSet(),
        ),
      );
      expect(result, isA<ImportConfirmed>());
      expect((result as ImportConfirmed).movementCount, 2);
      expect((await SqliteMovementRepository(db).readYear(2026)).length, 12);
    });

    test(
      'Confirmar revalida conflictos aparecidos después de revisar',
      () async {
        await importTemplate();
        final session = await _session(
          '2027-01-01;Plan;100.00;PRESUPUESTO;Vivienda;Alquiler;;;',
        );
        final review = await previewer.preview(session);
        final request = ImportConfirmationRequest(review: review);
        final category = (await SqliteCategoryRepository(
          db,
        ).list()).singleWhere((c) => c.name == 'Alquiler');
        await SqliteBudgetRepository(db).create(
          BudgetInput(
            month: BudgetMonth(2027, 1),
            categoryId: category.id,
            amountCents: 0,
          ),
        );
        final before = await image();
        final result = await confirmer.confirm(request);
        expect(result, isA<ImportRejected>());
        expect(
          (result as ImportRejected).issues.any(
            (i) => i.code == ImportIssueCode.budgetConflict,
          ),
          isTrue,
        );
        expect(await image(), before);
      },
    );

    test(
      'Fallo de escritura revierte referencias, lote, filas e historial',
      () async {
        await db.customStatement(
          "CREATE TRIGGER fail_csv BEFORE INSERT ON movements BEGIN SELECT RAISE(ABORT, 'fallo sintético'); END",
        );
        final before = await image();
        final session = await _template();
        final review = await previewer.preview(
          session,
          bindings: _templatePlans(session),
        );
        final result = await confirmer.confirm(
          ImportConfirmationRequest(review: review),
        );
        expect(result, isA<ImportRejected>());
        expect(await image(), before);
      },
    );
  });
}
