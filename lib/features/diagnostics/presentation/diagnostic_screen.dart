import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../ui/autofinance_ui.dart';
import '../../wealth/wealth.dart' show Month;
import '../diagnostics.dart';
import 'diagnostic_controller.dart';

const diagnosticRuleLabels = {
  DiagnosticRule.integrity: 'Integridad local',
  DiagnosticRule.references: 'Referencia inexistente',
  DiagnosticRule.budgetOverlap: 'Presupuesto padre y descendiente',
  DiagnosticRule.repeatedImport: 'Importación repetida persistida',
  DiagnosticRule.importCoincidence: 'Posible coincidencia entre lotes',
  DiagnosticRule.uncategorizedMovement: 'Movimiento sin categoría',
  DiagnosticRule.absentPhoto: 'Foto ausente',
  DiagnosticRule.incompletePhoto: 'Foto incompleta',
  DiagnosticRule.unavailableIndicator: 'Indicador sin dato',
};
const diagnosticSeverityLabels = {
  DiagnosticSeverity.error: 'Errores',
  DiagnosticSeverity.warning: 'Avisos',
  DiagnosticSeverity.pending: 'Pendientes',
};
const diagnosticEntityLabels = {
  DiagnosticEntity.category: 'categoría',
  DiagnosticEntity.account: 'ficha',
  DiagnosticEntity.movement: 'movimiento',
  DiagnosticEntity.budget: 'partida',
  DiagnosticEntity.importBatch: 'lote',
  DiagnosticEntity.importRow: 'fila de importación',
  DiagnosticEntity.wealthSnapshot: 'foto',
  DiagnosticEntity.wealthValue: 'valor patrimonial',
  DiagnosticEntity.liquidityPeriod: 'periodo de liquidez',
};

/// Resumen primero y evidencia desplegable. Las acciones las compone app.
class DiagnosticScreen extends StatelessWidget {
  const DiagnosticScreen({
    super.key,
    required this.controller,
    required this.month,
    required this.onAction,
    required this.onRecord,
  });
  final DiagnosticController controller;
  final Month month;
  final Future<void> Function(DiagnosticAction) onAction;
  final Future<void> Function(DiagnosticEntity, String, Month) onRecord;

  String _money(int cents) => AfAmount(cents).format();

  String _summary(DiagnosticEvidence e) => switch (e) {
    IntegrityEvidence() => 'La base requiere revisión en Recuperación local.',
    BrokenReferenceEvidence() =>
      'El campo ${e.field} conserva una referencia inexistente.',
    BudgetOverlapEvidence() =>
      'Dos niveles de la misma rama tienen partidas en ${e.ancestor.data.month.value}.',
    RepeatedImportEvidence() =>
      '${e.batches.length} lotes persistidos comparten la misma huella.',
    ImportCoincidenceEvidence() =>
      '${e.first.data.concept} · ${e.first.data.valueDate.value} · ${_money(e.first.data.amountCents)} · dos lotes distintos.',
    UncategorizedMovementEvidence() =>
      '${e.movement.data.concept} · ${e.movement.data.valueDate.value} · ${_money(e.movement.data.amountCents)}',
    WealthPhotoEvidence() =>
      '${e.snapshot.month.value} · Sin dato · ${e.snapshot.pending.length} fichas pendientes.',
    UnavailableIndicatorEvidence() => e.result.text,
  };

  Widget _record(
    DiagnosticEntity entity,
    String id,
    Month period,
    String label,
  ) => AfAction(label: label, onPressed: () => onRecord(entity, id, period));

  List<Widget> _evidence(DiagnosticEvidence e) => switch (e) {
    IntegrityEvidence() => [Text('${e.checkCode}: ${e.detail}')],
    BrokenReferenceEvidence() => [
      Text(
        'Registro ${diagnosticEntityLabels[e.owner.entity]} · ${e.owner.id} · campo ${e.field}',
      ),
      Text(
        'Referencia inexistente: ${diagnosticEntityLabels[e.missingTarget.entity]} · ${e.missingTarget.id}. Se abrirá el catálogo para revisar la referencia.',
      ),
    ],
    BudgetOverlapEvidence() => [
      for (final r in [e.ancestor, e.descendant]) ...[
        Text(
          'Partida ${r.id} · categoría ${r.data.categoryId} · ${r.data.month.value} · ${_money(r.data.amountCents)}',
        ),
        _record(
          DiagnosticEntity.budget,
          r.id,
          Month.parse(r.data.month.value),
          'Abrir partida ${r.id} · ${r.data.month.value}',
        ),
      ],
    ],
    RepeatedImportEvidence() => [
      Text('Huella SHA-256: ${e.sha256}'),
      for (final b in e.batches)
        AfAction(
          label: 'Abrir lote ${b.id}',
          onPressed: () => onAction(OpenImportBatch(b.id)),
        ),
    ],
    ImportCoincidenceEvidence() => [
      const Text(
        'Coincidencia para revisión humana. Ambos movimientos se conservan; no demuestra duplicación.',
      ),
      for (final r in [e.first, e.second]) ...[
        Text(
          'Movimiento ${r.id} · cuenta ${r.data.accountId} · ${r.data.valueDate.value} · ${r.data.concept} · ${_money(r.data.amountCents)} · lote ${r.batchId} · fila ${r.sourceOrdinal}',
        ),
        AfAction(
          label: 'Abrir lote ${r.batchId} · fila ${r.sourceOrdinal}',
          onPressed: () => onAction(
            OpenImportBatch(r.batchId!, sourceOrdinal: r.sourceOrdinal),
          ),
        ),
        _record(
          DiagnosticEntity.importRow,
          r.importRowId!,
          Month.parse('${r.data.valueDate.value.substring(0, 7)}-01'),
          'Abrir procedencia · fila ${r.sourceOrdinal}',
        ),
        _record(
          DiagnosticEntity.movement,
          r.id,
          Month.parse('${r.data.valueDate.value.substring(0, 7)}-01'),
          'Abrir movimiento ${r.id}',
        ),
      ],
    ],
    UncategorizedMovementEvidence() => [
      Text(
        'Movimiento ${e.movement.id} · ${e.movement.data.valueDate.value} · ${e.movement.data.concept} · ${_money(e.movement.data.amountCents)}',
      ),
      const Text(
        'Se abrirá la bandeja de categorización. Conserva pendientes de todos los meses.',
      ),
      if (e.movement.importRowId == null) ...[
        const Text(
          'Este movimiento es manual. Puedes abrir su ficha para asignarle categoría.',
        ),
        _record(
          DiagnosticEntity.movement,
          e.movement.id,
          Month.parse('${e.movement.data.valueDate.value.substring(0, 7)}-01'),
          'Abrir movimiento manual ${e.movement.id}',
        ),
      ],
    ],
    WealthPhotoEvidence() => [
      Text(
        'Foto del día 1 · ${e.snapshot.month.value} · Sin dato. Las fotos son manuales.',
      ),
      for (final a in e.snapshot.pending)
        _record(
          DiagnosticEntity.account,
          a.id,
          e.snapshot.month,
          'Abrir ficha ${a.name} · ${a.id}',
        ),
    ],
    UnavailableIndicatorEvidence() => [
      Text(e.result.text),
      for (final a in e.result.detail.pendingAccounts)
        Text('Ficha pendiente: ${a.name} · ${a.id}'),
      for (final m in e.result.detail.pendingMonths)
        _record(
          DiagnosticEntity.budget,
          '',
          Month(int.parse(e.evaluation.month.value.substring(0, 4)), m),
          'Completar presupuesto · ${e.evaluation.month.value.substring(0, 4)}-${m.toString().padLeft(2, '0')}',
        ),
      Text(
        'Indicador ${e.evaluation.definition.id} v${e.evaluation.definition.version} · ${e.evaluation.month.value} · causa ${e.result.code}',
      ),
    ],
  };

  String _destination(DiagnosticAction action) => switch (action) {
    OpenLocalRecovery() => 'Abrir Recuperación local',
    OpenDiagnosticCatalog(:final entity) =>
      'Revisar catálogo · ${diagnosticEntityLabels[entity]}',
    OpenBudgetMonth(:final month, :final budgetId) =>
      'Abrir partida $budgetId · ${month.value}',
    OpenImportBatch(:final batchId, :final sourceOrdinal) =>
      'Abrir lote $batchId${sourceOrdinal == null ? '' : ' · fila $sourceOrdinal'}',
    OpenPendingMovement(:final movementId) =>
      'Abrir bandeja · movimiento $movementId',
    OpenWealthPhoto(:final month) => 'Completar foto · ${month.value}',
    OpenIncomeBudget(:final year) =>
      'Completar presupuesto de ingresos · $year',
  };

  Future<void> _openFinding(DiagnosticFinding finding) {
    final evidence = finding.evidence;
    if (evidence is UnavailableIndicatorEvidence &&
        finding.action is OpenIncomeBudget &&
        evidence.result.detail.pendingMonths.isNotEmpty) {
      return onRecord(
        DiagnosticEntity.budget,
        '',
        Month(
          int.parse(evidence.evaluation.month.value.substring(0, 4)),
          evidence.result.detail.pendingMonths.first,
        ),
      );
    }
    return onAction(finding.action);
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final report = c.report;
    final findings = report?.results.expand((r) => r.findings).toList() ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 16,
      children: [
        const Text(
          'Revisión manual de tus datos locales. Los controles estructurales abarcan toda la base; fotos e indicador corresponden al mes elegido y los ingresos a su año. No se corrigen ni borran registros.',
        ),
        AfAction(
          variant: AfActionVariant.primary,
          label: report == null && c.execution == null
              ? 'Ejecutar diagnóstico'
              : 'Repetir diagnóstico',
          onPressed: c.busy ? null : () => c.run(month),
        ),
        if (c.busy) ...[
          const AfStatus(
            kind: AfStatusKind.loading,
            message: 'Ejecutando diagnóstico. Puedes cancelar; se descartará el resultado al terminar la lectura en curso.',
          ),
          AfAction(label: 'Cancelar diagnóstico', onPressed: c.cancel),
        ] else if (c.execution case DiagnosticFailed(
          :final reason,
          :final results,
        )) ...[
          AfStatus(
            kind: reason == DiagnosticSessionFailure.readFailure
                ? AfStatusKind.error
                : AfStatusKind.pending,
            message: switch (reason) {
              DiagnosticSessionFailure.cancelled =>
                'Diagnóstico cancelado. No hay resultado conforme.',
              DiagnosticSessionFailure.changedDuringRead => 'Los datos cambiaron durante la lectura. Repite el diagnóstico explícitamente.',
              DiagnosticSessionFailure.readFailure => 'No se pudo leer la base local. Revisa Recuperación local; no hay recuentos financieros fiables.',
            },
            action: reason == DiagnosticSessionFailure.readFailure
                ? AfAction(
                    label: 'Abrir Recuperación local',
                    onPressed: () => onAction(const OpenLocalRecovery()),
                  )
                : null,
          ),
          for (final r in results)
            Text('Regla no ejecutada: ${diagnosticRuleLabels[r.rule]}'),
        ] else if (report != null) ...[
          if (c.obsolete || c.checking)
            AfStatus(
              kind: AfStatusKind.pending,
              message: c.obsolete
                  ? 'Resultado obsoleto. El mes o los datos han cambiado. Repite el diagnóstico explícitamente.'
                  : 'Comprobando vigencia del resultado…',
            ),
          AfCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Text(
                  c.obsolete
                      ? 'Resultado anterior'
                      : c.checking
                      ? 'Resultado pendiente de validar'
                      : report.isConformant
                      ? 'Sin hallazgos'
                      : report.results.any(
                          (r) => r.status == DiagnosticRuleStatus.notRun,
                        )
                      ? 'Revisión incompleta'
                      : 'Revisión con hallazgos',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  'Ejecutado: ${DateFormat('dd/MM/yyyy HH:mm:ss', 'es_ES').format(report.executedAt.toLocal())} · Mes ${report.selectedMonth.value}',
                ),
                Text(
                  'Revisión ${report.revision.dataset.revision} · base ${report.revision.dataset.datasetId} · sesión ${report.revision.generation}',
                ),
                Text(
                  '${report.results.where((r) => r.status != DiagnosticRuleStatus.notRun).length} de 9 reglas ejecutadas',
                ),
              ],
            ),
          ),
          AfResponsiveGrid(
            children: [
              for (final s in DiagnosticSeverity.values)
                AfCard(
                  child: Text(
                    '${diagnosticSeverityLabels[s]}: ${findings.where((f) => f.severity == s).length}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
            ],
          ),
          if (report.isConformant)
            const Text(
              'Las nueve reglas se ejecutaron sin incidencias en el ámbito revisado. Un mes sin presupuesto es válido; cero registrado y referencias archivadas conservadas también.',
            ),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Todas'),
                selected: c.severity == null,
                onSelected: (_) => c.filter(null),
              ),
              for (final s in DiagnosticSeverity.values)
                ChoiceChip(
                  label: Text(diagnosticSeverityLabels[s]!),
                  selected: c.severity == s,
                  onSelected: (_) => c.filter(s),
                ),
            ],
          ),
          for (final s in DiagnosticSeverity.values)
            if ((c.severity == null || c.severity == s) &&
                findings.any((f) => f.severity == s)) ...[
              Text(
                diagnosticSeverityLabels[s]!,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final f in findings.where((f) => f.severity == s))
                AfCard(
                  child: Material(
                    type: MaterialType.transparency,
                    child: ExpansionTile(
                      key: PageStorageKey(f.evidence),
                      tilePadding: EdgeInsets.zero,
                      title: Text(diagnosticRuleLabels[f.rule]!),
                      subtitle: Text(
                        '${_summary(f.evidence)}\nVer detalle y origen',
                      ),
                      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 12,
                          children: [
                            Text(
                              'Regla: ${f.rule.code} · Ámbito: ${f.scope == DiagnosticScopeKind.database ? 'toda la base local' : report.selectedMonth.value}',
                            ),
                            ..._evidence(f.evidence),
                            AfAction(
                              label: _destination(f.action),
                              onPressed: () => _openFinding(f),
                            ),
                            const Text(
                              'Revisa el origen antes de decidir cualquier cambio.',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          if (findings.isNotEmpty &&
              !findings.any(
                (f) => c.severity == null || f.severity == c.severity,
              ))
            const Text(
              'No hay hallazgos con esta severidad. Los recuentos muestran el total de la ejecución.',
            ),
          AfCard(
            child: Material(
              type: MaterialType.transparency,
              child: ExpansionTile(
                title: const Text('Ver cobertura de las nueve reglas'),
                children: [
                  for (final r in report.results)
                    ListTile(
                      title: Text(diagnosticRuleLabels[r.rule]!),
                      subtitle: Text(
                        r.status == DiagnosticRuleStatus.notRun
                            ? 'Regla no ejecutada · ${switch (r.notRunReason) {
                                DiagnosticNotRunReason.dependencyUnavailable => 'proveedor no disponible',
                                DiagnosticNotRunReason.cancelled => 'cancelada',
                                DiagnosticNotRunReason.readFailure => 'fallo de lectura',
                                _ => 'no solicitada',
                              }}'
                            : 'Ejecutada · ${r.findings.length} hallazgos',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ] else
          const AfStatus(
            kind: AfStatusKind.pending,
            message: 'Listo para revisar. Elige el mes y pulsa Ejecutar diagnóstico.',
          ),
      ],
    );
  }
}
