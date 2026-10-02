import '../../../core/persistence/unit_of_work.dart';

enum LocalBackupOrigin { manual, preRestore }

enum LocalBackupFailureCode {
  operationInProgress,
  storageFailure,
  invalidSnapshot,
  invalidMetadata,
  recoveryRequired,
  incompatibleCatalog,
  counterExhausted,
}

final class LocalBackupFailure implements Exception {
  const LocalBackupFailure(this.code);
  final LocalBackupFailureCode code;

  @override
  String toString() =>
      'No se pudo completar la copia local (${code.name}). '
      'Se han conservado la base y las copias anteriores.';
}

/// Datos de la imagen, obtenidos por la política SQLite de EP-004.
final class LocalBackupImage {
  const LocalBackupImage({
    required this.state,
    required this.schemaVersion,
    required this.applicationId,
  });
  final DatasetState state;
  final int schemaVersion;
  final int applicationId;
}

abstract interface class LocalBackupImageValidator {
  Future<LocalBackupImage> validate(String path);
}

final class CreatedLocalBackup {
  const CreatedLocalBackup({
    required this.backupId,
    required this.relativeDirectory,
    required this.state,
    required this.creationOrder,
    required this.origin,
    required this.cleanupPending,
  });
  final String backupId;
  final String relativeDirectory;
  final DatasetState state;
  final int creationOrder;
  final LocalBackupOrigin origin;
  final bool cleanupPending;
}

abstract interface class LocalBackupCreator {
  Future<CreatedLocalBackup> createManual();

  /// Solo para el coordinador de restauración; no ejecuta retención.
  Future<CreatedLocalBackup> createPreRestore(String restoreOperationId);
}
