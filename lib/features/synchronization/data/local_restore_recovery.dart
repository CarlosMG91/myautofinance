import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../domain/local_backup_creation.dart';
import '../domain/local_backup_catalog.dart';
import 'backup_catalog.dart';
import 'backup_json.dart';
import 'backup_storage.dart';
import 'local_restore_candidate_service.dart';
import 'local_backup_catalog_service.dart';
import 'native_backup_persistence.dart';

/// Se ejecuta sin conexiones abiertas y bajo el bloqueo nativo compartido.
/// No elimina copias ni originales: los intercambios quedan en diagnóstico.
final class LocalRestoreRecovery {
  LocalRestoreRecovery({
    required this.preparer,
    required this.validateActive,
    NativeBackupPersistence? persistence,
  }) : persistence = persistence ?? NativeBackupPersistence();

  final LocalRestoreCandidateService preparer;
  final Future<LocalBackupImage> Function(String) validateActive;
  final NativeBackupPersistence persistence;
  late final storage = BackupStorage(persistence, DateTime.now);

  Future<void> recover(String root) async {
    final restore = p.join(root, 'local-backups', 'restore');
    await storage.safe(root, restore);
    if (!await Directory(restore).exists()) return;
    final lock = p.join(root, '.local-backups.lock');
    await storage.safe(root, lock);
    final completed = <Map<String, dynamic>>[];
    await persistence.exclusively(lock, () async {
      final pending = <(String, Map<String, dynamic>)>[];
      await for (final dir in Directory(restore).list(followLinks: false)) {
        await storage.safe(root, dir.path);
        // Directorio temporal de createDirectory: aún no publicado. Su
        // existencia no autoriza intercambio y se conserva sin adoptarlo.
        final name = p.basename(dir.path);
        if (dir is Directory && name.endsWith('.next')) continue;
        if (dir is! Directory || !backupUuid.hasMatch(p.basename(dir.path))) {
          invalidBackupMetadata();
        }
        final journals = <File>[];
        await for (final file in dir.list(followLinks: false)) {
          await storage.safe(root, file.path);
          if (!p.basename(file.path).startsWith('journal-') ||
              p.basename(file.path).endsWith('.next')) {
            continue;
          }
          if (file is! File ||
              !RegExp(r'^journal-[0-9]{3}\.json$')
                  .hasMatch(p.basename(file.path))) {
            invalidBackupMetadata();
          }
          journals.add(file);
        }
        journals.sort((a, b) => a.path.compareTo(b.path));
        Map<String, dynamic>? latest;
        for (final file in journals) {
          final value = decodeBackupEnvelope(await file.readAsBytes());
          _check(value, p.basename(dir.path));
          if (latest != null) {
            for (final key in value.keys.where((key) => key != 'phase')) {
              if (value[key] != latest[key]) invalidBackupMetadata();
            }
          }
          latest = value;
        }
        if (latest != null) pending.add((dir.path, latest));
        // Sin diario confirmado no se ha autorizado mover la activa.
      }
      if (pending.length > 1) invalidBackupMetadata();
      for (final (stage, journal) in pending) {
        if (await _resolve(root, stage, journal)) completed.add(journal);
      }
    });
    // La poda usa su propio bloqueo y solo se solicita tras validar, confirmar
    // el catálogo y archivar el diario. Un fallo de mantenimiento no deshace
    // una recuperación completada ni impide usar una activa comprobada.
    for (final journal in completed) {
      try {
        await LocalBackupCatalogService(
          validator: _RecoveryValidator(validateActive),
          supportDirectory: () async => Directory(p.dirname(root)),
          persistence: persistence,
        ).maintainAfterRestore(
          restoreOperationId: journal['operationId'] as String,
          outcome: LocalRestoreRetentionOutcome.confirmed,
          protectedBackupIds: {journal['candidateBackupId'] as String},
        );
      } catch (_) {
        // Conservación segura: la siguiente restauración reintenta retención.
      }
    }
  }

  void _check(Map<String, dynamic> value, String operation) {
    backupObject(value, {
      'kind',
      'formatVersion',
      'operationId',
      'candidateBackupId',
      'previousBackupId',
      'previousDatasetId',
      'previousRevision',
      'phase',
      'previousUsable',
      'previousEpoch',
      'previousContrastRequired',
      'newEpoch',
      'candidateSha256',
      'candidateSizeBytes',
      'datasetId',
      'revision',
    });
    checkBackupFormat(value, 'autofinance.localRestoreJournal');
    if (value['operationId'] != operation ||
        !backupUuid.hasMatch(value['candidateBackupId'] as String) ||
        !backupUuid.hasMatch(value['newEpoch'] as String) ||
        !backupUuid.hasMatch(value['previousEpoch'] as String) ||
        !datasetUuid.hasMatch(value['datasetId'] as String) ||
        !backupHash.hasMatch(value['candidateSha256'] as String) ||
        value['previousContrastRequired'] is! bool ||
        value['previousUsable'] is! bool ||
        !{
          'protected',
          'isolating',
          'installing',
          'installed',
          'validated',
          'completed',
          'rollingBack',
          'rolledBack',
        }.contains(value['phase'])) {
      invalidBackupMetadata();
    }
    backupCounter(value['revision'], positive: false);
    backupCounter(value['candidateSizeBytes']);
    if (value['previousUsable'] == true) {
      if (!backupUuid.hasMatch(value['previousBackupId'] as String) ||
          !datasetUuid.hasMatch(value['previousDatasetId'] as String)) {
        invalidBackupMetadata();
      }
      backupCounter(value['previousRevision'], positive: false);
    } else if (value['previousBackupId'] != null ||
        value['previousDatasetId'] != null ||
        value['previousRevision'] != null) {
      invalidBackupMetadata();
    }
  }

  Future<bool> _resolve(
    String root,
    String stage,
    Map<String, dynamic> j,
  ) async {
    final active = p.join(root, 'autofinance.sqlite');
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      await storage.safe(root, '$active$suffix');
    }
    final slots = await storage.loadSlots(root);
    if (slots.latest == null || slots.conflict) invalidBackupMetadata();
    final value = slots.latest!;
    final phase = j['phase'];
    var finish =
        phase == 'validated' ||
        phase == 'completed' ||
        j['previousUsable'] == false;
    if (finish && j['previousUsable'] == false) {
      final candidate = p.join(stage, 'autofinance.sqlite');
      await storage.safe(root, candidate);
      if (await File(candidate).exists()) {
        if (await File(candidate).length() !=
                backupCounter(j['candidateSizeBytes']) ||
            (await sha256.bind(File(candidate).openRead()).first).toString() !=
                j['candidateSha256']) {
          invalidBackupMetadata();
        }
        await validateActive(candidate);
        final isolated = p.join(stage, 'recovery-${const Uuid().v4()}');
        await persistence.createDirectory(isolated);
        for (final suffix in ['', '-wal', '-shm', '-journal']) {
          if (await File('$active$suffix').exists()) {
            await persistence.move(
              '$active$suffix',
              p.join(isolated, 'autofinance.sqlite$suffix'),
            );
          }
        }
        await persistence.move(candidate, active);
      }
    }
    if (finish) {
      try {
        final image = await validateActive(active);
        final revision = backupCounter(j['revision'], positive: false);
        if (image.state.datasetId != j['datasetId'] ||
            (phase == 'completed'
                ? image.state.revision < revision
                : image.state.revision != revision)) {
          invalidBackupMetadata();
        }
      } catch (_) {
        if (j['previousUsable'] != true) rethrow;
        finish = false;
      }
    }
    if (finish) {
      value['localRestoreEpoch'] = j['newEpoch'];
      value['syncContrastRequired'] = true;
    } else if (phase == 'protected' || phase == 'rolledBack') {
      final image = await validateActive(active);
      if (j['previousUsable'] != true ||
          image.state.datasetId != j['previousDatasetId'] ||
          image.state.revision !=
              backupCounter(j['previousRevision'], positive: false)) {
        invalidBackupMetadata();
      }
      value['localRestoreEpoch'] = j['previousEpoch'];
      value['syncContrastRequired'] = j['previousContrastRequired'];
    } else {
      if (j['previousUsable'] != true) invalidBackupMetadata();
      // Marca la decisión antes de cualquier movimiento: el reinicio repite
      // el rollback incluso si ya había sido confirmado el nuevo epoch.
      final marker = p.join(stage, 'journal-900.json');
      await storage.safe(root, marker);
      if (!await File(marker).exists()) {
        await storage.writeEnvelope(root, marker, {
          ...j,
          'phase': 'rollingBack',
        });
      }
      final previous = await preparer.prepareUnderLock(
        root,
        j['previousBackupId'] as String,
      );
      if (previous.image.state.datasetId != j['previousDatasetId'] ||
          previous.image.state.revision !=
              backupCounter(j['previousRevision'], positive: false)) {
        invalidBackupMetadata();
      }
      final failed = p.join(stage, 'recovery-${const Uuid().v4()}');
      await persistence.createDirectory(failed);
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final path = '$active$suffix';
        if (await File(path).exists()) {
          await persistence.move(
            path,
            p.join(failed, 'autofinance.sqlite$suffix'),
          );
        }
      }
      await persistence.move(p.join(root, previous.relativePath), active);
      final image = await validateActive(active);
      if (image.state.datasetId != j['previousDatasetId'] ||
          image.state.revision !=
              backupCounter(j['previousRevision'], positive: false)) {
        invalidBackupMetadata();
      }
      value['localRestoreEpoch'] = j['previousEpoch'];
      value['syncContrastRequired'] = j['previousContrastRequired'];
    }
    await storage.commitCatalog(root, value);
    final resolved = p.join(stage, 'journal-901.json');
    await storage.safe(root, resolved);
    if (!await File(resolved).exists()) {
      await storage.writeEnvelope(root, resolved, {
        ...j,
        'phase': finish ? 'completed' : 'rolledBack',
      });
    }
    final diagnostics = p.join(root, 'local-backups', 'diagnostics');
    await storage.safe(root, diagnostics);
    await persistence.createDirectory(diagnostics);
    final target = p.join(diagnostics, j['operationId'] as String);
    await storage.safe(root, target);
    await persistence.move(stage, target);
    return finish;
  }
}

final class _RecoveryValidator implements LocalBackupImageValidator {
  const _RecoveryValidator(this.inspect);
  final Future<LocalBackupImage> Function(String) inspect;
  @override
  Future<LocalBackupImage> validate(String path) => inspect(path);
}
