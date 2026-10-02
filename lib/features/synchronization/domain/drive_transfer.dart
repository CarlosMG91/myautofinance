import 'dart:async';

import 'drive_metadata.dart';

enum DriveTransferIssue {
  cancelled,
  remoteFailure,
  ambiguousResponse,
  invalidResponse,
  localIoFailure,
  invalidRequest,
}

/// No incluye mensajes del servidor, rutas, sesiones ni contenido financiero.
final class DriveTransferFailure implements Exception {
  const DriveTransferFailure(this.issue, {this.remoteFailure});
  final DriveTransferIssue issue;
  final DriveMetadataFailure? remoteFailure;
  @override
  String toString() =>
      'DriveTransferFailure(${issue.name}, '
      '${remoteFailure?.issue.name})';
}

final class DriveTransferCancellation {
  final _signal = Completer<void>();
  bool get isCancelled => _signal.isCompleted;
  Future<void> get whenCancelled => _signal.future;
  void cancel() {
    if (!_signal.isCompleted) _signal.complete();
  }
}

enum DriveTransferPhase { transferring, beforeCommit, committing, complete }

final class DriveTransferProgress {
  const DriveTransferProgress(this.bytes, this.total, this.phase);
  final int bytes;
  final int total;
  final DriveTransferPhase phase;
}

/// Un temporal completo sigue siendo una candidata: no acredita validez SQLite.
final class DriveDownloadCandidate {
  const DriveDownloadCandidate({required this.path, required this.bytes});
  final String path;
  final int bytes;
  @override
  String toString() => 'DriveDownloadCandidate';
}

abstract interface class DriveTransferClient {
  /// sourcePath debe ser un snapshot privado, validado e inmutable.
  /// fileId actualiza la copia conocida; null crea la primera dentro de folderId.
  /// beforeCommit revalida divergencia y solicita autorización del flujo manual.
  /// Al enviar el último bloque ya no se garantiza cancelar el commit remoto.
  Future<DriveFileMetadata> upload({
    required String accountId,
    required String folderId,
    String? fileId,
    required String sourcePath,
    required DriveTransferCancellation cancellation,
    required Future<void> Function() beforeCommit,
    void Function(DriveTransferProgress)? onProgress,
  });

  /// Escribe exclusivamente en un nuevo temporal privado. El consumidor valida,
  /// restaura mediante EP-006 y elimina la candidata; nunca es la base activa.
  Future<DriveDownloadCandidate> download({
    required String accountId,
    required String fileId,
    required int expectedBytes,
    required String temporaryDirectory,
    required DriveTransferCancellation cancellation,
    void Function(DriveTransferProgress)? onProgress,
  });
}
