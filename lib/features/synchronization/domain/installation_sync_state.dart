import '../../../core/persistence/unit_of_work.dart';
import 'drive_metadata.dart';
import 'local_restore.dart';

enum SyncLocalStatus { unknown, clean, changed, contrastRequired, pending }

enum SyncOperationKind { upload, download }

/// La revisión pertenece a la imagen capturada, nunca al final de la subida.
final class PendingSyncOperation {
  const PendingSyncOperation({
    required this.id,
    required this.kind,
    required this.image,
    required this.restoreEpoch,
    this.remoteVersion,
  });
  final String id;
  final SyncOperationKind kind;
  final DatasetState? image;
  final String? restoreEpoch;
  final String? remoteVersion;
}

final class InstallationSyncSnapshot {
  const InstallationSyncSnapshot({
    required this.accountId,
    required this.fileId,
    required this.localStatus,
    this.knownRemoteVersion,
    this.correspondingLocalState,
    this.observedRemoteVersion,
    this.checkedAt,
    this.pending,
  });
  final String accountId;
  final String fileId;
  final SyncLocalStatus localStatus;
  final String? knownRemoteVersion;
  final DatasetState? correspondingLocalState;
  final String? observedRemoteVersion;
  final DateTime? checkedAt;
  final PendingSyncOperation? pending;
  bool get remoteChanged =>
      knownRemoteVersion != null &&
      observedRemoteVersion != null &&
      knownRemoteVersion != observedRemoteVersion;
}

enum SyncStateIssue {
  storageFailure,
  invalidState,
  operationInProgress,
  staleOperation,
  installationNotConfirmed,
  remoteDivergence,
}

final class SyncStateFailure implements Exception {
  const SyncStateFailure(this.issue);
  final SyncStateIssue issue;
  @override
  String toString() => 'SyncStateFailure(${issue.name})';
}

/// Local por instalación; ninguna llamada autoriza OAuth o consulta Drive.
/// Cambiar cuenta/archivo invalida la relación anterior, incluso al volver.
abstract interface class InstallationSyncState {
  Future<InstallationSyncSnapshot> inspect({
    required String accountId,
    required String fileId,
  });

  /// Solo registra observación: no acredita que la base local sea esa versión.
  Future<void> recordCheck({
    required String accountId,
    required DriveFileMetadata remote,
  });
  Future<PendingSyncOperation> beginUpload({
    required String accountId,
    required String fileId,
    required DatasetState capturedImage,
  });
  Future<void> completeUpload({
    required String operationId,
    required DriveFileMetadata remote,
  });
  Future<PendingSyncOperation> beginDownload({
    required String accountId,
    required DriveFileMetadata remote,
    DatasetState? downloadedImage,
  });

  /// Tras descargar y validar en staging, antes de instalar. Permite registrar
  /// la operación desde el inicio de la transferencia, sin imagen todavía.
  Future<void> recordDownloadedImage({
    required String operationId,
    required DatasetState downloadedImage,
  });

  /// Ejecuta la instalación segura. Solo un éxito validado vincula la imagen.
  /// Cancelación, error, rollback o interrupción conservan la operación pendiente.
  Future<LocalRestoreResult> installDownload({
    required String operationId,
    required Future<LocalRestoreResult> Function() install,
  });

  /// Tras resolver/cancelar una operación incierta, deja comparación desconocida.
  Future<void> abandonPending({required String operationId});
}
