import '../../../core/persistence/unit_of_work.dart';
import 'drive_metadata.dart';
import 'drive_transfer.dart';
import 'installation_sync_state.dart';
import 'local_backup_creation.dart';
import 'local_restore_candidate.dart';
import 'local_sync_contrast.dart';

enum DriveDownloadStatus {
  ready,
  cancelled,
  busy,
  noCopy,
  remoteUnavailable,
  remoteChanged,
  localChanged,
  reconciliationRequired,
  invalidMetadata,
  sizeMismatch,
  hashMismatch,
  invalidImage,
  failed,
}

/// Se presenta siempre antes de transferir. Solo clean permite continuar sin
/// confirmación de pérdida; unknown/contrastRequired también requieren permiso.
final class DriveDownloadReview {
  const DriveDownloadReview({
    required this.accountId,
    required this.remote,
    required this.localStatus,
  });
  final String accountId;
  final DriveFileMetadata remote;
  final SyncLocalStatus localStatus;
  bool get requiresConfirmation => localStatus != SyncLocalStatus.clean;
  String get warning =>
      'Al aplicar esta copia se perderán los cambios de la base activa. '
      'Puedes cancelar y conservar tus datos locales.';
  @override
  String toString() => 'DriveDownloadReview';
}

/// Imagen cerrada de staging; no es una instalación ni un acuse de sincronía.
/// El consumidor debe descartarla o entregarla al flujo seguro de EP-006,
/// que volverá a comprobar versión remota, imagen y cambios locales al aplicar.
final class ValidatedDriveDownload {
  const ValidatedDriveDownload({
    required this.path,
    required this.remote,
    required this.accountId,
    required this.folderId,
    required this.image,
    required this.sha256,
    required this.localState,
    this.localContrast,
  });
  final String path;
  final DriveFileMetadata remote;
  final String accountId;
  final String folderId;
  final LocalBackupImage image;
  final String sha256;
  final DatasetState localState;
  final LocalSyncContrast? localContrast;
  @override
  String toString() => 'ValidatedDriveDownload';
}

final class DriveDownloadResult {
  const DriveDownloadResult(
    this.status, {
    this.candidate,
    this.imageIssue,
    this.transferFailure,
    this.cleanupPending = false,
  });
  final DriveDownloadStatus status;
  final ValidatedDriveDownload? candidate;
  final LocalRestoreCandidateIssue? imageIssue;
  final DriveTransferFailure? transferFailure;
  final bool cleanupPending;
}

abstract interface class DriveDownloader {
  /// Exclusivamente desde «Descargar última copia». review muestra cuenta,
  /// fecha y versión y devuelve true solo tras la confirmación que corresponda.
  Future<DriveDownloadResult> download({
    required DriveTransferCancellation cancellation,
    required Future<bool> Function(DriveDownloadReview) review,
    void Function(DriveTransferProgress)? onProgress,
  });

  /// Limpia únicamente el staging propio. false indica limpieza pendiente.
  Future<bool> discard(ValidatedDriveDownload candidate);
}
