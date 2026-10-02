import 'package:flutter/foundation.dart';

import '../domain/drive_download.dart';
import '../domain/drive_download_application.dart';
import '../domain/drive_metadata.dart';
import '../domain/drive_transfer.dart';
import '../domain/drive_upload.dart';
import '../domain/installation_sync_state.dart';
import '../domain/local_restore_candidate.dart';

enum DriveRemoteKnowledge { unknown, known, noCopy }

/// Metadatos locales: leerlos nunca implica comprobar Drive.
class DriveViewSnapshot {
  const DriveViewSnapshot({
    this.account,
    this.version,
    this.referenceVersion,
    this.date,
    this.localStatus = SyncLocalStatus.unknown,
  });
  final String? account;
  final String? version;
  final String? referenceVersion;
  final DateTime? date;
  final SyncLocalStatus localStatus;
}

class DriveController extends ChangeNotifier {
  DriveController({
    required this.uploader,
    required this.downloader,
    required this.readLocal,
    required this.prepare,
    this.cancelAuthorization,
    this.onRecoveryRequired,
    this.unavailableReason,
  });
  final DriveUploader? uploader;
  final DriveDownloadApplication? downloader;
  final Future<DriveViewSnapshot> Function() readLocal;
  final Future<String?> Function(bool upload) prepare;
  final VoidCallback? cancelAuthorization;
  final Future<void> Function()? onRecoveryRequired;
  final String? unavailableReason;
  DriveViewSnapshot snapshot = const DriveViewSnapshot();
  DriveRemoteKnowledge remoteKnowledge = DriveRemoteKnowledge.unknown;
  DriveFileMetadata? observed;
  String? message;
  String? backupId;
  String phase = '';
  bool busy = false;
  bool conflict = false;
  bool error = false;
  bool cancellationAllowed = true;
  bool recoveryBlocked = false;
  DriveTransferCancellation? _cancellation;
  bool _disposed = false;
  bool get available => unavailableReason == null && !recoveryBlocked;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refreshLocal() async {
    try {
      snapshot = await readLocal();
      if (snapshot.version != null &&
          remoteKnowledge == DriveRemoteKnowledge.unknown) {
        remoteKnowledge = DriveRemoteKnowledge.known;
      }
    } catch (_) {
      message =
          'No se pudo leer el estado local de Drive. Reintenta manualmente.';
      error = true;
    }
    _notify();
  }

  void cancel() {
    if (!busy || !cancellationAllowed) return;
    _cancellation?.cancel();
    cancelAuthorization?.call();
    phase = 'Cancelando; espera el resultado seguro';
    _notify();
  }

  void keepLocal() {
    conflict = false;
    message = 'Se conservan tus datos locales.';
    _notify();
  }

  Future<void> run({
    required bool upload,
    required Future<bool> Function(DriveDownloadReview) review,
  }) async {
    if (busy || !available) return;
    busy = true;
    error = false;
    conflict = false;
    message = null;
    backupId = null;
    cancellationAllowed = true;
    final cancellation = DriveTransferCancellation();
    _cancellation = cancellation;
    phase = 'Comprobando cuenta y versión';
    _notify();
    try {
      final problem = await prepare(upload);
      if (problem == null && !cancellation.isCancelled) {
        await refreshLocal();
      }
      if (cancellation.isCancelled) {
        message = 'Operación cancelada. Se conservan tus datos locales.';
      } else if (problem != null) {
        message = problem;
        error = true;
      } else if (upload) {
        final result = await uploader!.upload(
          cancellation: cancellation,
          onProgress: (p) => _progress(p, true),
        );
        observed = result.remote ?? observed;
        message = result.status == DriveUploadStatus.reconciliationRequired
            ? 'No se pudo confirmar la subida. Reintenta manualmente para comprobar Drive.'
            : result.message;
        conflict =
            result.status == DriveUploadStatus.divergence ||
            result.status == DriveUploadStatus.comparisonRequired;
        error =
            result.status != DriveUploadStatus.uploaded &&
            result.status != DriveUploadStatus.cancelled;
        if (result.remote != null) remoteKnowledge = DriveRemoteKnowledge.known;
        if (result.transferFailure != null) {
          message = '$message ${_failure(result.transferFailure!)}';
        }
      } else {
        phase = 'Comprobando versión';
        _notify();
        final result = await downloader!.downloadAndApply(
          cancellation: cancellation,
          review: (value) async {
            observed = value.remote;
            remoteKnowledge = DriveRemoteKnowledge.known;
            phase = value.requiresConfirmation
                ? 'Esperando confirmación'
                : 'Preparando descarga';
            _notify();
            final accepted = await review(value);
            phase = 'Descargando, validando y preparando respaldo seguro';
            _notify();
            return accepted && !cancellation.isCancelled;
          },
          onProgress: (p) => _progress(p, false),
          onApplying: () {
            phase = 'Creando respaldo y sustituyendo/abriendo la base';
            _notify();
          },
        );
        message = result.message;
        observed = result.remote ?? observed;
        backupId = result.restore?.previousBackupId;
        if (result.restore?.candidateIssue != null) {
          message = '$message ${result.restore!.candidateIssue!.message}';
        }
        error =
            result.status != DriveDownloadApplicationStatus.downloaded &&
            result.status != DriveDownloadApplicationStatus.cancelled;
        final rejected = result.download;
        if (rejected?.status == DriveDownloadStatus.noCopy) {
          remoteKnowledge = DriveRemoteKnowledge.noCopy;
          observed = null;
          message = 'No hay ninguna copia en Drive. Puedes subir una copia de este dispositivo.';
          error = false;
        } else if (rejected != null &&
            rejected.status != DriveDownloadStatus.ready &&
            error) {
          message = '$message ${_downloadReason(rejected.status)}';
          if (rejected.transferFailure != null) {
            message = '$message ${_failure(rejected.transferFailure!)}';
          }
          if (rejected.imageIssue != null) {
            message = '$message ${rejected.imageIssue!.message}';
          }
        } else if (result.status ==
                DriveDownloadApplicationStatus.localChanged ||
            result.status == DriveDownloadApplicationStatus.remoteChanged) {
          message =
              '$message La versión remota o los datos locales cambiaron durante la operación.';
        }
        if (result.status == DriveDownloadApplicationStatus.recoveryRequired) {
          recoveryBlocked = true;
          await onRecoveryRequired?.call();
        }
      }
    } catch (_) {
      error = true;
      message = 'No se pudo completar la operación. Reintenta manualmente desde el botón correspondiente.';
    } finally {
      if (!recoveryBlocked) {
        await refreshLocal();
      }
      busy = false;
      _cancellation = null;
      phase = '';
      _notify();
    }
  }

  void _progress(DriveTransferProgress p, bool upload) {
    if (_cancellation?.isCancelled == true) return;
    if (upload) {
      cancellationAllowed =
          p.phase != DriveTransferPhase.committing &&
          p.phase != DriveTransferPhase.complete;
      phase = switch (p.phase) {
        DriveTransferPhase.transferring => 'Subiendo copia',
        DriveTransferPhase.beforeCommit =>
          'Comprobando versión antes de publicar',
        _ => 'Confirmando publicación; espera el resultado',
      };
    } else {
      phase = 'Descargando, validando y preparando respaldo seguro';
    }
    _notify();
  }

  String _failure(DriveTransferFailure f) => switch (f.remoteFailure?.issue) {
    DriveMetadataIssue.credentialExpired ||
    DriveMetadataIssue.permissionDenied =>
      'Revisa la autorización de la cuenta.',
    DriveMetadataIssue.networkFailure ||
    DriveMetadataIssue.requestTimeout ||
    DriveMetadataIssue.serverUnavailable => 'Comprueba la conexión.',
    DriveMetadataIssue.quotaExceeded => 'La cuota de Drive está agotada.',
    _ =>
      f.issue == DriveTransferIssue.ambiguousResponse
          ? 'La respuesta de Drive es incierta.'
          : 'Falló la transferencia de la copia.',
  };
  String _downloadReason(DriveDownloadStatus s) => switch (s) {
    DriveDownloadStatus.invalidImage ||
    DriveDownloadStatus.hashMismatch ||
    DriveDownloadStatus.sizeMismatch ||
    DriveDownloadStatus.invalidMetadata =>
      'La copia remota no superó la validación.',
    DriveDownloadStatus.remoteChanged =>
      'La copia remota cambió; vuelve a consultar manualmente.',
    DriveDownloadStatus.localChanged =>
      'Los datos locales cambiaron; revisa antes de repetir.',
    DriveDownloadStatus.reconciliationRequired => 'Hay una subida pendiente de comprobar; pulsa Subir copia para contrastarla.',
    DriveDownloadStatus.remoteUnavailable =>
      'No se pudo consultar Drive; comprueba cuenta y conexión.',
    _ => 'No se pudo completar la descarga.',
  };
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
