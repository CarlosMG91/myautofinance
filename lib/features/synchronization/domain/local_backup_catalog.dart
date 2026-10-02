import 'local_backup_creation.dart';

enum LocalBackupCatalogStatus {
  ready,
  recovered,
  empty,
  incompatible,
  unavailable,
}

enum LocalBackupAvailability {
  present,
  missing,
  incomplete,
  quarantined,
  deletionPending,
}

enum LocalBackupValidationState {
  pending,
  valid,
  invalid,
  incompatible,
  unavailable,
}

enum LocalBackupCatalogIssue {
  incompleteFile,
  orphan,
  invalidMetadata,
  futureFormat,
  missingFile,
  sizeMismatch,
  hashMismatch,
  storageFailure,
  deletionPending,
  ambiguousOrder,
  protectedBackup,
  insufficientValidBackups,
  unresolvedRestore,
  catalogWritePending,
}

final class LocalBackupCatalogIncident {
  const LocalBackupCatalogIncident(this.issue, {this.backupId, this.origin});
  final LocalBackupCatalogIssue issue;
  final String? backupId;
  final LocalBackupOrigin? origin;
}

final class LocalBackupCatalogEntry {
  const LocalBackupCatalogEntry({
    required this.backupId,
    required this.createdAtUtc,
    required this.creationOrder,
    required this.origin,
    required this.sizeBytes,
    required this.availability,
    required this.validation,
    required this.checkedAtUtc,
    required this.issue,
  });
  final String backupId;
  final DateTime createdAtUtc;
  final int creationOrder;
  final LocalBackupOrigin origin;
  final int sizeBytes;
  final LocalBackupAvailability availability;
  final LocalBackupValidationState validation;
  final DateTime? checkedAtUtc;

  /// Código estable de la última comprobación; no contiene excepciones nativas.
  final String? issue;
}

final class LocalBackupCatalogListing {
  LocalBackupCatalogListing({
    required this.status,
    required List<LocalBackupCatalogEntry> entries,
    required List<LocalBackupCatalogIncident> incidents,
    required this.pruningAllowed,
  }) : entries = List.unmodifiable(entries),
       incidents = List.unmodifiable(incidents);
  final LocalBackupCatalogStatus status;
  final List<LocalBackupCatalogEntry> entries;
  final List<LocalBackupCatalogIncident> incidents;
  final bool pruningAllowed;
}

enum LocalRestoreRetentionOutcome { confirmed, failed, cancelled, pending }

final class LocalBackupMaintenanceResult {
  LocalBackupMaintenanceResult({
    required List<String> deletedBackupIds,
    required List<LocalBackupCatalogIncident> incidents,
  }) : deletedBackupIds = List.unmodifiable(deletedBackupIds),
       incidents = List.unmodifiable(incidents);
  final List<String> deletedBackupIds;
  final List<LocalBackupCatalogIncident> incidents;
}

abstract interface class LocalBackupCatalog {
  /// Reconcilia metadatos y archivos sin abrir la activa ni SQLite de las copias.
  Future<LocalBackupCatalogListing> read();

  /// El coordinador solo envía confirmed tras reapertura, validación y
  /// confirmación duradera. Fallo, cancelación e intercambio pendiente no podan.
  /// Debe indicar las copias en uso; diarios no resueltos suspenden la poda.
  Future<LocalBackupMaintenanceResult> maintainAfterRestore({
    required String restoreOperationId,
    required LocalRestoreRetentionOutcome outcome,
    Set<String> protectedBackupIds = const {},
  });

  /// Acción expresa sobre un ID. No borra una copia en uso ni la última válida.
  Future<LocalBackupMaintenanceResult> deleteExplicitly(
    String backupId, {
    Set<String> protectedBackupIds = const {},
  });

  /// Reintenta únicamente bajas duraderas ya autorizadas.
  Future<LocalBackupMaintenanceResult> retryPendingDeletions({
    Set<String> protectedBackupIds = const {},
  });
}
