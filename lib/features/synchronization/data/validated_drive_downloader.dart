import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../core/persistence/unit_of_work.dart';
import '../domain/drive_access.dart';
import '../domain/drive_copy_locator.dart';
import '../domain/drive_download.dart';
import '../domain/drive_metadata.dart';
import '../domain/drive_transfer.dart';
import '../domain/installation_sync_state.dart';
import '../domain/local_restore_candidate.dart';
import '../domain/local_sync_contrast.dart';

/// Sin instalación, escritura de estado sync, OAuth implícito ni reintentos.
final class ValidatedDriveDownloader implements DriveDownloader {
  ValidatedDriveDownloader({
    required this.access,
    required this.copies,
    required this.transfers,
    required this.readSyncState,
    required this.readDataset,
    required this.readContrast,
    required this.policy,
    required this.temporaryDirectory,
  });
  final DriveAccess access;
  final DriveCopyLocator copies;
  final DriveTransferClient transfers;
  final Future<InstallationSyncSnapshot> Function(
    String accountId,
    String fileId,
  )
  readSyncState;
  final Future<DatasetState> Function() readDataset;
  final Future<LocalSyncContrast> Function() readContrast;
  final LocalRestoreImagePolicy policy;
  final Future<Directory> Function() temporaryDirectory;
  final _owned = <ValidatedDriveDownload, Directory>{};
  bool _busy = false;

  void _check(DriveTransferCancellation cancellation) {
    if (cancellation.isCancelled) {
      throw const _Stop(DriveDownloadStatus.cancelled);
    }
  }

  bool _same(DatasetState a, DatasetState b) =>
      a.datasetId == b.datasetId && a.revision == b.revision;

  Future<void> _safe(String root, String path) async {
    if (path != root && !p.isWithin(root, path)) {
      throw const _Stop(DriveDownloadStatus.failed);
    }
    var current = path;
    while (true) {
      if (await FileSystemEntity.type(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const _Stop(DriveDownloadStatus.failed);
      }
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
    }
  }

  Future<bool> _clean(Directory staging) async {
    try {
      await _safe(staging.parent.path, staging.path);
      if (await FileSystemEntity.type(staging.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        return false;
      }
      // La raíz fue creada por esta operación; nunca es soporte ni base activa.
      await staging.delete(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> discard(ValidatedDriveDownload candidate) async {
    final staging = _owned[candidate];
    if (staging == null) return false;
    if (!await _clean(staging)) return false;
    _owned.remove(candidate);
    return true;
  }

  @override
  Future<DriveDownloadResult> download({
    required DriveTransferCancellation cancellation,
    required Future<bool> Function(DriveDownloadReview) review,
    void Function(DriveTransferProgress)? onProgress,
  }) async {
    if (_busy) return const DriveDownloadResult(DriveDownloadStatus.busy);
    _busy = true;
    Directory? staging;
    ValidatedDriveDownload? candidate;
    var status = DriveDownloadStatus.failed;
    LocalRestoreCandidateIssue? imageIssue;
    DriveTransferFailure? transferFailure;
    var cleanupPending = false;
    try {
      _check(cancellation);
      final folder = access.snapshot.session?.folder;
      if (folder == null) {
        throw const _Stop(DriveDownloadStatus.remoteUnavailable);
      }
      final account = folder.accountId;
      void checkSession() {
        final session = access.snapshot.session;
        if (session?.account.permissionId != account ||
            session?.folder?.folderId != folder.folderId) {
          throw const _Stop(DriveDownloadStatus.remoteUnavailable);
        }
      }

      final initial = await copies.findCopy();
      _check(cancellation);
      checkSession();
      if (initial.status == DriveCopyStatus.noCopy) {
        throw const _Stop(DriveDownloadStatus.noCopy);
      }
      if (initial.status != DriveCopyStatus.present ||
          initial.account?.permissionId != account ||
          initial.folder?.folderId != folder.folderId) {
        throw _Stop(
          initial.metadataFailure?.issue ==
                  DriveMetadataIssue.incompleteResponse
              ? DriveDownloadStatus.invalidMetadata
              : DriveDownloadStatus.remoteUnavailable,
        );
      }
      final remote = initial.copy!;
      final size = remote.size;
      if (size == null ||
          size <= 0 ||
          (remote.md5Checksum != null &&
              !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(remote.md5Checksum!))) {
        throw const _Stop(DriveDownloadStatus.invalidMetadata);
      }
      final sync = await readSyncState(account, remote.id);
      final contrast = await readContrast();
      if (sync.pending != null || sync.localStatus == SyncLocalStatus.pending) {
        throw const _Stop(DriveDownloadStatus.reconciliationRequired);
      }
      final local = await readDataset();
      final localStatus =
          sync.localStatus == SyncLocalStatus.clean &&
              (sync.correspondingLocalState == null ||
                  !_same(local, sync.correspondingLocalState!))
          ? SyncLocalStatus.changed
          : sync.localStatus;
      _check(cancellation);
      final accepted = await Future.any<bool>([
        review(
          DriveDownloadReview(
            accountId: account,
            remote: remote,
            localStatus: localStatus,
          ),
        ),
        cancellation.whenCancelled.then((_) => false),
      ]);
      _check(cancellation);
      if (!accepted) throw const _Stop(DriveDownloadStatus.cancelled);
      checkSession();
      if (!_same(local, await readDataset())) {
        throw const _Stop(DriveDownloadStatus.localChanged);
      }
      final base = (await temporaryDirectory()).absolute;
      await _safe(base.parent.path, base.path);
      await base.create(recursive: true);
      staging = await base.createTemp('validated-drive-');
      final downloaded = await transfers.download(
        accountId: account,
        fileId: remote.id,
        expectedBytes: size,
        temporaryDirectory: staging.path,
        cancellation: cancellation,
        onProgress: (progress) {
          // Complete del transporte no significa validación ni instalación.
          if (progress.phase != DriveTransferPhase.complete) {
            onProgress?.call(progress);
          }
        },
      );
      _check(cancellation);
      final path = p.normalize(p.absolute(downloaded.path));
      await _safe(staging.path, path);
      final file = File(path);
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const _Stop(DriveDownloadStatus.invalidImage);
      }
      if (downloaded.bytes != size || await file.length() != size) {
        throw const _Stop(DriveDownloadStatus.sizeMismatch);
      }
      final checksum = (await md5.bind(file.openRead()).first).toString();
      if (remote.md5Checksum != null &&
          checksum != remote.md5Checksum!.toLowerCase()) {
        throw const _Stop(DriveDownloadStatus.hashMismatch);
      }
      final sha = (await sha256.bind(file.openRead()).first).toString();
      _check(cancellation);
      final image = await policy.inspect(path);
      _check(cancellation);
      if ((await sha256.bind(file.openRead()).first).toString() != sha) {
        throw const _Stop(DriveDownloadStatus.hashMismatch);
      }
      final fresh = await copies.findCopy(
        knownCopy: DriveCopyBinding(
          accountId: account,
          folderId: folder.folderId,
          fileId: remote.id,
        ),
      );
      _check(cancellation);
      checkSession();
      if (fresh.status == DriveCopyStatus.inaccessible) {
        throw const _Stop(DriveDownloadStatus.remoteUnavailable);
      }
      if (fresh.status != DriveCopyStatus.present ||
          fresh.account?.permissionId != account ||
          fresh.folder?.folderId != folder.folderId ||
          fresh.copy?.id != remote.id ||
          fresh.copy?.version != remote.version ||
          fresh.copy?.size != remote.size ||
          fresh.copy?.md5Checksum != remote.md5Checksum ||
          fresh.copy?.modifiedTime != remote.modifiedTime) {
        throw const _Stop(DriveDownloadStatus.remoteChanged);
      }
      final finalSync = await readSyncState(account, remote.id);
      final finalContrast = await readContrast();
      if (finalSync.pending != null ||
          finalContrast.restoreEpoch != contrast.restoreEpoch ||
          finalContrast.required != contrast.required ||
          finalContrast.unreliable != contrast.unreliable ||
          finalSync.localStatus != sync.localStatus ||
          !_same(local, await readDataset())) {
        throw const _Stop(DriveDownloadStatus.localChanged);
      }
      _check(cancellation);
      candidate = ValidatedDriveDownload(
        path: path,
        remote: remote,
        accountId: account,
        folderId: folder.folderId,
        image: image,
        sha256: sha,
        localState: local,
      );
      _owned[candidate] = staging;
      status = DriveDownloadStatus.ready;
    } on _Stop catch (e) {
      status = e.status;
    } on LocalRestoreCandidateFailure catch (e) {
      status = DriveDownloadStatus.invalidImage;
      imageIssue = e.issue;
    } on DriveTransferFailure catch (e) {
      transferFailure = e;
      status = e.issue == DriveTransferIssue.cancelled
          ? DriveDownloadStatus.cancelled
          : DriveDownloadStatus.failed;
    } catch (_) {
      status = DriveDownloadStatus.failed;
    } finally {
      if (candidate == null && staging != null) {
        cleanupPending = !await _clean(staging);
      }
      _busy = false;
    }
    return DriveDownloadResult(
      status,
      candidate: candidate,
      imageIssue: imageIssue,
      transferFailure: transferFailure,
      cleanupPending: cleanupPending,
    );
  }
}

final class _Stop implements Exception {
  const _Stop(this.status);
  final DriveDownloadStatus status;
}
