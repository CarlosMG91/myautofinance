enum DiagnosticSeverity { error, warning, pending }

enum DiagnosticScopeKind { database, selectedMonth }

/// Distingue restricciones ya preventivas de nuevas lecturas retrospectivas.
enum DiagnosticControl { existingValidation, retrospectiveCheck }

/// Códigos explícitos estables: no serializar el índice ni el nombre del enum.
enum DiagnosticRule {
  integrity('integridad_local', DiagnosticSeverity.error),
  references('referencia_invalida', DiagnosticSeverity.error),
  budgetOverlap('presupuesto_solapado', DiagnosticSeverity.error),
  repeatedImport('importacion_repetida_persistida', DiagnosticSeverity.error),
  importCoincidence('coincidencia_entre_lotes', DiagnosticSeverity.warning),
  uncategorizedMovement('movimiento_sin_categoria', DiagnosticSeverity.pending),
  absentPhoto('foto_ausente', DiagnosticSeverity.pending),
  incompletePhoto('foto_incompleta', DiagnosticSeverity.pending),
  unavailableIndicator('indicador_sin_dato', DiagnosticSeverity.pending);

  const DiagnosticRule(this.code, this.severity);
  final String code;
  final DiagnosticSeverity severity;

  DiagnosticScopeKind get scope => switch (this) {
    absentPhoto ||
    incompletePhoto ||
    unavailableIndicator => DiagnosticScopeKind.selectedMonth,
    _ => DiagnosticScopeKind.database,
  };

  DiagnosticControl get control => switch (this) {
    integrity ||
    references ||
    budgetOverlap ||
    repeatedImport ||
    importCoincidence => DiagnosticControl.existingValidation,
    _ => DiagnosticControl.retrospectiveCheck,
  };
}
