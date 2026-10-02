import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../domain/local_backup_creation.dart';
import '../domain/local_restore_candidate.dart';
import 'backup_catalog.dart';
import 'backup_json.dart';
import 'backup_storage.dart';
import 'native_backup_persistence.dart';

/// No recibe store activo, fuente de snapshots ni cliente Drive.
final class LocalRestoreCandidateService
    implements LocalRestoreCandidatePreparer {
  LocalRestoreCandidateService({
    required this.policy,
    required this.supportDirectory,
    NativeBackupPersistence? persistence,
  }) : _persistence = persistence ?? NativeBackupPersistence();

  final LocalRestoreImagePolicy policy;
  final Future<Directory> Function() supportDirectory;
  final NativeBackupPersistence _persistence;
  late final _storage = BackupStorage(_persistence, DateTime.now);

  Never _reject(LocalRestoreCandidateIssue issue) =>
      throw LocalRestoreCandidateFailure(issue);

  @override
  Future<LocalRestoreCandidateResult> prepare(String backupId) async {
    try {
      if (!backupUuid.hasMatch(backupId)) {
        _reject(LocalRestoreCandidateIssue.invalidMetadata);
      }
      final support = (await supportDirectory()).absolute.path;
      final root = p.join(support, 'sqlite');
      await _storage.safe(support, root);
      final lock = p.join(root, '.local-backups.lock');
      await _storage.safe(root, lock);
      return await _persistence.exclusively(
        lock,
        () => _prepare(root, backupId),
      );
    } on LocalRestoreCandidateFailure catch (e) {
      return RejectedLocalRestoreCandidate(e.issue);
    } on LocalBackupFailure catch (e) {
      return RejectedLocalRestoreCandidate(switch (e.code) {
        LocalBackupFailureCode.operationInProgress =>
          LocalRestoreCandidateIssue.operationInProgress,
        LocalBackupFailureCode.incompatibleCatalog =>
          LocalRestoreCandidateIssue.futureFormat,
        LocalBackupFailureCode.storageFailure =>
          LocalRestoreCandidateIssue.storageFailure,
        _ => LocalRestoreCandidateIssue.invalidMetadata,
      });
    } on FileSystemException {
      return const RejectedLocalRestoreCandidate(
        LocalRestoreCandidateIssue.storageFailure,
      );
    } catch (_) {
      return const RejectedLocalRestoreCandidate(
        LocalRestoreCandidateIssue.invalidMetadata,
      );
    }
  }

  Future<ReadyLocalRestoreCandidate> _prepare(String root, String id) async {
    final base = p.join(root, 'local-backups');
    final directory = p.join(base, 'backups', id);
    final manifest = p.join(directory, 'manifest.json');
    final source = p.join(directory, 'autofinance.sqlite');
    await _requireFile(root, manifest);
    await _requireFile(root, source);
    final descriptor = decodeBackupEnvelope(await File(manifest).readAsBytes());
    checkBackupDescriptor(descriptor);
    if (descriptor['backupId'] != id) {
      _reject(LocalRestoreCandidateIssue.invalidMetadata);
    }
    final files = await Directory(directory).list(followLinks: false).toList();
    if (files.length != 2) _reject(LocalRestoreCandidateIssue.incompleteFile);

    // Catálogo confirmado si existe; el manifiesto permite validar una copia
    // recuperable todavía no catalogada. No se adopta una generación .next.
    final slots = await _storage.loadSlots(root);
    if (slots.conflict || slots.valid.isEmpty && slots.damaged.isNotEmpty) {
      _reject(LocalRestoreCandidateIssue.invalidMetadata);
    }
    final entries = slots.latest?['entries'] as List? ?? [];
    for (final entry in entries) {
      if (entry['descriptor']['backupId'] != id) continue;
      final catalogDescriptor = entry['descriptor'] as Map<String, dynamic>;
      if (catalogDescriptor['sizeBytes'] != descriptor['sizeBytes']) {
        _reject(LocalRestoreCandidateIssue.sizeMismatch);
      }
      if (catalogDescriptor['databaseSha256'] != descriptor['databaseSha256']) {
        _reject(LocalRestoreCandidateIssue.hashMismatch);
      }
      if (entry['manifestPayloadSha256'] != backupPayloadHash(descriptor) ||
          entry['availability'] == 'deletionPending') {
        _reject(LocalRestoreCandidateIssue.invalidMetadata);
      }
    }
    final tombstone = p.join(base, 'tombstones', '$id.json');
    await _storage.safe(root, tombstone);
    if (await FileSystemEntity.type(tombstone, followLinks: false) !=
        FileSystemEntityType.notFound) {
      _reject(LocalRestoreCandidateIssue.invalidMetadata);
    }
    final size = backupCounter(descriptor['sizeBytes']);
    final hash = descriptor['databaseSha256'] as String;
    await _checkBytes(source, size, hash);
    final operation = const Uuid().v4();
    final restore = p.join(base, 'restore');
    await _storage.safe(root, restore);
    await _persistence.createDirectory(restore);
    final stage = p.join(restore, operation);
    await _storage.safe(root, stage);
    await _persistence.createDirectory(stage);
    final part = p.join(stage, 'autofinance.sqlite.part');
    await File(source)
        .copy(part); // Imagen inmutable y cerrada, nunca base viva.
    await _persistence.flushFile(part);
    await _checkBytes(part, size, hash);
    final original = await policy.inspect(part);
    if (original.schemaVersion != descriptor['schemaVersion'] ||
        original.applicationId != descriptor['applicationId'] ||
        original.state.datasetId != descriptor['datasetId'] ||
        original.state.revision !=
            backupCounter(descriptor['revision'], positive: false)) {
      _reject(LocalRestoreCandidateIssue.invalidMetadata);
    }
    await policy.migrate(part);
    final image = await policy.inspect(part);
    if (image.state.datasetId != original.state.datasetId ||
        image.state.revision != original.state.revision) {
      _reject(LocalRestoreCandidateIssue.invalidMetadata);
    }
    await _persistence.flushFile(part);
    final readySize = await File(part).length();
    final readyHash = await _hash(part);
    // Detectar sustitución del original durante la preparación, incluido manifiesto.
    await _checkBytes(source, size, hash);
    if (backupPayloadHash(
          decodeBackupEnvelope(await File(manifest).readAsBytes()),
        ) !=
        backupPayloadHash(descriptor)) {
      _reject(LocalRestoreCandidateIssue.invalidMetadata);
    }
    final ready = p.join(stage, 'autofinance.sqlite');
    await _persistence.move(part, ready);
    await _checkBytes(ready, readySize, readyHash);
    return ReadyLocalRestoreCandidate(
      backupId: id,
      operationId: operation,
      relativePath: 'local-backups/restore/$operation/autofinance.sqlite',
      originalSchemaVersion: original.schemaVersion,
      image: image,
      sizeBytes: readySize,
      sha256: readyHash,
    );
  }

  /// Mantiene el bloqueo del coordinador durante preparación e intercambio.
  Future<ReadyLocalRestoreCandidate> prepareUnderLock(String root, String id) {
    if (!backupUuid.hasMatch(id)) invalidBackupMetadata();
    return _prepare(root, id);
  }

  /// Copia cerrada descargada: validar hash antes de migrar solo el staging.
  /// El llamador mantiene el bloqueo de EP-006 y acredita la ruta privada.
  Future<ReadyLocalRestoreCandidate> prepareImageUnderLock(
    String root, {
    required String path,
    required String expectedSha256,
    required int expectedSize,
  }) async {
    await _requireFile(root, path);
    await _checkBytes(path, expectedSize, expectedSha256);
    final operation = const Uuid().v4();
    final stage = p.join(root, 'local-backups', 'restore', operation);
    await _storage.safe(root, stage);
    await _persistence.createDirectory(p.dirname(stage));
    await _persistence.createDirectory(stage);
    final part = p.join(stage, 'autofinance.sqlite.part');
    await File(path).copy(part);
    await _persistence.flushFile(part);
    await _checkBytes(part, expectedSize, expectedSha256);
    final original = await policy.inspect(part);
    await policy.migrate(part);
    final image = await policy.inspect(part);
    if (image.state.datasetId != original.state.datasetId ||
        image.state.revision != original.state.revision) {
      _reject(LocalRestoreCandidateIssue.invalidMetadata);
    }
    await _persistence.flushFile(part);
    final size = await File(part).length();
    final hash = await _hash(part);
    await _checkBytes(path, expectedSize, expectedSha256);
    await _persistence.move(part, p.join(stage, 'autofinance.sqlite'));
    return ReadyLocalRestoreCandidate(
      backupId: operation,
      operationId: operation,
      relativePath: 'local-backups/restore/$operation/autofinance.sqlite',
      originalSchemaVersion: original.schemaVersion,
      image: image,
      sizeBytes: size,
      sha256: hash,
    );
  }

  Future<void> _requireFile(String root, String path) async {
    await _storage.safe(root, path);
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      _reject(LocalRestoreCandidateIssue.missingFile);
    }
    if (type != FileSystemEntityType.file) {
      _reject(LocalRestoreCandidateIssue.invalidMetadata);
    }
  }

  Future<String> _hash(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();

  Future<void> _checkBytes(String path, int size, String hash) async {
    if (await File(path).length() != size) {
      _reject(LocalRestoreCandidateIssue.sizeMismatch);
    }
    if (await _hash(path) != hash) {
      _reject(LocalRestoreCandidateIssue.hashMismatch);
    }
  }
}
