import 'package:drift/drift.dart' show Variable;

import '../../../features/budget/budget.dart';
import '../../../features/diagnostics/diagnostics.dart';
import '../../../features/importing/importing.dart';
import '../../../features/indicators/indicators.dart';
import '../../../features/movements/movements.dart';
import '../../../features/wealth/wealth.dart';
import 'local_database.dart' show LocalDatabase;
import 'schema_policy.dart';
import 'sqlite_budget_repository.dart';
import 'sqlite_import_history_repository.dart';
import 'sqlite_movement_repository.dart';
import 'sqlite_wealth_repository.dart';

/// El comprobador inyectado debe usar exclusivamente la conexión recibida.
typedef SqliteDiagnosticIndicator = Future<IndicatorEvaluation> Function(
  LocalDatabase database,
  Month month,
);

/// Se conserva durante la sesión de UI y resuelve la conexión activa en cada
/// llamada. Una reapertura/restauración cambia la generación aun con igual UUID.
final class SqliteDiagnosticSource implements DiagnosticReadSource {
  SqliteDiagnosticSource({required this.open, this.indicator});
  final Future<LocalDatabase> Function() open;
  final SqliteDiagnosticIndicator? indicator;
  static final Expando<int> _generations = Expando();
  static int _nextGeneration = 0;

  int _generation(LocalDatabase db) => _generations[db] ??= ++_nextGeneration;

  @override
  Future<DiagnosticRevision> currentRevision() async {
    final db = await open();
    return DiagnosticRevision(
      await db.readState(),
      generation: _generation(db),
    );
  }

  @override
  Future<T> read<T>(Future<T> Function(DiagnosticReadSession) operation) async {
    final db = await open();
    return db.transaction(() async {
      final session = _Session(
        db,
        DiagnosticRevision(await db.readState(), generation: _generation(db)),
        indicator,
      );
      return operation(session);
    });
  }
}

final class _Session implements DiagnosticReadSession {
  _Session(this.db, this.revision, this.indicator);
  final LocalDatabase db;
  @override
  final DiagnosticRevision revision;
  final SqliteDiagnosticIndicator? indicator;
  bool _readable = true, _validTree = true, _financialDataSafe = true;

  @override
  Future<DiagnosticRevision> readRevision() async =>
      DiagnosticRevision(await db.readState(), generation: revision.generation);

  @override
  Future<DiagnosticRuleResult> check(DiagnosticRule rule, Month month) async {
    if (!_readable ||
        (rule == DiagnosticRule.budgetOverlap && !_validTree) ||
        (rule.scope == DiagnosticScopeKind.selectedMonth &&
            !_financialDataSafe)) {
      return DiagnosticRuleResult.notRun(
        rule,
        DiagnosticNotRunReason.dependencyUnavailable,
      );
    }
    final List<DiagnosticEvidence> evidence;
    switch (rule) {
      case DiagnosticRule.integrity:
        evidence = await _integrity();
      case DiagnosticRule.references:
        evidence = await _references();
        if (evidence.isNotEmpty) _financialDataSafe = false;
      case DiagnosticRule.budgetOverlap:
        evidence = await _budgetOverlaps();
      case DiagnosticRule.repeatedImport:
        evidence = await _repeatedImports();
      case DiagnosticRule.importCoincidence:
        evidence = await _coincidences();
      case DiagnosticRule.uncategorizedMovement:
        evidence = [
          for (final movement in await _movements())
            if (movement.data.categoryId == null)
              UncategorizedMovementEvidence(movement),
        ];
      case DiagnosticRule.absentPhoto || DiagnosticRule.incompletePhoto:
        final photo = await SqliteWealthRepository(db).read(month);
        evidence = photo.status == WealthSnapshotStatus.complete
            ? []
            : [
                if (WealthPhotoEvidence(photo).rule == rule)
                  WealthPhotoEvidence(photo),
              ];
      case DiagnosticRule.unavailableIndicator:
        final checker = indicator;
        if (checker == null) {
          return DiagnosticRuleResult.notRun(
            rule,
            DiagnosticNotRunReason.dependencyUnavailable,
          );
        }
        try {
          final evaluation = await checker(db, month);
          if (evaluation.month.value != month.value ||
              evaluation.inputs.datasetState?.datasetId !=
                  revision.dataset.datasetId ||
              evaluation.inputs.datasetState?.revision !=
                  revision.dataset.revision) {
            throw StateError('Indicador ajeno a la lectura de diagnóstico.');
          }
          evidence = [
            if (evaluation.result is UnavailableIndicator)
              UnavailableIndicatorEvidence(evaluation),
          ];
        } catch (_) {
          return DiagnosticRuleResult.notRun(
            rule,
            DiagnosticNotRunReason.readFailure,
          );
        }
    }
    return DiagnosticRuleResult.completed(rule, evidence: evidence);
  }

  Future<List<DiagnosticEvidence>> _integrity() async {
    final evidence = <DiagnosticEvidence>[];
    final physical = await db.customSelect('PRAGMA integrity_check').get();
    for (final row in physical) {
      final detail = row.data.values.single.toString();
      if (detail != 'ok') {
        evidence.add(
          IntegrityEvidence(checkCode: 'integrity_check', detail: detail),
        );
      }
    }
    if (physical.length != 1 || evidence.isNotEmpty) {
      _readable = false;
      if (evidence.isEmpty) {
        evidence.add(
          IntegrityEvidence(
            checkCode: 'integrity_check',
            detail: 'Respuesta de integridad inesperada.',
          ),
        );
      }
      return evidence;
    }
    for (final (code, sql) in [
      ('category_integrity', categoryIntegrityErrors),
      ('movement_integrity', movementIntegrityErrors),
      ('wealth_integrity', wealthIntegrityErrors),
      ('account_coverage', accountCoverageErrors),
      // Esta consulta recursiva existente requiere un árbol válido.
      ('budget_integrity', budgetIntegrityErrors),
    ]) {
      if (code == 'budget_integrity' && !_validTree) continue;
      final rows = await db.customSelect(sql).get();
      if (code == 'category_integrity') _validTree = rows.isEmpty;
      for (final row in rows) {
        evidence.add(
          IntegrityEvidence(checkCode: code, detail: row.data.toString()),
        );
      }
    }
    _financialDataSafe = evidence.isEmpty;
    return evidence;
  }

  static const _entities = {
    'categories': DiagnosticEntity.category,
    'accounts': DiagnosticEntity.account,
    'movements': DiagnosticEntity.movement,
    'budgets': DiagnosticEntity.budget,
    'import_batches': DiagnosticEntity.importBatch,
    'import_rows': DiagnosticEntity.importRow,
    'wealth_snapshots': DiagnosticEntity.wealthSnapshot,
    'wealth_values': DiagnosticEntity.wealthValue,
    'account_liquidity_periods': DiagnosticEntity.liquidityPeriod,
    'import_batch_metadata': DiagnosticEntity.importBatch,
    'import_row_originals': DiagnosticEntity.importRow,
  };

  Future<List<DiagnosticEvidence>> _references() async {
    final evidence = <DiagnosticEvidence>[];
    // Reutiliza el diagnóstico nativo y su definición real de claves foráneas.
    for (final error
        in await db.customSelect('PRAGMA foreign_key_check').get()) {
      final table = error.read<String>('table');
      final target = error.read<String>('parent');
      if (!_entities.containsKey(table) || !_entities.containsKey(target)) {
        throw StateError('Referencia de tabla desconocida.');
      }
      final keys = await db
          .customSelect('PRAGMA foreign_key_list("$table")')
          .get();
      final key = keys.singleWhere(
        (key) => key.read<int>('id') == error.read<int>('fkid'),
      );
      final field = key.read<String>('from');
      final row = await db
          .customSelect(
            'SELECT * FROM "$table" WHERE rowid=?',
            variables: [Variable(error.read<int>('rowid'))],
          )
          .getSingle();
      final idField = switch (table) {
        'import_batch_metadata' => 'batch_id',
        'import_row_originals' => 'import_row_id',
        _ => 'id',
      };
      evidence.add(
        BrokenReferenceEvidence(
          owner: DiagnosticRecordRef(
            _entities[table]!,
            row.read<String>(idField),
          ),
          field: field,
          missingTarget: DiagnosticRecordRef(
            _entities[target]!,
            row.read<String>(field),
          ),
        ),
      );
    }
    return evidence;
  }

  Future<List<DiagnosticEvidence>> _budgetOverlaps() async {
    final parents = {
      for (final row
          in await db.customSelect('SELECT id,parent_id FROM categories').get())
        row.read<String>('id'): row.readNullable<String>('parent_id'),
    };
    final evidence = <DiagnosticEvidence>[];
    for (final row
        in await db
            .customSelect('SELECT DISTINCT month FROM budgets ORDER BY month')
            .get()) {
      final budgets = await SqliteBudgetRepository(db)
          .list(BudgetMonth.parse(row.read<String>('month')));
      final byCategory = {for (final b in budgets) b.data.categoryId: b};
      for (final child in budgets) {
        var parent = parents[child.data.categoryId];
        while (parent != null) {
          final ancestor = byCategory[parent];
          if (ancestor != null) {
            evidence.add(
              BudgetOverlapEvidence(ancestor: ancestor, descendant: child),
            );
          }
          parent = parents[parent];
        }
      }
    }
    return evidence;
  }

  Future<List<DiagnosticEvidence>> _repeatedImports() async {
    final grouped = <String, List<ImportBatch>>{};
    final repository = SqliteImportHistoryRepository(db);
    ImportBatchCursor? cursor;
    do {
      final page = await repository.listBatches(limit: 500, cursor: cursor);
      for (final batch in page.items) {
        (grouped[batch.sha256] ??= []).add(batch);
      }
      cursor = page.next;
    } while (cursor != null);
    return [
      for (final batches in grouped.values)
        if (batches.length > 1) RepeatedImportEvidence(batches),
    ];
  }

  Future<List<MovementRecord>> _movements() async {
    final records = <MovementRecord>[];
    final repository = SqliteMovementRepository(db);
    // Sin paginación parcial ni límite de año: toda la base, incluidos históricos.
    for (final row
        in await db
            .customSelect(
              'SELECT DISTINCT substr(value_date,1,7) AS month FROM movements ORDER BY month',
            )
            .get()) {
      final month = row.read<String>('month');
      records.addAll(
        await repository.readMonth(
          int.parse(month.substring(0, 4)),
          int.parse(month.substring(5, 7)),
        ),
      );
    }
    return records;
  }

  Future<List<DiagnosticEvidence>> _coincidences() async {
    final groups = <ImportMovementMatch, List<MovementRecord>>{};
    final evidence = <DiagnosticEvidence>[];
    for (final record in await _movements()) {
      if (record.batchId == null ||
          record.importRowId == null ||
          record.sourceOrdinal == null) {
        continue;
      }
      final data = record.data;
      final key = importMovementMatch(
        accountId: data.accountId,
        valueDate: data.valueDate.value,
        amountCents: data.amountCents,
        concept: data.concept,
      );
      final previous = groups[key] ??= [];
      for (final other in previous) {
        if (other.batchId != record.batchId) {
          evidence.add(ImportCoincidenceEvidence(other, record));
        }
      }
      previous.add(record);
    }
    return evidence;
  }
}
