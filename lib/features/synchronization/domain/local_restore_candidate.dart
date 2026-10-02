import 'local_backup_creation.dart';

enum LocalRestoreCandidateIssue {
  operationInProgress,
  missingFile,
  incompleteFile,
  sizeMismatch,
  hashMismatch,
  invalidMetadata,
  foreignFormat,
  futureFormat,
  futureSchema,
  unsupportedSchema,
  schemaMismatch,
  integrityFailure,
  foreignKeyFailure,
  financialRuleFailure,
  storageFailure,
  migrationFailure,
}

extension LocalRestoreCandidateMessage on LocalRestoreCandidateIssue {
  String get message => switch (this) {
    LocalRestoreCandidateIssue.operationInProgress =>
      'Hay otra operación de copias locales en curso.',
    LocalRestoreCandidateIssue.missingFile =>
      'Falta un archivo de la copia seleccionada.',
    LocalRestoreCandidateIssue.incompleteFile =>
      'La copia está incompleta o necesita archivos auxiliares.',
    LocalRestoreCandidateIssue.sizeMismatch =>
      'El tamaño de la copia no coincide con sus metadatos.',
    LocalRestoreCandidateIssue.hashMismatch =>
      'El contenido de la copia ha cambiado desde su registro.',
    LocalRestoreCandidateIssue.invalidMetadata =>
      'Los metadatos de la copia no son válidos o no coinciden.',
    LocalRestoreCandidateIssue.foreignFormat =>
      'La copia no pertenece a Autofinance.',
    LocalRestoreCandidateIssue.futureFormat => 'El formato de la copia requiere una versión más reciente de Autofinance.',
    LocalRestoreCandidateIssue.futureSchema =>
      'La base requiere una versión más reciente de Autofinance.',
    LocalRestoreCandidateIssue.unsupportedSchema =>
      'La versión del esquema no está admitida para restauración.',
    LocalRestoreCandidateIssue.schemaMismatch =>
      'La estructura de la base no coincide con el esquema publicado.',
    LocalRestoreCandidateIssue.integrityFailure =>
      'La base SQLite está dañada o no se puede interpretar.',
    LocalRestoreCandidateIssue.foreignKeyFailure =>
      'La base contiene referencias a datos inexistentes.',
    LocalRestoreCandidateIssue.financialRuleFailure =>
      'La base incumple las reglas financieras de Autofinance.',
    LocalRestoreCandidateIssue.storageFailure => 'No se pudo acceder o guardar la copia de trabajo. Revisa el almacenamiento.',
    LocalRestoreCandidateIssue.migrationFailure =>
      'No se pudo migrar la copia de trabajo al esquema actual.',
  };
}

sealed class LocalRestoreCandidateResult {
  const LocalRestoreCandidateResult();
}

final class ReadyLocalRestoreCandidate extends LocalRestoreCandidateResult {
  const ReadyLocalRestoreCandidate({
    required this.backupId,
    required this.operationId,
    required this.relativePath,
    required this.originalSchemaVersion,
    required this.image,
    required this.sizeBytes,
    required this.sha256,
  });
  final String backupId;
  final String operationId;

  /// Respecto a soporte/sqlite; solo una imagen de trabajo cerrada y validada.
  final String relativePath;
  final int originalSchemaVersion;
  final LocalBackupImage image;
  final int sizeBytes;
  final String sha256;
  bool get migrated => originalSchemaVersion != image.schemaVersion;
}

final class RejectedLocalRestoreCandidate extends LocalRestoreCandidateResult {
  const RejectedLocalRestoreCandidate(this.issue);
  final LocalRestoreCandidateIssue issue;
  String get message => issue.message;
}

final class LocalRestoreCandidateFailure implements Exception {
  const LocalRestoreCandidateFailure(this.issue);
  final LocalRestoreCandidateIssue issue;
  @override
  String toString() => issue.message;
}

abstract interface class LocalRestoreCandidatePreparer {
  /// ID privado de catálogo/manifiesto; no admite un archivo externo arbitrario.
  Future<LocalRestoreCandidateResult> prepare(String backupId);
}

/// App aporta la política SQLite; inspect no escribe y migrate solo recibe staging.
abstract interface class LocalRestoreImagePolicy {
  Future<LocalBackupImage> inspect(String path);
  Future<void> migrate(String stagingPath);
}
