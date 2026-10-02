import 'drive_metadata.dart';
import 'drive_download.dart';
import 'drive_transfer.dart';

enum DriveReconciliationStatus {
  current,
  uploaded,
  conflict,
  indeterminate,
  busy,
}

enum DriveConflictChoice { keepLocal, downloadLatest }

final class DriveReconciliationResult {
  const DriveReconciliationResult(this.status, {this.remote});
  final DriveReconciliationStatus status;
  final DriveFileMetadata? remote;
  bool get requiresNewQuery =>
      status == DriveReconciliationStatus.indeterminate;
  List<DriveConflictChoice> get choices => const [
    DriveConflictChoice.keepLocal,
    DriveConflictChoice.downloadLatest,
  ];
  String get message => switch (status) {
    DriveReconciliationStatus.current => 'La versión consultada coincide',
    DriveReconciliationStatus.uploaded =>
      'Copia subida; publicación comprobada en Drive',
    DriveReconciliationStatus.conflict =>
      'Hay una copia más reciente en Drive; no se ha subido tu copia local',
    DriveReconciliationStatus.indeterminate => 'Resultado indeterminado. Vuelve a consultar Drive antes de continuar; no se reenviará la copia',
    DriveReconciliationStatus.busy => 'Hay una comprobación en curso',
  };
}

abstract interface class DriveReconciliation {
  /// Consulta manual. Nunca publica ni descarga bytes, ni presume que una
  /// versión sin nuestra marca demuestra que la petición anterior no llegará.
  Future<DriveReconciliationResult> query();

  /// Conservar no escribe. Descargar consulta de nuevo y únicamente libera
  /// el bloqueo local si el conflicto está confirmado; el flujo de descarga
  /// mantiene su revisión, validación y confirmación de pérdida propias.
  Future<bool> choose(DriveConflictChoice choice);
}

/// Acciones del diálogo. Entrega staging validado; nunca aplica la base.
final class DriveConflictFlow {
  DriveConflictFlow({required this.reconciliation, required this.downloader});
  final DriveReconciliation reconciliation;
  final DriveDownloader downloader;
  String get keepLocalLabel => 'Conservar datos locales';
  String get downloadLabel => 'Descargar última copia';
  String get queryLabel => 'Volver a consultar Drive';

  Future<void> keepLocal() async {
    await reconciliation.choose(DriveConflictChoice.keepLocal);
  }

  Future<DriveDownloadResult> downloadLatest({
    required DriveTransferCancellation cancellation,
    required Future<bool> Function(DriveDownloadReview) review,
    void Function(DriveTransferProgress)? onProgress,
  }) async {
    if (cancellation.isCancelled) {
      return const DriveDownloadResult(DriveDownloadStatus.cancelled);
    }
    if (!await reconciliation.choose(DriveConflictChoice.downloadLatest)) {
      return const DriveDownloadResult(
        DriveDownloadStatus.reconciliationRequired,
      );
    }
    return downloader.download(
      cancellation: cancellation,
      review: review,
      onProgress: onProgress,
    );
  }
}
