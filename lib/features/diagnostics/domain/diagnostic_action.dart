import '../../wealth/wealth.dart' show Month;

enum DiagnosticEntity {
  category,
  account,
  movement,
  budget,
  importBatch,
  importRow,
  wealthSnapshot,
  wealthValue,
  liquidityPeriod,
}

/// Destinos de dominio, sin rutas, callbacks de escritura ni reparación.
sealed class DiagnosticAction {
  const DiagnosticAction();
}

final class OpenLocalRecovery extends DiagnosticAction {
  const OpenLocalRecovery();
}

/// Una referencia inexistente abre el catálogo, nunca el UUID roto.
final class OpenDiagnosticCatalog extends DiagnosticAction {
  const OpenDiagnosticCatalog(this.entity);
  final DiagnosticEntity entity;
}

final class OpenBudgetMonth extends DiagnosticAction {
  const OpenBudgetMonth(this.month, this.budgetId);
  final Month month;
  final String budgetId;
}

final class OpenImportBatch extends DiagnosticAction {
  const OpenImportBatch(this.batchId, {this.sourceOrdinal});
  final String batchId;
  final int? sourceOrdinal;
}

final class OpenPendingMovement extends DiagnosticAction {
  const OpenPendingMovement(this.movementId);
  final String movementId;
}

final class OpenWealthPhoto extends DiagnosticAction {
  const OpenWealthPhoto(this.month);
  final Month month;
}

final class OpenIncomeBudget extends DiagnosticAction {
  const OpenIncomeBudget(this.year);
  final int year;
}
