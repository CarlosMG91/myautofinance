import 'import_batch.dart';
import 'import_file.dart';
import 'import_creation.dart';
import 'interpreted_import.dart';

/// El lector entrega también todos sus errores; no omite filas inválidas para
/// permitir una carga parcial. Las filas que no pudo tipar quedan en issues.
final class ImportInterpretation {
  ImportInterpretation({
    required this.formatVersion,
    this.contractVersion = importContractVersion,
    List<InterpretedImportRow> rows = const [],
    List<ImportIssue> issues = const [],
  }) : rows = List.unmodifiable(rows),
       issues = List.unmodifiable(issues);

  final String contractVersion, formatVersion;
  final List<InterpretedImportRow> rows;
  final List<ImportIssue> issues;
}

/// Instantánea inmutable descartable. Construirla no consulta ni escribe datos.
final class ImportSession {
  ImportSession({required this.file, required this.interpretation}) {
    final found = <ImportIssue>[...interpretation.issues];
    if (interpretation.contractVersion != importContractVersion ||
        interpretation.formatVersion.trim().isEmpty) {
      found.add(
        const ImportIssue(
          code: ImportIssueCode.unsupportedVersion,
          reason: 'Versión de contrato o de lector no admitida.',
        ),
      );
    }
    if (interpretation.rows.isEmpty) {
      found.add(
        const ImportIssue(
          code: ImportIssueCode.emptyBatch,
          reason: 'El lote no contiene filas importables.',
        ),
      );
    }
    final ordinals = <int>{};
    for (final row in interpretation.rows) {
      if (row.sourceOrdinal < 2 || !ordinals.add(row.sourceOrdinal)) {
        found.add(
          ImportIssue(
            code: ImportIssueCode.invalidOrdinal,
            sourceOrdinal: row.sourceOrdinal,
            field: 'sourceOrdinal',
            reason: 'Ordinal inválido o repetido entre filas del lote.',
          ),
        );
      }
      if (file.source == ImportSource.bankXls && row is InterpretedBudget) {
        found.add(
          ImportIssue(
            code: ImportIssueCode.invalidField,
            sourceOrdinal: row.sourceOrdinal,
            field: 'tipo',
            reason: 'El origen bancario solo admite movimientos REAL.',
          ),
        );
      }
      if (file.source == ImportSource.historicalCsv &&
          row is InterpretedBudget &&
          row.amount.convention != ImportAmountConvention.historicalBudget) {
        found.add(
          ImportIssue(
            code: ImportIssueCode.invalidField,
            sourceOrdinal: row.sourceOrdinal,
            field: 'importe',
            reason:
                'El presupuesto CSV exige normalización del signo original.',
          ),
        );
      }
    }
    issues = List.unmodifiable(found);
  }

  final ImportFile file;
  final ImportInterpretation interpretation;
  late final List<ImportIssue> issues;
  bool get isValid => issues.isEmpty;
}

/// Lector sin persistencia ni acceso a catálogos. CSV/XLS implementarán este
/// puerto en sus épicas; sus bytes y errores pertenecen a esta interpretación.
abstract interface class ImportAdapter {
  ImportSource get source;
  Future<ImportInterpretation> interpret(ImportFile file);
}

/// Describe una referencia todavía no resuelta y todos sus ordinales afectados.
/// El resolutor debe tratar desconocidas y ambiguas expresamente, sin escribir.
final class ImportPendingReference {
  ImportPendingReference({
    required this.reference,
    required List<int> sourceOrdinals,
    required this.reason,
    List<String> candidateIds = const [],
  }) : sourceOrdinals = List.unmodifiable(sourceOrdinals),
       candidateIds = List.unmodifiable(candidateIds);

  // Los únicos tipos permitidos son los dos tipos de referencias públicas.
  final ImportReference reference;
  final List<int> sourceOrdinals;
  final String reason;
  final List<String> candidateIds;
}

sealed class ImportReference {
  const ImportReference();
}

final class PendingImportAccount extends ImportReference {
  const PendingImportAccount(this.account);
  final ImportAccountReference account;
}

final class PendingImportCategory extends ImportReference {
  const PendingImportCategory(this.category);
  final ImportCategoryReference category;
}

/// Coincidencia por cuenta/fecha/importe/concepto normalizado. Es aviso para
/// revisión explícita, nunca motivo para eliminar filas ni deduplicarlas.
final class ImportOverlap {
  const ImportOverlap({
    required this.sourceOrdinal,
    required this.existingMovementId,
  });
  final int sourceOrdinal;
  final String existingMovementId;
  String get key => '$sourceOrdinal:$existingMovementId';
}

/// Vinculaciones a identidades existentes y altas explícitamente propuestas;
/// una misma referencia aplica a todas sus filas. Son decisiones en memoria.
/// No confundir una referencia ausente en este mapa con Sin clasificar.
final class ImportReferenceBindings {
  ImportReferenceBindings({
    Map<ImportAccountReference, String> accounts = const {},
    Map<ImportCategoryReference, String> categories = const {},
    Map<ImportAccountReference, ImportNewAccount> newAccounts = const {},
    Map<ImportCategoryReference, ImportNewCategory> newCategories = const {},
  }) : accounts = Map.unmodifiable(accounts),
       categories = Map.unmodifiable(categories),
       newAccounts = Map.unmodifiable(newAccounts),
       newCategories = Map.unmodifiable(newCategories);

  final Map<ImportAccountReference, String> accounts;
  final Map<ImportCategoryReference, String> categories;
  final Map<ImportAccountReference, ImportNewAccount> newAccounts;
  final Map<ImportCategoryReference, ImportNewCategory> newCategories;

  ImportCategoryTarget? categoryTarget(ImportCategoryReference reference) {
    final id = categories[reference];
    if (id != null && id.trim().isNotEmpty) {
      return ImportCategoryTarget.existing(id);
    }
    return newCategories.containsKey(reference)
        ? ImportCategoryTarget.proposed(reference)
        : null;
  }

  bool resolves(InterpretedImportRow row) {
    bool present(String? id) => id != null && id.trim().isNotEmpty;
    return switch (row) {
      InterpretedMovement() =>
        (present(accounts[row.account]) ||
                newAccounts.containsKey(row.account)) &&
            (row.category == null || categoryTarget(row.category!) != null),
      InterpretedBudget() => categoryTarget(row.category) != null,
    };
  }
}

/// Resultado de lectura con asignaciones y planes de altas validados.
/// Una revisión preparada no garantiza confirmación:
/// toda restricción se vuelve a validar al confirmar con la base vigente.
final class ImportReview {
  ImportReview({
    required this.session,
    ImportReferenceBindings? bindings,
    List<ImportIssue> issues = const [],
    List<ImportPendingReference> pendingReferences = const [],
    List<ImportOverlap> overlaps = const [],
  }) : bindings = bindings ?? ImportReferenceBindings(),
       issues = List.unmodifiable(issues),
       pendingReferences = List.unmodifiable(pendingReferences),
       overlaps = List.unmodifiable(overlaps);

  final ImportSession session;
  final ImportReferenceBindings bindings;
  final List<ImportIssue> issues;
  final List<ImportPendingReference> pendingReferences;
  final List<ImportOverlap> overlaps;

  bool get canRequestConfirmation =>
      session.isValid &&
      issues.isEmpty &&
      pendingReferences.isEmpty &&
      session.interpretation.rows.every(bindings.resolves);

  int get movementCount =>
      session.interpretation.rows.whereType<InterpretedMovement>().length;
  int get budgetCount =>
      session.interpretation.rows.whereType<InterpretedBudget>().length;

  /// BigInt evita overflow al mostrar totales de archivos grandes.
  BigInt totalCents({required bool budgets, required bool original}) => session
      .interpretation
      .rows
      .where((row) => (row is InterpretedBudget) == budgets)
      .fold(BigInt.zero, (sum, row) {
        final amount = row.amount;
        return sum +
            BigInt.from(original ? amount.originalCents : amount.internalCents);
      });
}

abstract interface class ImportPreviewer {
  /// Solo lectura. Resolver/vincular/planificar altas no modifica la base.
  /// Debe devolver referencias pendientes y errores de todo el lote.
  Future<ImportReview> preview(
    ImportSession session, {
    ImportReferenceBindings? bindings,
  });
}

final class ImportConfirmationRequest {
  ImportConfirmationRequest({
    required this.review,
    Set<String> reviewedOverlapKeys = const {},
  }) : reviewedOverlapKeys = Set.unmodifiable(reviewedOverlapKeys) {
    if (!review.canRequestConfirmation ||
        !this.reviewedOverlapKeys.containsAll(
          review.overlaps.map((o) => o.key),
        )) {
      throw StateError(
        'Resuelve los errores y revisa todos los solapamientos.',
      );
    }
  }
  final ImportReview review;
  final Set<String> reviewedOverlapKeys;
}

sealed class ImportConfirmationResult {
  const ImportConfirmationResult();
}

final class ImportConfirmed extends ImportConfirmationResult {
  const ImportConfirmed({
    required this.batch,
    required this.movementCount,
    required this.budgetCount,
  });
  final ImportBatch batch;
  final int movementCount, budgetCount;
}

/// Incluso después de editar/borrar registros: cero altas de cualquier tipo.
final class ImportAlreadyImported extends ImportConfirmationResult {
  const ImportAlreadyImported(this.batch);
  final ImportBatch batch;
}

final class ImportRejected extends ImportConfirmationResult {
  ImportRejected(List<ImportIssue> issues)
    : issues = List.unmodifiable(issues) {
    if (this.issues.isEmpty) throw ArgumentError('Falta el motivo de rechazo.');
  }
  final List<ImportIssue> issues;
}

abstract interface class ImportConfirmer {
  /// Revalidar SHA de bytes, asignaciones, restricciones y solapamientos nuevos
  /// en la base actual; confirmar altas aprobadas/lote/filas/revisión en una
  /// transacción. Igual SHA devuelve alreadyImported sin ninguna escritura.
  /// Guardar campos originales y metadatos, nunca bytes ni intentos fallidos.
  Future<ImportConfirmationResult> confirm(ImportConfirmationRequest request);
}
