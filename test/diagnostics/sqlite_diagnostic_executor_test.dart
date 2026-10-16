import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart'
    show LocalDatabase;
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_diagnostic_source.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/app/diagnostic_factory.dart';
import 'package:myautofinance/app/indicator_input_factory.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/diagnostics/diagnostics.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/indicators/indicators.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart'
    show LocalRestoreStatus;
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:sqlite3/sqlite3.dart';

const missing = '00000000-0000-4000-8000-000000000099';

Future<Map<String, Object?>> image(LocalDatabase db) async => {
  for (final table
      in await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
          )
          .get())
    table.read<String>('name'): [
      for (final row
          in await db
              .customSelect(
                'SELECT * FROM "${table.read<String>('name')}" ORDER BY rowid',
              )
              .get())
        row.data,
    ],
};

Future<IndicatorEvaluation> evaluate(LocalDatabase db, Month month) =>
    IndicatorEngine(
      catalog: IndicatorCatalog.v1(),
      inputs: createIndicatorInputProvider(database: db),
      calculations: {'colchon_emergencia': const EmergencyCushionCalculation()},
    ).evaluate('colchon_emergencia', month);

void main() {
  late LocalDatabase db;
  late SqliteDiagnosticSource source;
  late DiagnosticExecutor executor;
  final month = Month(2026, 1);
  final now = DateTime.utc(2026, 10, 16, 12);

  setUp(() async {
    db = LocalDatabase(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys=ON'),
      ),
    );
    await db.readState();
    source = SqliteDiagnosticSource(open: () async => db, indicator: evaluate);
    executor = DiagnosticExecutor(source, now: () => now);
  });
  tearDown(() => db.close());

  Future<AccountRecord> account({
    Month? from,
    Month? through,
    AccountKind kind = AccountKind.account,
  }) => SqliteAccountRepository(db).create(
    name: 'Ficha sintética',
    kind: kind,
    activeFrom: from ?? month,
    activeThrough: through,
    liquidity: kind == AccountKind.debt ? null : Liquidity.liquid,
  );

  MovementInput movement(
    String account, {
    String? category,
    String concept = 'Café',
    int cents = -1000,
  }) => MovementInput(
    accountId: account,
    valueDate: ValueDate(2026, 1, 5),
    concept: concept,
    amountCents: cents,
    categoryId: category,
  );

  Future<DiagnosticReport> run({Month? selected}) async {
    final before = await image(db);
    final execution = await executor.execute(selected ?? month);
    expect(execution, isA<DiagnosticCompleted>());
    expect(
      await image(db),
      before,
      reason: 'El diagnóstico no cambia ninguna tabla ni revisión',
    );
    final report = (execution as DiagnosticCompleted).report;
    expect(report.executedAt, now);
    expect(report.selectedMonth.value, (selected ?? month).value);
    return report;
  }

  DiagnosticRuleResult result(DiagnosticReport report, DiagnosticRule rule) =>
      report.results.singleWhere((r) => r.rule == rule);
  List<DiagnosticEvidence> findings(
    DiagnosticReport report,
    DiagnosticRule rule,
  ) => result(report, rule).findings.map((f) => f.evidence).toList();

  test('Base vacía: sin presupuesto válido, foto pendiente y causa EP-023 original', () async {
    final report = await run();
    for (final rule in DiagnosticRule.values.take(6)) {
      expect(result(report, rule).status, DiagnosticRuleStatus.conformant);
    }
    expect(findings(report, DiagnosticRule.absentPhoto), hasLength(1));
    final indicator =
        findings(report, DiagnosticRule.unavailableIndicator).single
            as UnavailableIndicatorEvidence;
    expect(indicator.result.code, 'foto_ausente');
    expect(indicator.action, isA<OpenWealthPhoto>());
    expect(report.isConformant, isFalse);
    expect(await executor.isCurrent(report, month), isTrue);
  });

  test('Null es pendiente; archivada conservada es válida; UUID inexistente es error identificable', () async {
    final a = await account();
    final category = await SqliteCategoryRepository(db)
        .create(name: 'Gastos', isIncome: false);
    final pending = await SqliteMovementRepository(db).create(movement(a.id));
    final valid = await SqliteMovementRepository(db)
        .create(movement(a.id, category: category.id));
    await SqliteCategoryRepository(db).setArchived(category.id, archived: true);
    var report = await run();
    expect(findings(report, DiagnosticRule.references), isEmpty);
    expect(
      (findings(report, DiagnosticRule.uncategorizedMovement).single
              as UncategorizedMovementEvidence)
          .movement
          .id,
      pending.id,
    );
    // Corrupción exclusivamente sintética, después de la apertura validada.
    await db.customStatement('PRAGMA foreign_keys=OFF');
    await db.customStatement('UPDATE movements SET category_id=? WHERE id=?', [
      missing,
      valid.id,
    ]);
    await db.customStatement('PRAGMA foreign_keys=ON');
    report = await run();
    final broken =
        findings(report, DiagnosticRule.references).single
            as BrokenReferenceEvidence;
    expect(broken.owner.id, valid.id);
    expect(broken.field, 'category_id');
    expect(broken.missingTarget.id, missing);
    expect(broken.action, isA<OpenDiagnosticCatalog>());
    expect(
      findings(report, DiagnosticRule.uncategorizedMovement),
      hasLength(1),
    );
    expect(
      result(report, DiagnosticRule.unavailableIndicator).notRunReason,
      DiagnosticNotRunReason.dependencyUnavailable,
    );
  });

  test('Foreign key de procedencia conserva propietario/campo/destino sin asignación inventada', () async {
    await db.customStatement('PRAGMA foreign_keys=OFF');
    await db.customStatement(
      "INSERT INTO import_rows VALUES('00000000-0000-4000-8000-000000000001',?,2,'movement','t','t')",
      [missing],
    );
    await db.customStatement('PRAGMA foreign_keys=ON');
    final report = await run();
    final broken =
        findings(report, DiagnosticRule.references).single
            as BrokenReferenceEvidence;
    expect(broken.owner.entity, DiagnosticEntity.importRow);
    expect(broken.missingTarget.entity, DiagnosticEntity.importBatch);
    expect(broken.field, 'batch_id');
  });

  test('Solape histórico raíz/nieto con cero y archivados identifica partidas y mes', () async {
    final categories = SqliteCategoryRepository(db);
    final root = await categories.create(name: 'Raíz', isIncome: false);
    final child = await categories.create(name: 'Hija', parentId: root.id);
    final leaf = await categories.create(name: 'Nieta', parentId: child.id);
    final historic = BudgetMonth(2020, 2);
    final parent = await SqliteBudgetRepository(
      db,
    ).create(BudgetInput(month: historic, categoryId: root.id, amountCents: 0));
    await categories.setArchived(root.id, archived: true);
    await db.customStatement('DROP TRIGGER budgets_insert');
    await db.customStatement(
      "INSERT INTO budgets VALUES(?,?,?,0,NULL,NULL,NULL,'t','t')",
      [missing, historic.value, leaf.id],
    );
    final report = await run();
    final overlap =
        findings(report, DiagnosticRule.budgetOverlap).single
            as BudgetOverlapEvidence;
    expect(overlap.ancestor.id, parent.id);
    expect(overlap.descendant.id, missing);
    expect((overlap.action as OpenBudgetMonth).month.value, historic.value);
  });

  test('Árbol cíclico no bloquea ejecución recursiva ni ofrece presupuesto conforme', () async {
    final categories = SqliteCategoryRepository(db);
    final root = await categories.create(name: 'Raíz', isIncome: false);
    final child = await categories.create(name: 'Hija', parentId: root.id);
    await db.customStatement('DROP TRIGGER categories_update');
    await db.customStatement('DROP TRIGGER categories_budget_overlap');
    await db.customStatement(
      'UPDATE categories SET parent_id=?,is_income=NULL WHERE id=?',
      [child.id, root.id],
    );
    final report = await run();
    expect(findings(report, DiagnosticRule.integrity), isNotEmpty);
    expect(
      result(report, DiagnosticRule.budgetOverlap).notRunReason,
      DiagnosticNotRunReason.dependencyUnavailable,
    );
  });

  test('Dos filas iguales en lote son legítimas; entre lotes solo aviso, original no requerido', () async {
    final a = await account();
    final batches = SqliteImportBatchRepository(db);
    final first = await batches.create(
      sha256: 'a' * 64,
      source: ImportSource.historicalCsv,
      originalName: 'sintetico.csv',
      contractVersion: '1',
      movements: [
        ImportedMovement(2, movement(a.id)),
        ImportedMovement(3, movement(a.id)),
      ],
    );
    var report = await run();
    expect(findings(report, DiagnosticRule.importCoincidence), isEmpty);
    expect(findings(report, DiagnosticRule.repeatedImport), isEmpty);
    final second = await batches.create(
      sha256: 'b' * 64,
      source: ImportSource.bankXls,
      originalName: 'sintetico.xls',
      contractVersion: '1',
      movements: [ImportedMovement(2, movement(a.id, concept: ' CAFÉ '))],
    );
    report = await run();
    final overlaps = findings(
      report,
      DiagnosticRule.importCoincidence,
    ).cast<ImportCoincidenceEvidence>();
    expect(overlaps, hasLength(2));
    for (final overlap in overlaps) {
      expect(
        {overlap.first.batchId, overlap.second.batchId},
        {first.id, second.id},
      );
      expect(overlap.rule.severity, DiagnosticSeverity.warning);
      expect(overlap.first.sourceOrdinal, isNotNull);
    }
    expect(findings(report, DiagnosticRule.repeatedImport), isEmpty);
    expect(
      (await db.customSelect('SELECT * FROM import_row_originals').get()),
      isEmpty,
    );
    // El destino borrado conserva su origen y no es corrupción.
    final id = overlaps.first.second.id;
    await SqliteMovementRepository(db).delete(id);
    report = await run();
    expect(findings(report, DiagnosticRule.references), isEmpty);
    expect(findings(report, DiagnosticRule.integrity), isEmpty);
  });

  test('Dos lotes persistidos con igual SHA son error distinto del aviso de coincidencia', () async {
    final a = await account();
    final first = await SqliteImportBatchRepository(db).create(
      sha256: 'a' * 64,
      source: ImportSource.historicalCsv,
      originalName: 'sintetico.csv',
      contractVersion: '1',
      movements: [ImportedMovement(2, movement(a.id))],
    );
    // Reconstrucción solo en fixture de memoria para eliminar la unicidad SHA.
    await db.customStatement('PRAGMA foreign_keys=OFF');
    final schema =
        (await db
                .customSelect(
                  "SELECT sql FROM sqlite_master WHERE name='import_batches'",
                )
                .getSingle())
            .read<String>('sql');
    await db.customStatement(
      schema
          .replaceFirst('"import_batches"', '"synthetic_batches"')
          .replaceFirst(' UNIQUE', ''),
    );
    await db.customStatement(
      'INSERT INTO synthetic_batches SELECT * FROM import_batches',
    );
    await db.customStatement('DROP TABLE import_batches');
    await db.customStatement(
      'ALTER TABLE synthetic_batches RENAME TO import_batches',
    );
    await db.customStatement(
      'INSERT INTO import_batches SELECT ?,content_sha256,source_kind,original_name,contract_version,imported_at,created_at,updated_at FROM import_batches',
      [missing],
    );
    await db.customStatement('PRAGMA foreign_keys=ON');
    final report = await run();
    final repeated =
        findings(report, DiagnosticRule.repeatedImport).single
            as RepeatedImportEvidence;
    expect(
      repeated.batches.map((b) => b.id),
      unorderedEquals([first.id, missing]),
    );
    expect(repeated.sha256, 'a' * 64);
    expect(repeated.rule.severity, DiagnosticSeverity.error);
  });

  test(
    'Foto cero válida, vigencias inclusivas y pendientes solo del mes elegido',
    () async {
      final a = await account(through: month);
      await account(from: Month(2026, 2));
      await account(from: Month(2025, 1), through: Month(2025, 12));
      await SqliteWealthRepository(db).setValue(month, a.id, 0);
      var report = await run();
      expect(findings(report, DiagnosticRule.absentPhoto), isEmpty);
      expect(findings(report, DiagnosticRule.incompletePhoto), isEmpty);
      final indicator =
          findings(report, DiagnosticRule.unavailableIndicator).single
              as UnavailableIndicatorEvidence;
      expect(indicator.result.code, 'ingresos_incompletos');
      final debt = await account(kind: AccountKind.debt);
      report = await run();
      final photo =
          findings(report, DiagnosticRule.incompletePhoto).single
              as WealthPhotoEvidence;
      expect(photo.snapshot.pending.map((a) => a.id), [debt.id]);
      expect(photo.snapshot.values.single.amountCents, 0);
      report = await run(selected: Month(2026, 2));
      expect(findings(report, DiagnosticRule.absentPhoto), hasLength(1));
      expect(findings(report, DiagnosticRule.incompletePhoto), isEmpty);
    },
  );

  test('Proveedor/cálculo real: cero líquido y doce ingresos positivos queda conforme', () async {
    final a = await account();
    await SqliteWealthRepository(db).setValue(month, a.id, 0);
    final income = await SqliteCategoryRepository(db)
        .create(name: 'Ingreso', isIncome: true);
    for (var m = 1; m <= 12; m++) {
      await SqliteBudgetRepository(db).create(
        BudgetInput(
          month: BudgetMonth(2026, m),
          categoryId: income.id,
          amountCents: 100,
        ),
      );
    }
    final report = await run();
    expect(report.isConformant, isTrue);
    expect(findings(report, DiagnosticRule.unavailableIndicator), isEmpty);
  });

  test(
    'Comprobador ausente o fallido no se inventa como causa financiera',
    () async {
      for (final checker in <SqliteDiagnosticIndicator?>[
        null,
        (_, _) async => throw StateError('Fallo sintético'),
      ]) {
        executor = DiagnosticExecutor(
          SqliteDiagnosticSource(open: () async => db, indicator: checker),
          now: () => now,
        );
        final report = await run();
        expect(
          result(report, DiagnosticRule.unavailableIndicator).status,
          DiagnosticRuleStatus.notRun,
        );
        expect(report.isConformant, isFalse);
      }
    },
  );

  test(
    'Cancelación previa y durante el indicador no devuelve conformidad',
    () async {
      final cancellation = DiagnosticCancellation()..cancel();
      final before = await image(db);
      var execution = await executor.execute(month, cancellation: cancellation);
      expect(
        (execution as DiagnosticFailed).reason,
        DiagnosticSessionFailure.cancelled,
      );
      expect(
        execution.results.every(
          (r) => r.notRunReason == DiagnosticNotRunReason.cancelled,
        ),
        isTrue,
      );
      final during = DiagnosticCancellation();
      executor = DiagnosticExecutor(
        SqliteDiagnosticSource(
          open: () async => db,
          indicator: (db, m) async {
            during.cancel();
            return evaluate(db, m);
          },
        ),
      );
      execution = await executor.execute(month, cancellation: during);
      expect(
        (execution as DiagnosticFailed).reason,
        DiagnosticSessionFailure.cancelled,
      );
      expect(await image(db), before);
    },
  );

  test(
    'Base ilegible detiene controles, sin inventar marcador y con recuperación',
    () async {
      final before = await image(db);
      var invoked = false;
      executor = DiagnosticExecutor(
        SqliteDiagnosticSource(
          open: () async => throw StateError('Ilegible'),
          indicator: (db, m) {
            invoked = true;
            return evaluate(db, m);
          },
        ),
      );
      final execution = await executor.execute(month) as DiagnosticFailed;
      expect(execution.reason, DiagnosticSessionFailure.readFailure);
      expect(execution.action, isA<OpenLocalRecovery>());
      expect(
        execution.results.every((r) => r.status == DiagnosticRuleStatus.notRun),
        isTrue,
      );
      expect(invoked, isFalse);
      expect(await image(db), before);
    },
  );

  test(
    'Integridad física fallida conserva evidencia y detiene dependientes',
    () async {
      final a = await account();
      final m = await SqliteMovementRepository(db).create(movement(a.id));
      await db.customStatement('PRAGMA ignore_check_constraints=ON');
      await db.customStatement(
        'UPDATE movements SET amount_cents=0 WHERE id=?',
        [m.id],
      );
      await db.customStatement('PRAGMA ignore_check_constraints=OFF');
      final report = await run();
      expect(
        findings(report, DiagnosticRule.integrity).single,
        isA<IntegrityEvidence>(),
      );
      for (final rule in DiagnosticRule.values.skip(1)) {
        expect(
          result(report, rule).notRunReason,
          DiagnosticNotRunReason.dependencyUnavailable,
        );
      }
    },
  );

  test('Edición posterior invalida; repetición explícita devuelve la nueva revisión', () async {
    final report = await run();
    await account();
    expect(await executor.isCurrent(report, month), isFalse);
    final repeated = await run();
    expect(
      repeated.revision.dataset.revision,
      greaterThan(report.revision.dataset.revision),
    );
    expect(await executor.isCurrent(repeated, month), isTrue);
    expect(await executor.isCurrent(repeated, Month(2026, 2)), isFalse);
  });

  test(
    'Escritor WAL bloqueado no se presenta como indicador conforme',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'diagnostic-synthetic-',
      );
      final store = LocalDatabaseStore(supportDirectory: () async => temp);
      try {
        final active = await store.open();
        expect(
          (await active.customSelect('PRAGMA journal_mode=WAL').getSingle())
              .data
              .values
              .single,
          'wal',
        );
        Object? writerError;
        var writerCalled = false;
        final local = DiagnosticExecutor(
          SqliteDiagnosticSource(
            open: store.open,
            indicator: (db, m) async {
              writerCalled = true;
              try {
                final writer = sqlite3.open(store.databasePath!);
                try {
                  writer.execute(
                    'UPDATE database_state SET revision=revision+1',
                  );
                } finally {
                  writer.close();
                }
              } catch (error) {
                writerError = error;
                rethrow;
              }
              return evaluate(db, m);
            },
          ),
        );
        final previous = await active.readState();
        final execution = await local.execute(month);
        expect(writerCalled, isTrue);
        expect(
          writerError,
          isA<SqliteException>().having((e) => e.resultCode, 'SQLITE_BUSY', 5),
        );
        final report = (execution as DiagnosticCompleted).report;
        expect(
          result(report, DiagnosticRule.unavailableIndicator).notRunReason,
          DiagnosticNotRunReason.readFailure,
        );
        expect(report.isConformant, isFalse);
        expect((await active.readState()).revision, previous.revision);
      } finally {
        await store.close();
        await temp.delete(recursive: true);
      }
    },
  );

  test('Reabrir/restaurar misma imagen invalida generación sin cambiar dataset ni revisión', () async {
    final temp = await Directory.systemTemp.createTemp('diagnostic-synthetic-');
    final session = LocalBackupSession(supportDirectory: () async => temp);
    final store = session.store;
    final local = createDiagnosticExecutor(store: store);
    try {
      expect(await session.open(), isTrue);
      await session.controller.create();
      expect(session.controller.error, isNull);
      final backupId = session.controller.listing!.entries.single.backupId;
      final report =
          ((await local.execute(month)) as DiagnosticCompleted).report;
      await SqliteAccountRepository(await store.open()).create(
        name: 'Alta sintética posterior',
        kind: AccountKind.account,
        activeFrom: month,
        liquidity: Liquidity.liquid,
      );
      await session.controller.restore(backupId, confirmed: true);
      expect(
        session.controller.restoreResult!.status,
        LocalRestoreStatus.restored,
      );
      final state = await (await store.open()).readState();
      expect(state.datasetId, report.revision.dataset.datasetId);
      expect(state.revision, report.revision.dataset.revision);
      expect(await local.isCurrent(report, month), isFalse);
      expect(
        await createDiagnosticExecutor(store: store).isCurrent(report, month),
        isFalse,
      );
      final repeated =
          ((await local.execute(month)) as DiagnosticCompleted).report;
      expect(repeated.revision.generation, isNot(report.revision.generation));
    } finally {
      session.controller.dispose();
      await session.categoryInvalidation.close();
      await store.close();
      await temp.delete(recursive: true);
    }
  });

  test(
    'Cambio después del snapshot descarta resultado; repetir es explícito',
    () async {
      final local = DiagnosticExecutor(
        _AfterSnapshot(source, () async {
          await db.customStatement(
            'UPDATE database_state SET revision=revision+1',
          );
        }),
      );
      final execution = await local.execute(month) as DiagnosticFailed;
      expect(execution.reason, DiagnosticSessionFailure.changedDuringRead);
      expect(
        execution.results.every((r) => r.status == DiagnosticRuleStatus.notRun),
        isTrue,
      );
    },
  );

  test(
    'Archivo ilegible sintético ofrece recuperación sin modificar sus bytes',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'diagnostic-damaged-synthetic-',
      );
      final directory = await Directory('${temp.path}/sqlite').create();
      final file = File('${directory.path}/autofinance.sqlite');
      final bytes = List<int>.generate(256, (i) => i);
      await file.writeAsBytes(bytes);
      final store = LocalDatabaseStore(supportDirectory: () async => temp);
      try {
        final execution = await createDiagnosticExecutor(
          store: store,
        ).execute(month) as DiagnosticFailed;
        expect(execution.action, isA<OpenLocalRecovery>());
        expect(
          execution.results.every(
            (r) => r.status == DiagnosticRuleStatus.notRun,
          ),
          isTrue,
        );
        expect(await file.readAsBytes(), bytes);
      } finally {
        await store.close();
        await temp.delete(recursive: true);
      }
    },
  );

  test(
    'Cambio visible durante los controles descarta sin mezclar lecturas',
    () async {
      final local = DiagnosticExecutor(
        SqliteDiagnosticSource(
          open: () async => db,
          indicator: (db, m) async {
            // Inyección de carrera solo para test: el diagnóstico de producción no escribe.
            await db.customStatement(
              'UPDATE database_state SET revision=revision+1',
            );
            return evaluate(db, m);
          },
        ),
      );
      final execution = await local.execute(month) as DiagnosticFailed;
      expect(execution.reason, DiagnosticSessionFailure.changedDuringRead);
    },
  );
}

final class _AfterSnapshot implements DiagnosticReadSource {
  _AfterSnapshot(this.delegate, this.after);
  final DiagnosticReadSource delegate;
  final Future<void> Function() after;
  @override
  Future<DiagnosticRevision> currentRevision() => delegate.currentRevision();
  @override
  Future<T> read<T>(Future<T> Function(DiagnosticReadSession) operation) async {
    final result = await delegate.read(operation);
    await after();
    return result;
  }
}
