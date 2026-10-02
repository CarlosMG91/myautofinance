import '../../../core/persistence/unit_of_work.dart';
import '../domain/drive_access.dart';
import '../domain/drive_copy_locator.dart';
import '../domain/drive_download.dart';
import '../domain/drive_download_application.dart';
import '../domain/drive_transfer.dart';
import '../domain/local_restore.dart';
import 'local_restore_service.dart';
import 'stored_installation_sync_state.dart';

/// Ninguna llamada remota en construcción, recuperación o reinicio.
final class SafeDriveDownloadApplication implements DriveDownloadApplication {
  SafeDriveDownloadApplication({
    required this.downloader,
    required this.restorer,
    required this.syncState,
    required this.access,
    required this.copies,
    required this.readDataset,
  });
  final DriveDownloader downloader;
  final LocalRestoreService restorer;
  final StoredInstallationSyncState syncState;
  final DriveAccess access;
  final DriveCopyLocator copies;
  final Future<DatasetState> Function() readDataset;
  bool _busy = false;

  @override
  Future<DriveDownloadApplicationResult> downloadAndApply({
    required DriveTransferCancellation cancellation,
    required Future<bool> Function(DriveDownloadReview) review,
    void Function(DriveTransferProgress)? onProgress,
  }) async {
    if (_busy) {
      return const DriveDownloadApplicationResult(
        DriveDownloadApplicationStatus.busy,
      );
    }
    _busy = true;
    DriveDownloadResult? download;
    LocalRestoreResult? restored;
    ValidatedDriveDownload? candidate;
    var status = DriveDownloadApplicationStatus.failed;
    var cleanupPending = false;
    var committed = false;
    String? operationId;
    void checkCancellation() {
      if (cancellation.isCancelled) {
        throw const _Stop(DriveDownloadApplicationStatus.cancelled);
      }
    }

    try {
      checkCancellation();
      await restorer.resolveDownloadState(syncState.abandonInterruptedDownload);
      download = await downloader.download(
        cancellation: cancellation,
        review: review,
        onProgress: onProgress,
      );
      candidate = download.candidate;
      cleanupPending = download.cleanupPending;
      if (download.status != DriveDownloadStatus.ready || candidate == null) {
        status = download.status == DriveDownloadStatus.cancelled
            ? DriveDownloadApplicationStatus.cancelled
            : DriveDownloadApplicationStatus.downloadRejected;
      } else {
        final image = candidate;
        restored = await restorer.restoreImage(
          path: image.path,
          sha256: image.sha256,
          sizeBytes: image.remote.size!,
          beforePrepare: () async {
            checkCancellation();
            final folder = access.snapshot.session?.folder;
            if (folder?.accountId != image.accountId ||
                folder?.folderId != image.folderId) {
              status = DriveDownloadApplicationStatus.remoteChanged;
              throw const _Stop(DriveDownloadApplicationStatus.remoteChanged);
            }
            final fresh = await copies.findCopy(
              knownCopy: DriveCopyBinding(
                accountId: image.accountId,
                folderId: image.folderId,
                fileId: image.remote.id,
              ),
            );
            checkCancellation();
            final session = access.snapshot.session;
            final remote = fresh.copy;
            if (fresh.status != DriveCopyStatus.present ||
                fresh.account?.permissionId != image.accountId ||
                fresh.folder?.folderId != image.folderId ||
                session?.account.permissionId != image.accountId ||
                session?.folder?.folderId != image.folderId ||
                remote?.id != image.remote.id ||
                remote?.version != image.remote.version ||
                remote?.size != image.remote.size ||
                remote?.md5Checksum != image.remote.md5Checksum ||
                remote?.modifiedTime != image.remote.modifiedTime) {
              status = DriveDownloadApplicationStatus.remoteChanged;
              throw const _Stop(DriveDownloadApplicationStatus.remoteChanged);
            }
            final local = await readDataset();
            final contrast = await syncState.contrastReader.read();
            if (local.datasetId != image.localState.datasetId ||
                local.revision != image.localState.revision ||
                contrast.unreliable ||
                (image.localContrast != null &&
                    (contrast.restoreEpoch !=
                            image.localContrast!.restoreEpoch ||
                        contrast.required != image.localContrast!.required))) {
              status = DriveDownloadApplicationStatus.localChanged;
              throw const _Stop(DriveDownloadApplicationStatus.localChanged);
            }
            final pending = await syncState.beginDownload(
              accountId: image.accountId,
              remote: image.remote,
              downloadedImage: image.image.state,
            );
            operationId = pending.id;
          },
          checkCancellation: () async => checkCancellation(),
          onValidated: (epoch) async {
            checkCancellation();
            final session = access.snapshot.session;
            if (session?.account.permissionId != image.accountId ||
                session?.folder?.folderId != image.folderId) {
              throw const _Stop(DriveDownloadApplicationStatus.remoteChanged);
            }
            await syncState.installDownload(
              operationId: operationId!,
              downloadedRemote: image.remote,
              validatedRestoreEpoch: epoch,
              install: () async =>
                  const LocalRestoreResult(LocalRestoreStatus.restored),
            );
            committed = true;
          },
        );
        status = switch (restored.status) {
          LocalRestoreStatus.restored =>
            DriveDownloadApplicationStatus.downloaded,
          LocalRestoreStatus.recoveryRequired =>
            DriveDownloadApplicationStatus.recoveryRequired,
          LocalRestoreStatus.rolledBack =>
            cancellation.isCancelled
                ? DriveDownloadApplicationStatus.cancelled
                : DriveDownloadApplicationStatus.rolledBack,
          _ =>
            cancellation.isCancelled
                ? DriveDownloadApplicationStatus.cancelled
                : status,
        };
        // Un rechazo/rollback no se anuncia sincronizado. Una interrupción deja
        // pending durable; EP-006 resuelve SQLite antes de cualquier contraste.
        if (!committed &&
            operationId != null &&
            restored.status != LocalRestoreStatus.recoveryRequired) {
          await syncState.abandonPending(operationId: operationId!);
        }
      }
    } catch (_) {
      status = cancellation.isCancelled
          ? DriveDownloadApplicationStatus.cancelled
          : DriveDownloadApplicationStatus.failed;
    } finally {
      if (candidate != null) {
        cleanupPending = !await downloader.discard(candidate) || cleanupPending;
      }
      _busy = false;
    }
    return DriveDownloadApplicationResult(
      status,
      download: download,
      restore: restored,
      remote: status == DriveDownloadApplicationStatus.downloaded
          ? candidate?.remote
          : null,
      cleanupPending: cleanupPending,
    );
  }
}

final class _Stop implements Exception {
  const _Stop(this.status);
  final DriveDownloadApplicationStatus status;
}
