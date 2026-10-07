import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/persistence/local_database_format.dart';

import '../domain/local_backup.dart';
import '../domain/local_backup_creation.dart';
import 'backup_catalog.dart';
import 'backup_json.dart';
import 'native_backup_persistence.dart';
import 'backup_storage.dart';

/// Creación explícita; no abre la activa al construirlo ni ejecuta retención.
final class LocalBackupService implements LocalBackupCreator {
  LocalBackupService({
    required this.source,
    required this.validator,
    required this.supportDirectory,
    NativeBackupPersistence? persistence,
    DateTime Function()? clock,
  }) : _persistence = persistence ?? NativeBackupPersistence(),
       _clock = clock ?? DateTime.now;

  final LocalBackupSource source;
  final LocalBackupImageValidator validator;
  final Future<Directory> Function() supportDirectory;
  final NativeBackupPersistence _persistence;
  final DateTime Function() _clock;
  late final _storage = BackupStorage(_persistence, _clock);

  @override
  Future<CreatedLocalBackup> createManual() =>
      _create(LocalBackupOrigin.manual, null);
  @override
  Future<CreatedLocalBackup> createPreRestore(String restoreOperationId) {
    if (!backupUuid.hasMatch(restoreOperationId)) invalidBackupMetadata();
    return _create(LocalBackupOrigin.preRestore, restoreOperationId);
  }

  Future<CreatedLocalBackup> _create(
    LocalBackupOrigin origin,
    String? restoreId,
  ) async {
    try {
      final support = (await supportDirectory()).absolute.path;
      await _safe(support, support);
      final root = p.join(support, 'sqlite');
      await _safe(support, root);
      await _persistence.createDirectory(root);
      // Lock outside local-backups so two first-time owners cannot race its creation.
      final lock = p.join(root, '.local-backups.lock');
      await _safe(root, lock);
      return await _persistence.exclusively(
        lock,
        () => _capture(root, origin, restoreId),
      );
    } on LocalBackupFailure {
      rethrow;
    } catch (_) {
      throw const LocalBackupFailure(LocalBackupFailureCode.storageFailure);
    }
  }

  Future<CreatedLocalBackup> _capture(
    String root,
    LocalBackupOrigin origin,
    String? restoreId,
  ) async {
    final base = p.join(root, 'local-backups');
    await _safe(root, base);
    await _persistence.createDirectory(base);
    final catalog = await _loadCatalog(root);
    for (final name in ['staging', 'backups']) {
      final path = p.join(base, name);
      await _safe(root, path);
      await _persistence.createDirectory(path);
    }
    await _reconcileOrders(root, catalog);
    final order = backupCounter(catalog['nextCreationOrder']);
    if (order == maxBackupCounter) {
      throw const LocalBackupFailure(LocalBackupFailureCode.counterExhausted);
    }
    final id = const Uuid().v4();
    final stage = p.join(base, 'staging', id);
    await _safe(root, stage);
    await _persistence.createDirectory(stage);
    final intent = <String, dynamic>{
      'kind': 'autofinance.localBackupIntent',
      'formatVersion': 1,
      'backupId': id,
      'creationOrder': '$order',
      'origin': origin.name,
      'restoreOperationId': restoreId,
      'requestedAtUtc': backupUtc(_clock()),
    };
    await _writeEnvelope(root, p.join(stage, 'intent.json'), intent);
    catalog['nextCreationOrder'] = '${order + 1}';
    await _commitCatalog(root, catalog);

    final snapshot = await source.createConsistentBackup(); // única captura
    final created = backupUtc(_clock());
    final snapshotPath = p.normalize(p.absolute(snapshot.path));
    final relative = p
        .relative(snapshotPath, from: root)
        .split(p.separator)
        .join('/');
    if (!RegExp(r'^copies/snapshot-[A-Za-z0-9_-]+/autofinance\.sqlite$')
        .hasMatch(relative)) {
      invalidBackupMetadata();
    }
    await _safe(root, snapshotPath);
    await _requireFile(snapshotPath);
    for (final suffix in ['-wal', '-shm', '-journal']) {
      if (await FileSystemEntity.type(
            '$snapshotPath$suffix',
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound) {
        throw const LocalBackupFailure(LocalBackupFailureCode.invalidSnapshot);
      }
    }
    await _writeEnvelope(root, p.join(stage, 'receipt.json'), {
      'kind': 'autofinance.localBackupReceipt',
      'formatVersion': 1,
      'backupId': id,
      'snapshotRelativePath': relative,
    });
    final imagePart = p.join(stage, 'autofinance.sqlite.part');
    await _persistence.move(snapshotPath, imagePart);
    await _persistence.flushFile(imagePart);
    final size = await File(imagePart).length();
    if (size <= 0) {
      throw const LocalBackupFailure(LocalBackupFailureCode.invalidSnapshot);
    }
    final hash = await _hash(imagePart);
    final image = await validator.validate(imagePart);
    if (image.schemaVersion != localSchemaVersion ||
        image.applicationId != localApplicationId ||
        image.state.datasetId != snapshot.state.datasetId ||
        image.state.revision != snapshot.state.revision) {
      throw const LocalBackupFailure(LocalBackupFailureCode.invalidSnapshot);
    }
    if (await File(imagePart).length() != size ||
        await _hash(imagePart) != hash) {
      throw const LocalBackupFailure(LocalBackupFailureCode.invalidSnapshot);
    }
    final validation = <String, dynamic>{
      'state': 'valid',
      'checkedAtUtc': backupUtc(_clock()),
      'policySchemaVersion': localSchemaVersion,
      'issue': null,
    };
    final descriptor = <String, dynamic>{
      'kind': 'autofinance.localBackup',
      'formatVersion': 1,
      'backupId': id,
      'datasetId': image.state.datasetId,
      'applicationId': image.applicationId,
      'schemaVersion': image.schemaVersion,
      'revision': '${image.state.revision}',
      'createdAtUtc': created,
      'creationOrder': '$order',
      'origin': origin.name,
      'restoreOperationId': restoreId,
      'databaseFile': 'autofinance.sqlite',
      'sizeBytes': '$size',
      'databaseSha256': hash,
      'initialValidation': validation,
    };
    checkBackupDescriptor(descriptor);
    await _writeEnvelope(root, p.join(stage, 'manifest.json.part'), descriptor);
    // Final artifact has exactly two files. intent/receipt remain in staging until
    // catalog confirmation, providing diagnostics without altering the manifest.
    final ready = p.join(stage, 'ready');
    await _persistence.createDirectory(ready);
    await _persistence.move(imagePart, p.join(ready, 'autofinance.sqlite'));
    await _persistence.move(
      p.join(stage, 'manifest.json.part'),
      p.join(ready, 'manifest.json'),
    );
    final relativeDirectory = 'local-backups/backups/$id';
    final finalDirectory = p.joinAll([root, ...relativeDirectory.split('/')]);
    await _safe(root, finalDirectory);
    await _persistence.move(ready, finalDirectory);
    (catalog['entries'] as List).add({
      'descriptor': descriptor,
      'manifestPayloadSha256': backupPayloadHash(descriptor),
      'relativeDirectory': relativeDirectory,
      'availability': 'present',
      'validation': validation,
    });
    await _commitCatalog(root, catalog);
    var cleanupPending = false;
    try {
      await _safe(root, stage);
      final leftovers = await Directory(stage)
          .list(followLinks: false)
          .toList();
      if (leftovers.length == 2 &&
          leftovers.every(
            (item) =>
                {'intent.json', 'receipt.json'}.contains(p.basename(item.path)),
          )) {
        for (final item in leftovers) {
          await _safe(root, item.path);
          await _requireFile(item.path);
          await File(item.path).delete();
        }
        await Directory(stage).delete();
      } else {
        cleanupPending = true;
      }
      final oldDirectory = p.dirname(snapshotPath);
      await _safe(root, oldDirectory);
      // Never recursively remove a source directory containing unknown artifacts.
      if (await Directory(oldDirectory).list().isEmpty) {
        await Directory(oldDirectory).delete();
      } else {
        cleanupPending = true;
      }
    } catch (_) {
      cleanupPending = true;
    }
    return CreatedLocalBackup(
      backupId: id,
      relativeDirectory: relativeDirectory,
      state: image.state,
      creationOrder: order,
      origin: origin,
      cleanupPending: cleanupPending,
    );
  }

  /// Solo el coordinador que ya posee .local-backups.lock puede usarlo.
  Future<CreatedLocalBackup> capturePreRestoreUnderLock(
    String root,
    String operationId,
  ) {
    if (!backupUuid.hasMatch(operationId)) invalidBackupMetadata();
    return _capture(root, LocalBackupOrigin.preRestore, operationId);
  }

  Future<Map<String, dynamic>> _loadCatalog(String root) async {
    final valid = <Map<String, dynamic>>[];
    var existing = false;
    var damaged = false;
    for (final slot in ['a', 'b']) {
      final path = p.join(root, 'local-backups', 'catalog-$slot.json');
      await _safe(root, path);
      if (await FileSystemEntity.type(path, followLinks: false) ==
          FileSystemEntityType.notFound) {
        continue;
      }
      existing = true;
      await _requireFile(path);
      final bytes = await File(path)
          .readAsBytes(); // I/O must never become empty
      try {
        final value = decodeBackupEnvelope(bytes);
        checkBackupCatalog(value);
        valid.add(value);
      } on LocalBackupFailure catch (e) {
        if (e.code == LocalBackupFailureCode.incompatibleCatalog) rethrow;
        damaged = true;
      }
    }
    // Reconciliation/reconstruction of damaged or conflicting slots belongs to 053.
    if (damaged || existing && valid.isEmpty) {
      throw const LocalBackupFailure(LocalBackupFailureCode.recoveryRequired);
    }
    if (valid.length == 2 &&
        valid[0]['generation'] == valid[1]['generation'] &&
        jsonEncode(valid[0]) != jsonEncode(valid[1])) {
      throw const LocalBackupFailure(LocalBackupFailureCode.recoveryRequired);
    }
    if (valid.isNotEmpty) {
      valid.sort(
        (a, b) =>
            backupCounter(b['generation'])
                .compareTo(backupCounter(a['generation'])),
      );
      return valid.first;
    }
    final base = Directory(p.join(root, 'local-backups'));
    if (!await base.list().isEmpty) {
      throw const LocalBackupFailure(LocalBackupFailureCode.recoveryRequired);
    }
    final result = <String, dynamic>{
      'kind': 'autofinance.localBackupCatalog',
      'formatVersion': 1,
      'generation': '1',
      'writtenAtUtc': backupUtc(_clock()),
      'nextCreationOrder': '1',
      'localRestoreEpoch': const Uuid().v4(),
      'syncContrastRequired': true,
      'entries': <dynamic>[],
    };
    await _commitCatalog(root, result, initial: true);
    return result;
  }

  Future<void> _reconcileOrders(
    String root,
    Map<String, dynamic> catalog,
  ) async {
    var next = backupCounter(catalog['nextCreationOrder']);
    final orders = <int, String>{
      for (final e in catalog['entries'])
        backupCounter(e['descriptor']['creationOrder']):
            e['descriptor']['backupId'],
    };
    final stage = Directory(p.join(root, 'local-backups', 'staging'));
    await for (final item in stage.list(followLinks: false)) {
      await _safe(root, item.path);
      final id = p.basename(item.path);
      if (!backupUuid.hasMatch(id) || item is! Directory) {
        throw const LocalBackupFailure(LocalBackupFailureCode.recoveryRequired);
      }
      final path = p.join(item.path, 'intent.json');
      await _safe(root, path);
      final intent = decodeBackupEnvelope(await File(path).readAsBytes());
      checkBackupIntent(intent, id);
      final order = backupCounter(intent['creationOrder']);
      for (final entry in catalog['entries']) {
        final descriptor = entry['descriptor'];
        if (descriptor['backupId'] == id &&
            (descriptor['creationOrder'] != intent['creationOrder'] ||
                descriptor['origin'] != intent['origin'] ||
                descriptor['restoreOperationId'] !=
                    intent['restoreOperationId'])) {
          throw const LocalBackupFailure(
            LocalBackupFailureCode.recoveryRequired,
          );
        }
      }
      if (orders.containsKey(order) && orders[order] != id) {
        throw const LocalBackupFailure(LocalBackupFailureCode.recoveryRequired);
      }
      orders[order] = id;
      if (order == maxBackupCounter) {
        throw const LocalBackupFailure(LocalBackupFailureCode.counterExhausted);
      }
      if (order >= next) next = order + 1;
    }
    final ids = {
      for (final e in catalog['entries']) e['descriptor']['backupId'],
    };
    await for (final item in Directory(
      p.join(root, 'local-backups', 'backups'),
    ).list(followLinks: false)) {
      await _safe(root, item.path);
      if (item is! Directory || !ids.contains(p.basename(item.path))) {
        throw const LocalBackupFailure(LocalBackupFailureCode.recoveryRequired);
      }
    }
    catalog['nextCreationOrder'] = '$next';
  }

  Future<void> _commitCatalog(
    String root,
    Map<String, dynamic> catalog, {
    bool initial = false,
  }) => _storage.commitCatalog(root, catalog, initial: initial);
  Future<void> _writeEnvelope(
    String root,
    String path,
    Map<String, dynamic> payload,
  ) => _storage.writeEnvelope(root, path, payload);

  Future<String> _hash(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();
  Future<void> _requireFile(String path) async {
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      invalidBackupMetadata();
    }
  }

  Future<void> _safe(String root, String path) => _storage.safe(root, path);
}
