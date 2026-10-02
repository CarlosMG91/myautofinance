import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../domain/local_restore.dart';
import '../domain/local_restore_candidate.dart';
import '../domain/local_backup_creation.dart';
import '../domain/local_backup_catalog.dart';
import 'backup_json.dart';
import 'backup_storage.dart';
import 'local_backup_service.dart';
import 'local_restore_candidate_service.dart';
import 'native_backup_persistence.dart';

/// Orquestación local, sin autorización implícita, rutas externas ni red.
final class LocalRestoreService implements LocalRestorer {
  LocalRestoreService({
    required this.active,
    required this.creator,
    required this.preparer,
    required this.catalog,
    required this.supportDirectory,
    NativeBackupPersistence? persistence,
  }) : _persistence = persistence ?? NativeBackupPersistence();
  final LocalRestoreActiveDatabase active;
  final LocalBackupService creator;
  final LocalRestoreCandidateService preparer;
  final LocalBackupCatalog catalog;
  final Future<Directory> Function() supportDirectory;
  final NativeBackupPersistence _persistence;
  late final _storage = BackupStorage(_persistence, DateTime.now);

  @override
  Future<LocalRestoreResult> restore(
    String backupId, {
    required bool confirmed,
  }) async {
    if (!confirmed) {
      return const LocalRestoreResult(LocalRestoreStatus.cancelled);
    }
    LocalRestoreResult result;
    String? operation;
    try {
      if (!backupUuid.hasMatch(backupId)) invalidBackupMetadata();
      final support = (await supportDirectory()).absolute.path;
      final root = p.join(support, 'sqlite');
      await _storage.safe(support, root);
      final lock = p.join(root, '.local-backups.lock');
      await _storage.safe(root, lock);
      result = await _persistence.exclusively(
        lock,
        () => active.exclusivelyForRestore(() async {
          // No iniciar otro intercambio con un diario pendiente (MA-TSK-056).
          final restore = Directory(p.join(root, 'local-backups', 'restore'));
          await _storage.safe(root, restore.path);
          if (await restore.exists()) {
            await for (final dir in restore.list(followLinks: false)) {
              await _storage.safe(root, dir.path);
              if (dir is! Directory) invalidBackupMetadata();
              await for (final file in dir.list(followLinks: false)) {
                if (p.basename(file.path).startsWith('journal-')) {
                  active.requireRecovery();
                  return const LocalRestoreResult(
                    LocalRestoreStatus.recoveryRequired,
                  );
                }
              }
            }
          }
          final candidate = await preparer.prepareUnderLock(root, backupId);
          operation = candidate.operationId;
          return _install(root, candidate);
        }),
      );
    } on LocalRestoreCandidateFailure catch (e) {
      return LocalRestoreResult(
        LocalRestoreStatus.rejected,
        candidateIssue: e.issue,
      );
    } on LocalBackupFailure catch (e) {
      return LocalRestoreResult(
        LocalRestoreStatus.rejected,
        candidateIssue: e.code == LocalBackupFailureCode.operationInProgress
            ? LocalRestoreCandidateIssue.operationInProgress
            : LocalRestoreCandidateIssue.storageFailure,
      );
    } catch (_) {
      return const LocalRestoreResult(LocalRestoreStatus.rejected);
    }
    if (result.status == LocalRestoreStatus.restored) {
      try {
        final maintenance = await catalog.maintainAfterRestore(
          restoreOperationId: operation!,
          outcome: LocalRestoreRetentionOutcome.confirmed,
          protectedBackupIds: {backupId},
        );
        return LocalRestoreResult(
          result.status,
          previousBackupId: result.previousBackupId,
          maintenancePending:
              result.maintenancePending || maintenance.incidents.isNotEmpty,
        );
      } catch (_) {
        return LocalRestoreResult(
          result.status,
          previousBackupId: result.previousBackupId,
          maintenancePending: true,
        );
      }
    }
    return result;
  }

  Future<LocalRestoreResult> _install(
    String root,
    ReadyLocalRestoreCandidate candidate,
  ) async {
    final stage = p.join(
      root,
      'local-backups',
      'restore',
      candidate.operationId,
    );
    final image = p.join(stage, 'autofinance.sqlite');
    if (candidate.relativePath !=
        'local-backups/restore/${candidate.operationId}/autofinance.sqlite') {
      invalidBackupMetadata();
    }
    await _storage.safe(root, image);
    await _checkImage(image, candidate);
    final activePath = p.join(root, 'autofinance.sqlite');
    final suffixes = ['', '-wal', '-shm', '-journal'];
    for (final suffix in suffixes) {
      await _storage.safe(root, '$activePath$suffix');
      final type = await FileSystemEntity.type(
        '$activePath$suffix',
        followLinks: false,
      );
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.notFound) {
        invalidBackupMetadata();
      }
    }
    final slots = await _storage.loadSlots(root);
    final catalogValue = slots.latest;
    if (catalogValue == null || slots.conflict || slots.damaged.isNotEmpty) {
      invalidBackupMetadata();
    }
    final previousEpoch = catalogValue['localRestoreEpoch'];
    final previousContrast = catalogValue['syncContrastRequired'];
    final newEpoch = const Uuid().v4();
    String? backup;
    CreatedLocalBackup? previousBackup;
    var usablePrevious = false;
    var exchangeStarted = false;
    var catalogAttempted = false;
    var sequence = 0;
    final previous = p.join(stage, 'previous');
    final failed = p.join(stage, 'failed');
    Future<void> journal(String phase) => _storage.writeEnvelope(
      root,
      p.join(stage, 'journal-${(sequence++).toString().padLeft(3, '0')}.json'),
      {
        'kind': 'autofinance.localRestoreJournal',
        'formatVersion': 1,
        'operationId': candidate.operationId,
        'candidateBackupId': candidate.backupId,
        'previousBackupId': backup,
        'previousDatasetId': previousBackup?.state.datasetId,
        'previousRevision': previousBackup == null
            ? null
            : '${previousBackup.state.revision}',
        'phase': phase,
        'previousUsable': usablePrevious,
        'previousEpoch': previousEpoch,
        'previousContrastRequired': previousContrast,
        'newEpoch': newEpoch,
        'candidateSha256': candidate.sha256,
        'candidateSizeBytes': '${candidate.sizeBytes}',
        'datasetId': candidate.image.state.datasetId,
        'revision': '${candidate.image.state.revision}',
      },
    );
    try {
      usablePrevious = await active.canOpenExisting();
      if (usablePrevious) {
        previousBackup = await creator.capturePreRestoreUnderLock(
          root,
          candidate.operationId,
        );
        backup = previousBackup.backupId;
      }
      await journal('protected');
      await active.close();
      await _checkImage(image, candidate);
      await _persistence.createDirectory(previous);
      await journal('isolating'); // Antes de mover cualquier original/sidecar.
      exchangeStarted = true;
      for (final suffix in suffixes) {
        final source = '$activePath$suffix';
        await _storage.safe(root, source);
        if (await File(source).exists()) {
          await _persistence.move(
            source,
            p.join(previous, 'autofinance.sqlite$suffix'),
          );
        }
      }
      await journal('installing');
      await _persistence.move(image, activePath);
      await _checkImage(activePath, candidate);
      await journal('installed');
      final opened = await active.reopenAndValidate();
      if (opened.schemaVersion != candidate.image.schemaVersion ||
          opened.applicationId != candidate.image.applicationId ||
          opened.state.datasetId != candidate.image.state.datasetId ||
          opened.state.revision != candidate.image.state.revision) {
        invalidBackupMetadata();
      }
      await journal('validated');
      // Recargar tras la captura: nunca perder la entrada automática recién creada.
      final value = (await _storage.loadSlots(root)).latest!;
      value['localRestoreEpoch'] = newEpoch;
      value['syncContrastRequired'] = true;
      catalogAttempted = true;
      await _storage.commitCatalog(root, value);
      await journal('completed');
    } catch (_) {
      try {
        await journal('rollingBack');
        if (exchangeStarted) {
          await active.close();
          await _persistence.createDirectory(failed);
          // Deducir movimientos que llegaron a disco aunque move lanzase después.
          final oldMain = File(p.join(previous, 'autofinance.sqlite'));
          final installed = !await File(image).exists();
          for (final suffix in suffixes) {
            final old = p.join(previous, 'autofinance.sqlite$suffix');
            final target = '$activePath$suffix';
            await _storage.safe(root, old);
            await _storage.safe(root, target);
            if ((installed || await oldMain.exists()) &&
                await File(target).exists()) {
              // Solo apartar un sidecar si el main ya se aisló o la candidata se instaló.
              // Sidecars aún originales se conservan y se devuelven con el main.
              if (installed || await File(old).exists()) {
                await _persistence.move(
                  target,
                  p.join(failed, 'autofinance.sqlite$suffix'),
                );
              }
            }
            if (await File(old).exists()) await _persistence.move(old, target);
          }
        }
        if (catalogAttempted) {
          final value = (await _storage.loadSlots(root)).latest!;
          value['localRestoreEpoch'] = previousEpoch;
          value['syncContrastRequired'] = previousContrast;
          await _storage.commitCatalog(root, value);
        }
        if (!usablePrevious) {
          throw const LocalBackupFailure(
            LocalBackupFailureCode.recoveryRequired,
          );
        }
        final restoredPrevious = await active.reopenAndValidate();
        if (previousBackup != null &&
            (restoredPrevious.state.datasetId !=
                    previousBackup.state.datasetId ||
                restoredPrevious.state.revision !=
                    previousBackup.state.revision)) {
          invalidBackupMetadata();
        }
        await journal('rolledBack');
        await _archive(root, stage, candidate.operationId);
        return LocalRestoreResult(
          LocalRestoreStatus.rolledBack,
          previousBackupId: backup,
        );
      } catch (_) {
        active.requireRecovery();
        return LocalRestoreResult(
          LocalRestoreStatus.recoveryRequired,
          previousBackupId: backup,
        );
      }
    }
    var pending = false;
    try {
      await _archive(root, stage, candidate.operationId);
      if (usablePrevious) {
        // El estado anterior ya está en el catálogo como copia consistente.
        // Retirar solamente los originales conocidos; no acumular otra retención.
        final archived = p.join(
          root,
          'local-backups',
          'diagnostics',
          candidate.operationId,
          'previous',
        );
        for (final suffix in suffixes) {
          final path = p.join(archived, 'autofinance.sqlite$suffix');
          await _storage.safe(root, path);
          if (await File(path).exists()) await _persistence.deleteFile(path);
        }
        await _persistence.deleteEmptyDirectory(archived);
      }
    } catch (_) {
      pending = true;
    }
    return LocalRestoreResult(
      LocalRestoreStatus.restored,
      previousBackupId: backup,
      maintenancePending: pending,
    );
  }

  Future<void> _archive(String root, String stage, String operation) async {
    final diagnostics = p.join(root, 'local-backups', 'diagnostics');
    await _storage.safe(root, diagnostics);
    await _persistence.createDirectory(diagnostics);
    final target = p.join(diagnostics, operation);
    await _storage.safe(root, stage);
    await _storage.safe(root, target);
    await _persistence.move(stage, target);
  }

  Future<void> _checkImage(
    String path,
    ReadyLocalRestoreCandidate candidate,
  ) async {
    if (await File(path).length() != candidate.sizeBytes ||
        (await sha256.bind(File(path).openRead()).first).toString() !=
            candidate.sha256) {
      throw const LocalRestoreCandidateFailure(
        LocalRestoreCandidateIssue.hashMismatch,
      );
    }
  }
}
