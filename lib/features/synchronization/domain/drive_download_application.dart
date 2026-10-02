import 'drive_download.dart';
import 'drive_metadata.dart';
import 'drive_transfer.dart';
import 'local_restore.dart';

enum DriveDownloadApplicationStatus {
  downloaded,
  cancelled,
  busy,
  downloadRejected,
  localChanged,
  remoteChanged,
  rolledBack,
  recoveryRequired,
  failed,
}

final class DriveDownloadApplicationResult {
  const DriveDownloadApplicationResult(
    this.status, {
    this.download,
    this.restore,
    this.remote,
    this.cleanupPending = false,
  });
  final DriveDownloadApplicationStatus status;
  final DriveDownloadResult? download;
  final LocalRestoreResult? restore;
  final DriveFileMetadata? remote;
  final bool cleanupPending;
  String get message => switch (status) {
    DriveDownloadApplicationStatus.downloaded =>
      'Copia descargada. El estado anterior sigue recuperable.',
    DriveDownloadApplicationStatus.cancelled =>
      'Descarga cancelada. Se conservan tus datos locales.',
    DriveDownloadApplicationStatus.recoveryRequired =>
      'La descarga necesita recuperación local. El acceso queda bloqueado.',
    _ => 'No se descargó la copia; tus datos locales siguen disponibles.',
  };
}

abstract interface class DriveDownloadApplication {
  /// Solo desde «Descargar última copia»; la revisión obtiene confirmación
  /// expresa cuando hay cambios o no se conoce la relación con Drive.
  Future<DriveDownloadApplicationResult> downloadAndApply({
    required DriveTransferCancellation cancellation,
    required Future<bool> Function(DriveDownloadReview) review,
    void Function(DriveTransferProgress)? onProgress,

    /// Imagen validada; comienza respaldo, sustitución y apertura segura.
    void Function()? onApplying,
  });
}
