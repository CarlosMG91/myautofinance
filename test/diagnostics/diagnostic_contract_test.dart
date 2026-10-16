import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/core/persistence/unit_of_work.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/diagnostics/diagnostics.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/indicators/indicators.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

final _month = Month(2026, 1);
const _revision = DiagnosticRevision(
  DatasetState(datasetId: 'sintetico', revision: 7),
  generation: 1,
);

MovementRecord _movement(
  String id, {
  String? category,
  String? batch = 'lote-a',
  int ordinal = 2,
}) => MovementRecord(
  id: id,
  data: MovementInput(
    accountId: 'cuenta',
    valueDate: ValueDate(2026, 1, 5),
    concept: 'Café sintético',
    amountCents: -1000,
    categoryId: category,
  ),
  batchId: batch,
  importRowId: batch == null ? null : '$batch-$ordinal',
  sourceOrdinal: batch == null ? null : ordinal,
);

BudgetRecord _budget(String id, String category, {int month = 1}) =>
    BudgetRecord(
      id: id,
      data: BudgetInput(
        month: BudgetMonth(2026, month),
        categoryId: category,
        amountCents: 0,
      ),
    );

ImportBatch _batch(String id, {String? sha}) => ImportBatch(
  id: id,
  sha256: sha ?? 'a' * 64,
  source: ImportSource.historicalCsv,
  originalName: 'sintetico.csv',
  contractVersion: '1',
  importedAt: '2026-01-05T00:00:00Z',
);

AccountRecord _account({Month? from, Month? through}) => AccountRecord(
  id: 'cuenta',
  name: 'Cuenta sintética',
  kind: AccountKind.account,
  activeFrom: from ?? Month(2026, 1),
  activeThrough: through,
  liquidity: Liquidity.liquid,
);

WealthSnapshot _photo(WealthSnapshotStatus status, {Month? month}) =>
    WealthSnapshot(
      month: month ?? _month,
      snapshotId: status == WealthSnapshotStatus.absent ? null : 'foto',
      status: status,
      values: status == WealthSnapshotStatus.complete
          ? [WealthValue(id: 'valor', account: _account(), amountCents: 0)]
          : [],
      pending: status == WealthSnapshotStatus.complete ? [] : [_account()],
    );

IndicatorEvaluation _evaluation({
  WealthSnapshotStatus photo = WealthSnapshotStatus.complete,
  int income = 3600000,
  Set<int>? present,
}) {
  final inputs = IndicatorInputs(
    month: _month,
    wealth: WealthReading.fromSnapshot(_photo(photo)),
    annualIncome: AnnualIncomeBudget(
      year: 2026,
      totalCents: BigInt.from(income),
      presentMonths: present ?? {for (var i = 1; i <= 12; i++) i},
    ),
  );
  return IndicatorEvaluation(
    definition: IndicatorCatalog.v1().definition('colchon_emergencia'),
    month: _month,
    result: const EmergencyCushionCalculation().calculate(inputs),
    inputs: inputs,
  );
}

DiagnosticReport _report(List<DiagnosticRuleResult> results, {Month? month}) =>
    DiagnosticReport(
      executedAt: DateTime.utc(2026, 10, 16, 8),
      selectedMonth: month ?? _month,
      revision: _revision,
      results: results,
    );

void main() {
  final examples = <(DiagnosticEvidence, DiagnosticRule, DiagnosticSeverity)>[
    (
      IntegrityEvidence(
        checkCode: 'integrity_check',
        detail: 'página sintética',
      ),
      DiagnosticRule.integrity,
      DiagnosticSeverity.error,
    ),
    (
      BrokenReferenceEvidence(
        owner: DiagnosticRecordRef(DiagnosticEntity.movement, 'real'),
        field: 'category_id',
        missingTarget: DiagnosticRecordRef(
          DiagnosticEntity.category,
          'ausente',
        ),
      ),
      DiagnosticRule.references,
      DiagnosticSeverity.error,
    ),
    (
      BudgetOverlapEvidence(
        ancestor: _budget('padre', 'categoria-padre'),
        descendant: _budget('hijo', 'categoria-hijo'),
      ),
      DiagnosticRule.budgetOverlap,
      DiagnosticSeverity.error,
    ),
    (
      RepeatedImportEvidence([_batch('lote-a'), _batch('lote-b')]),
      DiagnosticRule.repeatedImport,
      DiagnosticSeverity.error,
    ),
    (
      ImportCoincidenceEvidence(
        _movement('real-a'),
        _movement('real-b', batch: 'lote-b'),
      ),
      DiagnosticRule.importCoincidence,
      DiagnosticSeverity.warning,
    ),
    (
      UncategorizedMovementEvidence(_movement('real')),
      DiagnosticRule.uncategorizedMovement,
      DiagnosticSeverity.pending,
    ),
    (
      WealthPhotoEvidence(_photo(WealthSnapshotStatus.absent)),
      DiagnosticRule.absentPhoto,
      DiagnosticSeverity.pending,
    ),
    (
      WealthPhotoEvidence(_photo(WealthSnapshotStatus.incomplete)),
      DiagnosticRule.incompletePhoto,
      DiagnosticSeverity.pending,
    ),
    (
      UnavailableIndicatorEvidence(_evaluation(present: {})),
      DiagnosticRule.unavailableIndicator,
      DiagnosticSeverity.pending,
    ),
  ];

  test('catálogo cubierto una vez, códigos estables y origen del control', () {
    expect(examples.map((example) => example.$2), DiagnosticRule.values);
    expect(DiagnosticRule.values.map((rule) => rule.code), [
      'integridad_local',
      'referencia_invalida',
      'presupuesto_solapado',
      'importacion_repetida_persistida',
      'coincidencia_entre_lotes',
      'movimiento_sin_categoria',
      'foto_ausente',
      'foto_incompleta',
      'indicador_sin_dato',
    ]);
    expect(
      DiagnosticRule.budgetOverlap.control,
      DiagnosticControl.existingValidation,
    );
    expect(
      DiagnosticRule.uncategorizedMovement.control,
      DiagnosticControl.retrospectiveCheck,
    );
  });

  for (final (evidence, rule, severity) in examples) {
    test('${rule.code}: clasificación y ámbito de su ejemplo', () {
      final result = DiagnosticRuleResult.completed(rule, evidence: [evidence]);
      final finding = result.findings.single;
      expect(result.status, DiagnosticRuleStatus.findings);
      expect(finding.rule, rule);
      expect(finding.severity, severity);
      expect(finding.evidence, same(evidence));
      expect(
        finding.scope,
        evidence.selectedMonth == null
            ? DiagnosticScopeKind.database
            : DiagnosticScopeKind.selectedMonth,
      );
      expect(_report([result]).isConformant, isFalse);
    });
  }

  test('acciones preservan identidades y no apuntan al UUID inexistente', () {
    expect(examples[0].$1.action, isA<OpenLocalRecovery>());
    expect(
      (examples[1].$1.action as OpenDiagnosticCatalog).entity,
      DiagnosticEntity.category,
    );
    final budget = examples[2].$1.action as OpenBudgetMonth;
    expect(budget.budgetId, 'padre');
    expect(budget.month.value, '2026-01-01');
    expect((examples[3].$1.action as OpenImportBatch).batchId, 'lote-a');
    final coincidence = examples[4].$1.action as OpenImportBatch;
    expect(coincidence.batchId, 'lote-a');
    expect(coincidence.sourceOrdinal, 2);
    expect((examples[5].$1.action as OpenPendingMovement).movementId, 'real');
    expect(
      (examples[6].$1.action as OpenWealthPhoto).month.value,
      '2026-01-01',
    );
  });

  test('categoría nula pendiente; categoría asignada no es pendiente', () {
    final evidence = UncategorizedMovementEvidence(
      _movement('manual', batch: null),
    );
    expect(evidence.rule, DiagnosticRule.uncategorizedMovement);
    expect(evidence.rule.severity, DiagnosticSeverity.pending);
    expect(
      () => UncategorizedMovementEvidence(_movement('real', category: 'cat')),
      throwsArgumentError,
    );
    expect(
      () => DiagnosticRecordRef(DiagnosticEntity.category, ''),
      throwsArgumentError,
    );
  });

  test(
    'repetición rechazada con un solo lote nunca es duplicación persistida',
    () {
      expect(
        () => RepeatedImportEvidence([_batch('único')]),
        throwsArgumentError,
      );
      expect(
        () => RepeatedImportEvidence([_batch('único'), _batch('único')]),
        throwsArgumentError,
      );
      expect(
        () => RepeatedImportEvidence([_batch('a'), _batch('b', sha: 'b' * 64)]),
        throwsArgumentError,
      );
    },
  );

  test('dos Café de un lote son legítimos y conservan ordinales distintos', () {
    final first = _movement('café-1');
    final second = _movement('café-2', ordinal: 3);
    expect(() => ImportCoincidenceEvidence(first, second), throwsArgumentError);
    expect([first.id, second.id], ['café-1', 'café-2']);
    expect([first.sourceOrdinal, second.sourceOrdinal], [2, 3]);
    expect(
      () => ImportCoincidenceEvidence(first, _movement('manual', batch: null)),
      throwsArgumentError,
    );
  });

  test('el conflicto presupuestario tiene mes propio, incluso cero', () {
    final conflict = examples[2].$1 as BudgetOverlapEvidence;
    expect(conflict.ancestor.data.amountCents, 0);
    // Un conflicto estructural histórico no se limita al mes de la pantalla.
    final report = _report([
      DiagnosticRuleResult.completed(conflict.rule, evidence: [conflict]),
    ], month: Month(2026, 10));
    expect(report.results[2].status, DiagnosticRuleStatus.findings);
    expect(
      () => BudgetOverlapEvidence(
        ancestor: _budget('a', 'padre'),
        descendant: _budget('b', 'hijo', month: 2),
      ),
      throwsArgumentError,
    );
  });

  test('foto cero es completa; nunca se convierte en pendiente', () {
    final snapshot = _photo(WealthSnapshotStatus.complete);
    expect(WealthReading.fromSnapshot(snapshot).liquidAssetsCents, 0);
    expect(() => WealthPhotoEvidence(snapshot), throwsArgumentError);
    final evaluation = _evaluation();
    expect(evaluation.result, isA<CalculatedIndicator>());
    expect(() => UnavailableIndicatorEvidence(evaluation), throwsArgumentError);
  });

  test('solo mes seleccionado y fichas vigentes, alta/baja inclusivas', () {
    final evidence = WealthPhotoEvidence(_photo(WealthSnapshotStatus.absent));
    expect(evidence.snapshot.pending.single.id, 'cuenta');
    final result = DiagnosticRuleResult.completed(
      evidence.rule,
      evidence: [evidence],
    );
    expect(() => _report([result], month: Month(2026, 2)), throwsArgumentError);
    for (final account in [
      _account(from: Month(2026, 2)),
      _account(from: Month(2025, 1), through: Month(2025, 12)),
    ]) {
      expect(
        () => WealthPhotoEvidence(
          WealthSnapshot(
            month: _month,
            snapshotId: null,
            status: WealthSnapshotStatus.absent,
            values: [],
            pending: [account],
          ),
        ),
        throwsArgumentError,
      );
    }
    final lastMonth = WealthSnapshot(
      month: _month,
      snapshotId: null,
      status: WealthSnapshotStatus.absent,
      values: [],
      pending: [_account(through: _month)],
    );
    expect(WealthPhotoEvidence(lastMonth).snapshot.pending, hasLength(1));
    final empty = WealthSnapshot(
      month: _month,
      snapshotId: null,
      status: WealthSnapshotStatus.absent,
      values: [],
      pending: [],
    );
    expect(WealthPhotoEvidence(empty).rule, DiagnosticRule.absentPhoto);
  });

  for (final (photo, income, present, code) in [
    (WealthSnapshotStatus.absent, 0, <int>{}, 'foto_ausente'),
    (WealthSnapshotStatus.incomplete, 0, <int>{}, 'foto_incompleta'),
    (WealthSnapshotStatus.complete, 0, <int>{}, 'ingresos_incompletos'),
    (WealthSnapshotStatus.complete, 0, null, 'ingresos_nulos'),
    (WealthSnapshotStatus.complete, -120000, null, 'ingresos_negativos'),
  ]) {
    test('causa EP-023 $code y destino conservados sin recalcular', () {
      final evaluation = _evaluation(
        photo: photo,
        income: income,
        present: present,
      );
      final evidence = UnavailableIndicatorEvidence(evaluation);
      expect(evidence.result, same(evaluation.result));
      expect(evidence.result.code, code);
      expect(evidence.rule.severity, DiagnosticSeverity.pending);
      if (code.startsWith('foto_')) {
        expect((evidence.action as OpenWealthPhoto).month.value, _month.value);
        expect(evidence.result.detail.pendingAccounts.single.id, 'cuenta');
        expect(evidence.result.detail.pendingMonths, isEmpty);
      } else {
        expect((evidence.action as OpenIncomeBudget).year, 2026);
        expect(
          evidence.result.detail.pendingMonths,
          code == 'ingresos_incompletos'
              ? List.generate(12, (i) => i + 1)
              : isEmpty,
        );
      }
    });
  }

  for (final reason in DiagnosticNotRunReason.values) {
    test('no ejecutada por $reason no equivale a conforme', () {
      final result = DiagnosticRuleResult.notRun(
        DiagnosticRule.integrity,
        reason,
      );
      expect(result.status, DiagnosticRuleStatus.notRun);
      expect(result.findings, isEmpty);
      expect(_report([result]).isConformant, isFalse);
    });
  }

  test(
    'sin resultados no hay conformidad; solo controles ejecutados conformes',
    () {
      final empty = _report([]);
      expect(empty.results, hasLength(DiagnosticRule.values.length));
      expect(
        empty.results.every((r) => r.status == DiagnosticRuleStatus.notRun),
        isTrue,
      );
      expect(empty.isConformant, isFalse);
      final complete = _report([
        for (final rule in DiagnosticRule.values)
          DiagnosticRuleResult.completed(rule),
      ]);
      expect(complete.isConformant, isTrue);
      expect(complete.executedAt, DateTime.utc(2026, 10, 16, 8));
    },
  );

  test('inmutabilidad, reglas únicas y evidencia de la regla correcta', () {
    final evidence = <DiagnosticEvidence>[examples.first.$1];
    final result = DiagnosticRuleResult.completed(
      DiagnosticRule.integrity,
      evidence: evidence,
    );
    evidence.clear();
    expect(result.findings, hasLength(1));
    expect(() => result.findings.clear(), throwsUnsupportedError);
    final report = _report([result]);
    expect(() => report.results.clear(), throwsUnsupportedError);
    expect(() => _report([result, result]), throwsArgumentError);
    expect(
      () => DiagnosticRuleResult.completed(
        DiagnosticRule.references,
        evidence: [examples.first.$1],
      ),
      throwsArgumentError,
    );
  });

  test(
    'edición, otra base, restauración o mes distinto dejan resultado obsoleto',
    () {
      final report = _report([]);
      expect(report.isObsolete(_revision, Month(2026, 1)), isFalse);
      for (final current in [
        const DiagnosticRevision(
          DatasetState(datasetId: 'sintetico', revision: 8),
          generation: 1,
        ),
        const DiagnosticRevision(
          DatasetState(datasetId: 'otra', revision: 7),
          generation: 1,
        ),
        const DiagnosticRevision(
          DatasetState(datasetId: 'sintetico', revision: 7),
          generation: 2,
        ),
      ]) {
        expect(report.isObsolete(current, _month), isTrue);
      }
      expect(report.isObsolete(_revision, Month(2026, 2)), isTrue);
    },
  );
}
