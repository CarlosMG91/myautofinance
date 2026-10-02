import '../domain/drive_access.dart';
import '../domain/drive_copy_locator.dart';
import '../domain/drive_reconciliation.dart';
import '../domain/drive_transfer.dart';
import '../domain/drive_upload.dart';
import '../domain/installation_sync_state.dart';

/// Decisiones comunes a ambas instalaciones. No hay exclusión atómica remota:
/// otro escritor puede publicar después de cualquier lectura o acuse.
final class ManualDriveReconciliation implements DriveReconciliation {
  ManualDriveReconciliation({
    required this.access,
    required this.copies,
    required this.state,
  });
  final DriveAccess access;
  final DriveCopyLocator copies;
  final InstallationSyncState state;
  bool _busy = false;

  @override
  Future<DriveReconciliationResult> query() => _query(download: false);

  Future<DriveReconciliationResult> _query({required bool download}) async {
    if (_busy) {
      return const DriveReconciliationResult(DriveReconciliationStatus.busy);
    }
    _busy = true;
    const unknown = DriveReconciliationResult(
      DriveReconciliationStatus.indeterminate,
    );
    try {
      final folder = access.snapshot.session?.folder;
      if (folder == null) return unknown;
      bool sameSession() =>
          access.snapshot.session?.account.permissionId == folder.accountId &&
          access.snapshot.session?.folder?.folderId == folder.folderId;
      final fileId = await state.readFileId(accountId: folder.accountId);
      if (fileId == null || !sameSession()) return unknown;
      final local = await state.inspect(
        accountId: folder.accountId,
        fileId: fileId,
      );
      final pending = local.pending;
      if (pending != null && pending.kind != SyncOperationKind.upload) {
        return unknown;
      }
      // Una primera creación pendiente conserva un ID provisional local.
      // Buscar sin él permite descubrir el archivo cuyo acuse se perdió.
      final found = await copies.findCopy(
        knownCopy: pending?.createsFile == true
            ? null
            : DriveCopyBinding(
                accountId: folder.accountId,
                folderId: folder.folderId,
                fileId: fileId,
              ),
      );
      if (!sameSession() ||
          found.account?.permissionId != folder.accountId ||
          found.folder?.folderId != folder.folderId ||
          found.status != DriveCopyStatus.present) {
        return unknown;
      }
      final remote = found.copy!;
      final version = remote.version;
      if (version == null || !RegExp(r'^[1-9][0-9]*$').hasMatch(version)) {
        return unknown;
      }
      final baseline = local.knownRemoteVersion;
      if (pending != null) {
        if (!pending.createsFile && remote.id != fileId) return unknown;
        final matches =
            pending.snapshotSha256 != null &&
            pending.snapshotMd5 != null &&
            remote.appProperties['uploadOperationId'] == pending.id &&
            remote.appProperties['snapshotSha256'] == pending.snapshotSha256 &&
            remote.md5Checksum == pending.snapshotMd5 &&
            remote.modifiedTime != null &&
            remote.size != null &&
            remote.size! > 0 &&
            (pending.createsFile ||
                (baseline != null &&
                    BigInt.parse(version) > BigInt.parse(baseline)));
        if (matches) {
          await state.completeUpload(operationId: pending.id, remote: remote);
          return DriveReconciliationResult(
            DriveReconciliationStatus.uploaded,
            remote: remote,
          );
        }
        // Misma marca con hashes incoherentes no acredita éxito ni conflicto.
        if (remote.appProperties['uploadOperationId'] == pending.id) {
          return unknown;
        }
      }
      final conflict =
          baseline != null && baseline != version ||
          pending?.createsFile == true;
      if (conflict) {
        // recordCheck cambia identidad y borraría una creación pendiente.
        if (remote.id == fileId) {
          await state.recordCheck(accountId: folder.accountId, remote: remote);
        }
        if (download && pending != null) {
          await state.abandonPending(operationId: pending.id);
        }
        return DriveReconciliationResult(
          DriveReconciliationStatus.conflict,
          remote: remote,
        );
      }
      if (pending != null || baseline == null || local.remoteChanged) {
        return unknown;
      }
      await state.recordCheck(accountId: folder.accountId, remote: remote);
      return DriveReconciliationResult(
        DriveReconciliationStatus.current,
        remote: remote,
      );
    } catch (_) {
      // Red, OAuth, disco o epoch restaurado: conservar pendiente para consulta.
      return unknown;
    } finally {
      _busy = false;
    }
  }

  @override
  Future<bool> choose(DriveConflictChoice choice) async {
    if (choice == DriveConflictChoice.keepLocal) return false;
    final result = await _query(download: true);
    return result.status == DriveReconciliationStatus.conflict ||
        result.status == DriveReconciliationStatus.current ||
        result.status == DriveReconciliationStatus.uploaded;
  }
}

/// Punto de entrada manual: al repetir una subida pendiente se consulta, y
/// esta pulsación nunca envía otra operación, ni siquiera tras reconocer éxito.
final class ReconcilingDriveUploader implements DriveUploader {
  ReconcilingDriveUploader({
    required this.uploader,
    required this.reconciliation,
    required this.access,
    required this.state,
  });
  final DriveUploader uploader;
  final DriveReconciliation reconciliation;
  final DriveAccess access;
  final InstallationSyncState state;
  bool _busy = false;

  @override
  Future<DriveUploadResult> upload({
    required DriveTransferCancellation cancellation,
    void Function(DriveTransferProgress)? onProgress,
  }) async {
    if (_busy) {
      return const DriveUploadResult(DriveUploadStatus.reconciliationRequired);
    }
    _busy = true;
    try {
      if (cancellation.isCancelled) {
        return const DriveUploadResult(DriveUploadStatus.cancelled);
      }
      final account = access.snapshot.session?.account.permissionId;
      if (account == null) {
        return const DriveUploadResult(DriveUploadStatus.remoteUnavailable);
      }
      final fileId = await state.readFileId(accountId: account);
      final local = fileId == null
          ? null
          : await state.inspect(accountId: account, fileId: fileId);
      if (local?.pending != null) {
        final result = await reconciliation.query();
        return DriveUploadResult(
          switch (result.status) {
            DriveReconciliationStatus.uploaded => DriveUploadStatus.uploaded,
            DriveReconciliationStatus.conflict => DriveUploadStatus.divergence,
            _ => DriveUploadStatus.reconciliationRequired,
          },
          remote: result.status == DriveReconciliationStatus.uploaded
              ? result.remote
              : null,
        );
      }
      return await uploader.upload(
        cancellation: cancellation,
        onProgress: onProgress,
      );
    } catch (_) {
      return const DriveUploadResult(DriveUploadStatus.reconciliationRequired);
    } finally {
      _busy = false;
    }
  }
}
