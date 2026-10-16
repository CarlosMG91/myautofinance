import '../../../core/persistence/unit_of_work.dart';
import '../../wealth/wealth.dart' show Month;
import 'diagnostic_action.dart';
import 'diagnostic_evidence.dart';
import 'diagnostic_rule.dart';

enum DiagnosticRuleStatus { notRun, conformant, findings }

enum DiagnosticNotRunReason {
  notRequested,
  dependencyUnavailable,
  cancelled,
  readFailure,
}

final class DiagnosticFinding {
  const DiagnosticFinding(this.evidence);
  final DiagnosticEvidence evidence;
  DiagnosticRule get rule => evidence.rule;
  DiagnosticSeverity get severity => rule.severity;
  DiagnosticScopeKind get scope => rule.scope;
  DiagnosticAction get action => evidence.action;
}

final class DiagnosticRuleResult {
  DiagnosticRuleResult.completed(
    this.rule, {
    List<DiagnosticEvidence> evidence = const [],
  }) : findings = List.unmodifiable(evidence.map(DiagnosticFinding.new)),
       notRunReason = null {
    if (evidence.any((item) => item.rule != rule)) {
      throw ArgumentError('Evidencia de otra regla.');
    }
  }

  const DiagnosticRuleResult.notRun(this.rule, DiagnosticNotRunReason reason)
    : notRunReason = reason,
      findings = const [];

  final DiagnosticRule rule;
  final List<DiagnosticFinding> findings;
  final DiagnosticNotRunReason? notRunReason;
  DiagnosticRuleStatus get status => notRunReason != null
      ? DiagnosticRuleStatus.notRun
      : findings.isEmpty
      ? DiagnosticRuleStatus.conformant
      : DiagnosticRuleStatus.findings;
}

/// La generación de sesión cambia al sustituir/reabrir la base, incluso si
/// datasetId/revision coinciden. La composición T02 aporta este marcador.
final class DiagnosticRevision {
  const DiagnosticRevision(this.dataset, {required this.generation});
  final DatasetState dataset;
  final int generation;

  bool matches(DiagnosticRevision other) =>
      dataset.datasetId == other.dataset.datasetId &&
      dataset.revision == other.dataset.revision &&
      generation == other.generation;
}

/// Resultado efímero: base completa + patrimonio/indicador del mes elegido.
/// No ejecuta controles, no persiste resultados ni inicia repeticiones.
final class DiagnosticReport {
  DiagnosticReport({
    required this.executedAt,
    required this.selectedMonth,
    required this.revision,
    required List<DiagnosticRuleResult> results,
  }) : results = List.unmodifiable([
         for (final rule in DiagnosticRule.values)
           results.firstWhere(
             (result) => result.rule == rule,
             orElse: () => DiagnosticRuleResult.notRun(
               rule,
               DiagnosticNotRunReason.notRequested,
             ),
           ),
       ]) {
    if (results.map((result) => result.rule).toSet().length != results.length) {
      throw ArgumentError('Regla repetida en el resultado.');
    }
    for (final finding in this.results.expand((result) => result.findings)) {
      final month = finding.evidence.selectedMonth;
      if (month != null && month.value != selectedMonth.value) {
        throw ArgumentError('Evidencia patrimonial/indicador de otro mes.');
      }
    }
  }

  final DateTime executedAt;
  final Month selectedMonth;
  final DiagnosticRevision revision;
  final List<DiagnosticRuleResult> results;

  bool get isConformant => results.every(
    (result) => result.status == DiagnosticRuleStatus.conformant,
  );

  bool isObsolete(DiagnosticRevision current, Month month) =>
      !revision.matches(current) || selectedMonth.value != month.value;
}
