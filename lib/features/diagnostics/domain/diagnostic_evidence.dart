import '../../budget/budget.dart' show BudgetRecord;
import '../../importing/importing.dart' show ImportBatch;
import '../../indicators/indicators.dart'
    show IndicatorEvaluation, UnavailableIndicator;
import '../../movements/movements.dart' show MovementRecord;
import '../../wealth/wealth.dart'
    show Month, WealthSnapshot, WealthSnapshotStatus;
import 'diagnostic_action.dart';
import 'diagnostic_rule.dart';

final class DiagnosticRecordRef {
  DiagnosticRecordRef(this.entity, this.id) {
    if (id.trim().isEmpty) throw ArgumentError('Falta identidad de evidencia.');
  }
  final DiagnosticEntity entity;
  final String id;
}

/// Hechos comprobados por el adaptador/servicio propietario. No realiza IO.
/// El ejecutor T02 acredita la lectura y la relación entre registros.
sealed class DiagnosticEvidence {
  const DiagnosticEvidence();
  DiagnosticRule get rule;
  DiagnosticAction get action;

  /// Solo evidencias patrimoniales/indicador limitan el ámbito a este mes.
  Month? get selectedMonth => null;
}

final class IntegrityEvidence extends DiagnosticEvidence {
  IntegrityEvidence({required this.checkCode, required this.detail}) {
    if (checkCode.trim().isEmpty || detail.trim().isEmpty) {
      throw ArgumentError('Falta identificación del control de integridad.');
    }
  }
  final String checkCode, detail;
  @override
  DiagnosticRule get rule => DiagnosticRule.integrity;
  @override
  DiagnosticAction get action => const OpenLocalRecovery();
}

final class BrokenReferenceEvidence extends DiagnosticEvidence {
  BrokenReferenceEvidence({
    required this.owner,
    required this.field,
    required this.missingTarget,
  }) {
    if (field.trim().isEmpty) throw ArgumentError('Falta campo de referencia.');
  }
  final DiagnosticRecordRef owner, missingTarget;
  final String field;
  @override
  DiagnosticRule get rule => DiagnosticRule.references;
  @override
  DiagnosticAction get action => OpenDiagnosticCatalog(missingTarget.entity);
}

/// La ascendencia se acredita con el árbol actual, también archivado.
final class BudgetOverlapEvidence extends DiagnosticEvidence {
  BudgetOverlapEvidence({required this.ancestor, required this.descendant}) {
    if (ancestor.id == descendant.id ||
        ancestor.data.categoryId == descendant.data.categoryId ||
        ancestor.data.month.value != descendant.data.month.value) {
      throw ArgumentError('El conflicto exige dos niveles en el mismo mes.');
    }
  }
  final BudgetRecord ancestor, descendant;
  @override
  DiagnosticRule get rule => DiagnosticRule.budgetOverlap;
  @override
  DiagnosticAction get action =>
      OpenBudgetMonth(Month.parse(ancestor.data.month.value), ancestor.id);
}

/// Dos lotes PERSISTIDOS con la misma huella, no un intento rechazado.
final class RepeatedImportEvidence extends DiagnosticEvidence {
  RepeatedImportEvidence(List<ImportBatch> batches)
    : batches = List.unmodifiable(batches) {
    if (this.batches.length < 2 ||
        this.batches.map((batch) => batch.id).toSet().length !=
            this.batches.length ||
        this.batches.map((batch) => batch.sha256).toSet().length != 1) {
      throw ArgumentError(
        'La repetición debe estar persistida en varios lotes.',
      );
    }
  }
  final List<ImportBatch> batches;
  String get sha256 => batches.first.sha256;
  @override
  DiagnosticRule get rule => DiagnosticRule.repeatedImport;
  @override
  DiagnosticAction get action => OpenImportBatch(batches.first.id);
}

/// T02 reutiliza el criterio EP-012: cuenta/fecha/importe/concepto trim/lower.
/// Es un aviso para revisión humana aun cuando todos esos campos coincidan.
final class ImportCoincidenceEvidence extends DiagnosticEvidence {
  ImportCoincidenceEvidence(this.first, this.second) {
    for (final record in [first, second]) {
      if (record.batchId == null ||
          record.importRowId == null ||
          record.sourceOrdinal == null ||
          record.sourceOrdinal! < 2) {
        throw ArgumentError(
          'Falta procedencia identificable de la coincidencia.',
        );
      }
    }
    if (first.id == second.id || first.batchId == second.batchId) {
      throw ArgumentError('Dos filas del mismo lote no son esta evidencia.');
    }
  }
  final MovementRecord first, second;
  @override
  DiagnosticRule get rule => DiagnosticRule.importCoincidence;
  @override
  DiagnosticAction get action =>
      OpenImportBatch(first.batchId!, sourceOrdinal: first.sourceOrdinal);
}

final class UncategorizedMovementEvidence extends DiagnosticEvidence {
  UncategorizedMovementEvidence(this.movement) {
    if (movement.data.categoryId != null) {
      throw ArgumentError('El movimiento ya tiene categoría.');
    }
  }
  final MovementRecord movement;
  @override
  DiagnosticRule get rule => DiagnosticRule.uncategorizedMovement;
  @override
  DiagnosticAction get action => OpenPendingMovement(movement.id);
}

/// Reutiliza estado y fichas vigentes de WealthRepository, sin crear pendientes
/// de calendario, exigir valores a fichas futuras/bajas ni confundir cero/null.
final class WealthPhotoEvidence extends DiagnosticEvidence {
  WealthPhotoEvidence(this.snapshot) {
    if (snapshot.status == WealthSnapshotStatus.complete ||
        snapshot.pending.any(
          (account) =>
              account.activeFrom.compareTo(snapshot.month) > 0 ||
              (account.activeThrough != null &&
                  account.activeThrough!.compareTo(snapshot.month) < 0),
        )) {
      throw ArgumentError(
        'La evidencia requiere foto sin dato y fichas vigentes.',
      );
    }
  }
  final WealthSnapshot snapshot;
  @override
  DiagnosticRule get rule => snapshot.status == WealthSnapshotStatus.absent
      ? DiagnosticRule.absentPhoto
      : DiagnosticRule.incompletePhoto;
  @override
  Month get selectedMonth => snapshot.month;
  @override
  DiagnosticAction get action => OpenWealthPhoto(snapshot.month);
}

/// Mantiene causa, precedencia y detalle entregados por EP-023, sin fórmula.
final class UnavailableIndicatorEvidence extends DiagnosticEvidence {
  UnavailableIndicatorEvidence(this.evaluation) {
    final result = evaluation.result;
    if (result is! UnavailableIndicator ||
        !evaluation.definition.reasons.any(
          (reason) => reason.code == result.code && reason.text == result.text,
        ) ||
        !const {
          'foto_ausente',
          'foto_incompleta',
          'ingresos_incompletos',
          'ingresos_nulos',
          'ingresos_negativos',
        }.contains(result.code)) {
      throw ArgumentError('Se requiere una causa EP-023 reconocida sin dato.');
    }
  }
  final IndicatorEvaluation evaluation;
  UnavailableIndicator get result => evaluation.result as UnavailableIndicator;
  @override
  DiagnosticRule get rule => DiagnosticRule.unavailableIndicator;
  @override
  Month get selectedMonth => evaluation.month;
  @override
  DiagnosticAction get action => switch (result.code) {
    'foto_ausente' || 'foto_incompleta' => OpenWealthPhoto(evaluation.month),
    _ => OpenIncomeBudget(int.parse(evaluation.month.value.substring(0, 4))),
  };
}
