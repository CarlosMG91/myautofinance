import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/persistence/local_database_format.dart';

import '../domain/local_backup_catalog.dart';
import '../domain/local_backup_creation.dart';
import 'backup_catalog.dart';
import 'backup_json.dart';
import 'backup_storage.dart';
import 'native_backup_persistence.dart';

final class _CatalogState {
  _CatalogState(this.catalog);
  final Map<String, dynamic> catalog;
  final incidents = <LocalBackupCatalogIncident>[];
  final deletions = <String, Map<String, dynamic>>{};
  bool recovered = false;
  bool unavailable = false;
  bool blocked = false;
  List<dynamic> get entries => catalog['entries'] as List<dynamic>;
  void warn(
    LocalBackupCatalogIssue issue, {
    String? id,
    LocalBackupOrigin? origin,
    bool block = true,
  }) {
    incidents.add(
      LocalBackupCatalogIncident(issue, backupId: id, origin: origin),
    );
    if (block) blocked = true;
  }
}

/// Catálogo privado independiente: no recibe store, snapshot ni base activa.
final class LocalBackupCatalogService implements LocalBackupCatalog {
  LocalBackupCatalogService({
    required this.supportDirectory,
    required this.validator,
    NativeBackupPersistence? persistence,
    DateTime Function()? clock,
  }) : _persistence = persistence ?? NativeBackupPersistence(),
       _clock = clock ?? DateTime.now;
  final Future<Directory> Function() supportDirectory;
  final LocalBackupImageValidator validator;
  final NativeBackupPersistence _persistence;
  final DateTime Function() _clock;
  late final _storage = BackupStorage(_persistence, _clock);

  Future<T> _locked<T>(Future<T> Function(String root) action) async {
    try {
      final support = (await supportDirectory()).absolute.path;
      await _storage.safe(support, support);
      final root = p.join(support, 'sqlite');
      await _storage.safe(support, root);
      await _persistence.createDirectory(root);
      final lock = p.join(root, '.local-backups.lock');
      await _storage.safe(root, lock);
      return await _persistence.exclusively(lock, () => action(root));
    } on LocalBackupFailure {
      rethrow;
    } catch (_) {
      throw const LocalBackupFailure(LocalBackupFailureCode.storageFailure);
    }
  }

  @override
  Future<LocalBackupCatalogListing> read() async {
    try {
      return await _locked((root) async => _listing(await _load(root)));
    } on LocalBackupFailure catch (e) {
      if (e.code == LocalBackupFailureCode.operationInProgress) rethrow;
      final future = e.code == LocalBackupFailureCode.incompatibleCatalog;
      return LocalBackupCatalogListing(
        status: future
            ? LocalBackupCatalogStatus.incompatible
            : LocalBackupCatalogStatus.unavailable,
        entries: const [],
        incidents: [
          LocalBackupCatalogIncident(
            future
                ? LocalBackupCatalogIssue.futureFormat
                : LocalBackupCatalogIssue.storageFailure,
          ),
        ],
        pruningAllowed: false,
      );
    }
  }

  LocalBackupCatalogListing _listing(_CatalogState state) {
    final entries =
        state.entries.map((e) {
          final d = e['descriptor'];
          final v = e['validation'];
          return LocalBackupCatalogEntry(
            backupId: d['backupId'],
            createdAtUtc: DateTime.parse(d['createdAtUtc']),
            creationOrder: backupCounter(d['creationOrder']),
            origin: LocalBackupOrigin.values.byName(d['origin']),
            sizeBytes: backupCounter(d['sizeBytes']),
            availability: LocalBackupAvailability.values.byName(
              e['availability'],
            ),
            validation: LocalBackupValidationState.values.byName(v['state']),
            checkedAtUtc: v['checkedAtUtc'] == null
                ? null
                : DateTime.parse(v['checkedAtUtc']),
            issue: v['issue'],
          );
        }).toList()..sort((a, b) {
          final date = b.createdAtUtc.compareTo(a.createdAtUtc);
          if (date != 0) return date;
          final order = b.creationOrder.compareTo(a.creationOrder);
          return order != 0 ? order : a.backupId.compareTo(b.backupId);
        });
    return LocalBackupCatalogListing(
      status: state.unavailable
          ? LocalBackupCatalogStatus.unavailable
          : state.recovered
          ? LocalBackupCatalogStatus.recovered
          : entries.isEmpty && state.incidents.isEmpty
          ? LocalBackupCatalogStatus.empty
          : LocalBackupCatalogStatus.ready,
      entries: entries,
      incidents: state.incidents,
      pruningAllowed: !state.blocked,
    );
  }

  Map<String, dynamic> _validation(String status, String? issue) => {
    'state': status,
    'checkedAtUtc': backupUtc(_clock()),
    'policySchemaVersion': localSchemaVersion,
    'issue': issue,
  };
  Map<String, dynamic> get _pending => {
    'state': 'pending',
    'checkedAtUtc': null,
    'policySchemaVersion': null,
    'issue': null,
  };

  Future<List<FileSystemEntity>> _children(String root, String path) async {
    await _storage.safe(root, path);
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return [];
    if (type != FileSystemEntityType.directory) invalidBackupMetadata();
    return Directory(path).list(followLinks: false).toList();
  }

  Future<Map<String, dynamic>> _document(String root, String path) async {
    await _storage.safe(root, path);
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      invalidBackupMetadata();
    }
    return decodeBackupEnvelope(await File(path).readAsBytes());
  }

  Future<_CatalogState> _load(String root) async {
    final base = p.join(root, 'local-backups');
    await _storage.safe(root, base);
    await _persistence.createDirectory(base);
    final slots = await _storage.loadSlots(root);
    final selected = slots.latest;
    final catalog =
        selected ??
        <String, dynamic>{
          'kind': 'autofinance.localBackupCatalog',
          'formatVersion': 1,
          'generation': '1',
          'writtenAtUtc': backupUtc(_clock()),
          'nextCreationOrder': '1',
          'localRestoreEpoch': const Uuid().v4(),
          'syncContrastRequired': true,
          'entries': <dynamic>[],
        };
    final before = jsonEncode(catalog);
    final state = _CatalogState(catalog);
    state.recovered =
        slots.damaged.isNotEmpty ||
        slots.conflict ||
        selected != null && slots.valid.length < 2;
    final orders = <int, String>{};
    final idOrders = <String, int>{};
    var next = backupCounter(catalog['nextCreationOrder']);
    void reserve(String id, Object? value) {
      final order = backupCounter(value);
      if (orders.containsKey(order) && orders[order] != id ||
          idOrders.containsKey(id) && idOrders[id] != order) {
        state.warn(LocalBackupCatalogIssue.ambiguousOrder, id: id);
      }
      orders[order] = id;
      idOrders[id] = order;
      if (order == maxBackupCounter) {
        throw const LocalBackupFailure(LocalBackupFailureCode.counterExhausted);
      }
      if (order >= next) next = order + 1;
    }

    for (final e in state.entries) {
      reserve(e['descriptor']['backupId'], e['descriptor']['creationOrder']);
    }

    // A corrupt/contradictory tombstone never authorizes deletion or resurrection.
    final badDeletions = <String>{};
    for (final file in await _children(root, p.join(base, 'tombstones'))) {
      final id = p.basenameWithoutExtension(file.path);
      try {
        final d = await _document(root, file.path);
        if (p.basename(file.path) != '$id.json') invalidBackupMetadata();
        checkBackupDeletion(d, id);
        reserve(id, d['creationOrder']);
        final known = state.entries.where(
          (e) => e['descriptor']['backupId'] == id,
        );
        if (known.isNotEmpty &&
            (known.single['descriptor']['creationOrder'] !=
                    d['creationOrder'] ||
                d['reason'] == 'retention' &&
                    known.single['descriptor']['origin'] != 'preRestore')) {
          invalidBackupMetadata();
        }
        state.deletions[id] = d;
      } catch (_) {
        badDeletions.add(id);
        state.warn(
          LocalBackupCatalogIssue.invalidMetadata,
          id: backupUuid.hasMatch(id) ? id : null,
        );
      }
    }

    final knownIds = {
      for (final e in state.entries) e['descriptor']['backupId'] as String,
    };
    for (final dir in await _children(root, p.join(base, 'backups'))) {
      final id = p.basename(dir.path);
      try {
        await _storage.safe(root, dir.path);
        if (dir is! Directory || !backupUuid.hasMatch(id)) {
          invalidBackupMetadata();
        }
        if (state.deletions.containsKey(id) &&
            await FileSystemEntity.type(
                  p.join(dir.path, 'manifest.json'),
                  followLinks: false,
                ) ==
                FileSystemEntityType.notFound) {
          continue; // Deletion may have stopped after removing the manifest.
        }
        final descriptor = await _document(
          root,
          p.join(dir.path, 'manifest.json'),
        );
        checkBackupDescriptor(descriptor);
        if (descriptor['backupId'] != id) invalidBackupMetadata();
        reserve(id, descriptor['creationOrder']);
        if (state.deletions.containsKey(id)) {
          final d = state.deletions[id]!;
          if (d['creationOrder'] != descriptor['creationOrder'] ||
              d['reason'] == 'retention' &&
                  descriptor['origin'] != 'preRestore') {
            state.deletions.remove(id);
            badDeletions.add(id);
            invalidBackupMetadata();
          }
        }
        if (!knownIds.contains(id) && !badDeletions.contains(id)) {
          // Duplicate orders cannot be represented by a valid v1 catalog.
          if (state.entries.any(
            (e) =>
                e['descriptor']['creationOrder'] == descriptor['creationOrder'],
          )) {
            state.warn(LocalBackupCatalogIssue.ambiguousOrder, id: id);
            continue;
          }
          state.entries.add({
            'descriptor': descriptor,
            'manifestPayloadSha256': backupPayloadHash(descriptor),
            'relativeDirectory': 'local-backups/backups/$id',
            'availability': 'present',
            'validation': _pending,
          });
          knownIds.add(id);
          state.recovered = true;
        }
      } on LocalBackupFailure catch (e) {
        state.warn(
          e.code == LocalBackupFailureCode.incompatibleCatalog
              ? LocalBackupCatalogIssue.futureFormat
              : LocalBackupCatalogIssue.invalidMetadata,
          id: backupUuid.hasMatch(id) ? id : null,
        );
      } catch (_) {
        state.warn(LocalBackupCatalogIssue.storageFailure, id: id);
      }
    }

    for (final e in state.entries) {
      final id = e['descriptor']['backupId'] as String;
      if (badDeletions.contains(id)) {
        e['availability'] = 'quarantined';
        e['validation'] = _validation('invalid', 'invalidMetadata');
      } else if (state.deletions.containsKey(id)) {
        e['availability'] = 'deletionPending';
        state.warn(LocalBackupCatalogIssue.deletionPending, id: id);
      } else {
        await _inspect(root, state, e);
      }
    }
    for (final id in state.deletions.keys.where(
      (id) => !knownIds.contains(id),
    )) {
      if (await FileSystemEntity.type(
            p.join(base, 'backups', id),
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound) {
        state.warn(LocalBackupCatalogIssue.deletionPending, id: id);
      }
    }

    for (final stage in await _children(root, p.join(base, 'staging'))) {
      final id = p.basename(stage.path);
      LocalBackupOrigin? origin;
      try {
        final intent = await _document(root, p.join(stage.path, 'intent.json'));
        checkBackupIntent(intent, id);
        reserve(id, intent['creationOrder']);
        origin = LocalBackupOrigin.values.byName(intent['origin']);
        final known = state.entries.where(
          (e) => e['descriptor']['backupId'] == id,
        );
        final contents = await _children(root, stage.path);
        if (known.isNotEmpty &&
            known.single['descriptor']['creationOrder'] ==
                intent['creationOrder'] &&
            known.single['descriptor']['origin'] == intent['origin'] &&
            known.single['descriptor']['restoreOperationId'] ==
                intent['restoreOperationId'] &&
            contents.every(
              (f) =>
                  {'intent.json', 'receipt.json'}.contains(p.basename(f.path)),
            )) {
          continue;
        }
      } catch (_) {
        /* Preserve unrecognized staging without inferring origin. */
      }
      state.warn(
        LocalBackupCatalogIssue.incompleteFile,
        id: backupUuid.hasMatch(id) ? id : null,
        origin: origin,
      );
    }
    for (final snapshot in await _children(root, p.join(root, 'copies'))) {
      if (snapshot is! Directory) {
        state.warn(LocalBackupCatalogIssue.orphan);
        continue;
      }
      try {
        if ((await _children(root, snapshot.path)).isNotEmpty) {
          state.warn(LocalBackupCatalogIssue.orphan);
        }
      } catch (_) {
        state.warn(LocalBackupCatalogIssue.orphan);
      }
    }
    if ((await _children(root, p.join(base, 'restore'))).isNotEmpty) {
      state.warn(LocalBackupCatalogIssue.unresolvedRestore);
    }
    for (final item in await _children(root, base)) {
      final name = p.basename(item.path);
      if (RegExp(r'^catalog-[0-9a-f-]{36}\.next(?:\.[0-9a-f-]{36}\.next)?$')
              .hasMatch(name) &&
          item is File) {
        // Pending writes never authorize deletion or reserve an order.
        state.warn(LocalBackupCatalogIssue.catalogWritePending, block: false);
        continue;
      }
      if (!{
        'catalog-a.json',
        'catalog-b.json',
        'backups',
        'staging',
        'tombstones',
        'restore',
        'diagnostics',
      }.contains(name)) {
        state.warn(LocalBackupCatalogIssue.incompleteFile);
      }
    }
    catalog['nextCreationOrder'] = '$next';
    if (selected == null && knownIds.isNotEmpty) state.recovered = true;
    final needsRepair =
        slots.valid.length < 2 || slots.conflict || slots.damaged.isNotEmpty;
    if (needsRepair || jsonEncode(catalog) != before) {
      try {
        // Preserve bad/conflicting bytes before replacing any slot.
        final isolate = {
          ...slots.damaged,
          if (slots.conflict) ...slots.valid.keys,
        };
        if (isolate.isNotEmpty) {
          final diagnostics = p.join(base, 'diagnostics');
          await _storage.safe(root, diagnostics);
          await _persistence.createDirectory(diagnostics);
          for (final path in isolate) {
            await _persistence.move(
              path,
              p.join(
                diagnostics,
                '${p.basename(path)}.${const Uuid().v4()}.damaged',
              ),
            );
          }
        }
        await _storage.commitCatalog(root, catalog, initial: selected == null);
      } catch (_) {
        // Keep the readable cache for diagnostics even when repair cannot be
        // persisted. No destructive action may use this unconfirmed generation.
        state.unavailable = true;
        state.warn(LocalBackupCatalogIssue.storageFailure);
      }
    }
    return state;
  }

  Future<void> _inspect(String root, _CatalogState state, dynamic e) async {
    final d = e['descriptor'];
    final id = d['backupId'] as String;
    final directory = p.join(root, 'local-backups', 'backups', id);
    try {
      final contents = await _children(root, directory);
      if (contents.isEmpty) {
        e['availability'] = 'missing';
        e['validation'] = _validation('unavailable', 'missingFile');
        state.warn(LocalBackupCatalogIssue.missingFile, id: id, block: false);
        return;
      }
      if (contents.length != 2 ||
          !contents.every(
            (f) =>
                f is File &&
                {
                  'manifest.json',
                  'autofinance.sqlite',
                }.contains(p.basename(f.path)),
          )) {
        e['availability'] = 'incomplete';
        e['validation'] = _validation('invalid', 'incompleteFile');
        state.warn(LocalBackupCatalogIssue.incompleteFile, id: id);
        return;
      }
      final manifest = await _document(
        root,
        p.join(directory, 'manifest.json'),
      );
      checkBackupDescriptor(manifest);
      if (backupPayloadHash(manifest) != e['manifestPayloadSha256']) {
        invalidBackupMetadata();
      }
      final image = p.join(directory, 'autofinance.sqlite');
      await _storage.safe(root, image);
      e['availability'] = 'present';
      String? issue;
      if (await File(image).length() != backupCounter(d['sizeBytes'])) {
        issue = 'sizeMismatch';
      } else if (await _hash(image) != d['databaseSha256']) {
        issue = 'hashMismatch';
      }
      if (issue != null) {
        e['validation'] = _validation('invalid', issue);
        state.warn(
          LocalBackupCatalogIssue.values.byName(issue),
          id: id,
          block: false,
        );
      }
    } on LocalBackupFailure catch (error) {
      e['availability'] = 'quarantined';
      final future = error.code == LocalBackupFailureCode.incompatibleCatalog;
      e['validation'] = _validation(
        future ? 'incompatible' : 'invalid',
        future ? 'futureFormat' : 'invalidMetadata',
      );
      state.warn(
        future
            ? LocalBackupCatalogIssue.futureFormat
            : LocalBackupCatalogIssue.invalidMetadata,
        id: id,
      );
    } catch (_) {
      e['validation'] = _validation('unavailable', 'storageFailure');
      state.warn(LocalBackupCatalogIssue.storageFailure, id: id);
    }
  }

  Future<String> _hash(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();

  Future<void> _checkArtifact(String root, dynamic entry) async {
    final directory = p.join(root, entry['relativeDirectory']);
    final files = await _children(root, directory);
    if (files.length != 2 ||
        !files.every(
          (f) =>
              f is File &&
              {
                'manifest.json',
                'autofinance.sqlite',
              }.contains(p.basename(f.path)),
        )) {
      invalidBackupMetadata();
    }
    final manifest = await _document(root, p.join(directory, 'manifest.json'));
    checkBackupDescriptor(manifest);
    if (backupPayloadHash(manifest) != entry['manifestPayloadSha256']) {
      invalidBackupMetadata();
    }
    await _storage.safe(root, p.join(directory, 'autofinance.sqlite'));
  }

  Future<bool> _revalidate(String root, dynamic e) async {
    if (e['availability'] != 'present') return false;
    final d = e['descriptor'];
    final path = p.join(
      root,
      'local-backups',
      'backups',
      d['backupId'],
      'autofinance.sqlite',
    );
    try {
      await _checkArtifact(root, e);
      if (d['schemaVersion'] < 1 || d['schemaVersion'] > localSchemaVersion) {
        e['validation'] = _validation(
          'incompatible',
          d['schemaVersion'] > localSchemaVersion
              ? 'futureSchema'
              : 'unsupportedSchema',
        );
        return false;
      }
      if (await File(path).length() != backupCounter(d['sizeBytes']) ||
          await _hash(path) != d['databaseSha256']) {
        e['validation'] = _validation('invalid', 'hashMismatch');
        return false;
      }
      final image = await validator.validate(path);
      await _checkArtifact(root, e);
      if (image.applicationId != d['applicationId'] ||
          image.schemaVersion != d['schemaVersion'] ||
          image.state.datasetId != d['datasetId'] ||
          image.state.revision !=
              backupCounter(d['revision'], positive: false) ||
          await File(path).length() != backupCounter(d['sizeBytes']) ||
          await _hash(path) != d['databaseSha256']) {
        e['validation'] = _validation('invalid', 'invalidMetadata');
        return false;
      }
      e['validation'] = _validation('valid', null);
      return true;
    } on LocalBackupFailure catch (error) {
      final storage = error.code == LocalBackupFailureCode.storageFailure;
      e['validation'] = _validation(
        storage ? 'unavailable' : 'invalid',
        storage ? 'storageFailure' : 'integrityFailure',
      );
      return false;
    } catch (_) {
      e['validation'] = _validation('unavailable', 'storageFailure');
      return false;
    }
  }

  @override
  Future<LocalBackupMaintenanceResult> maintainAfterRestore({
    required String restoreOperationId,
    required LocalRestoreRetentionOutcome outcome,
    Set<String> protectedBackupIds = const {},
  }) async {
    if (!backupUuid.hasMatch(restoreOperationId)) invalidBackupMetadata();
    return _maintenance((root, state, deleted) async {
      if (outcome != LocalRestoreRetentionOutcome.confirmed || state.blocked) {
        return;
      }
      final automatic =
          state.entries
              .where((e) => e['descriptor']['origin'] == 'preRestore')
              .toList()
            ..sort(
              (a, b) => backupCounter(b['descriptor']['creationOrder'])
                  .compareTo(backupCounter(a['descriptor']['creationOrder'])),
            );
      final valid = <dynamic>[];
      for (final e in automatic) {
        if (await _revalidate(root, e)) valid.add(e);
      }
      await _storage.commitCatalog(root, state.catalog);
      if (automatic.any(
        (e) =>
            e['validation']['state'] == 'unavailable' ||
            e['validation']['state'] == 'incompatible',
      )) {
        state.warn(LocalBackupCatalogIssue.storageFailure);
        return;
      }
      if (valid.length < 4) {
        if (automatic.length > 3) {
          state.warn(LocalBackupCatalogIssue.insufficientValidBackups);
        }
        return;
      }
      final keep = valid.take(3).toList();
      // Oldest first, with a fresh integral check of all three survivors per deletion.
      for (final e in valid.skip(3).toList().reversed) {
        final id = e['descriptor']['backupId'] as String;
        if (protectedBackupIds.contains(id)) {
          state.warn(LocalBackupCatalogIssue.protectedBackup, id: id);
          continue;
        }
        for (final survivor in keep) {
          if (!await _revalidate(root, survivor)) {
            state.warn(LocalBackupCatalogIssue.insufficientValidBackups);
            await _storage.commitCatalog(root, state.catalog);
            return;
          }
        }
        if (!await _revalidate(root, e)) {
          await _storage.commitCatalog(root, state.catalog);
          continue;
        }
        if (!await _delete(
          root,
          state,
          e,
          'retention',
          restoreOperationId,
          deleted,
        )) {
          return;
        }
      }
    });
  }

  @override
  Future<LocalBackupMaintenanceResult> deleteExplicitly(
    String backupId, {
    Set<String> protectedBackupIds = const {},
  }) async {
    if (!backupUuid.hasMatch(backupId)) invalidBackupMetadata();
    return _maintenance((root, state, deleted) async {
      if (state.blocked) return;
      if (protectedBackupIds.contains(backupId)) {
        state.warn(LocalBackupCatalogIssue.protectedBackup, id: backupId);
        return;
      }
      final target = state.entries.where(
        (e) => e['descriptor']['backupId'] == backupId,
      );
      if (target.isEmpty) {
        state.warn(LocalBackupCatalogIssue.missingFile, id: backupId);
        return;
      }
      var survivor = false;
      for (final e in state.entries.where(
        (e) => e['descriptor']['backupId'] != backupId,
      )) {
        if (await _revalidate(root, e)) {
          survivor = true;
          break;
        }
      }
      await _storage.commitCatalog(root, state.catalog);
      if (!survivor) {
        state.warn(
          LocalBackupCatalogIssue.insufficientValidBackups,
          id: backupId,
        );
        return;
      }
      await _delete(root, state, target.single, 'explicitUser', null, deleted);
    });
  }

  Future<LocalBackupMaintenanceResult> _maintenance(
    Future<void> Function(String, _CatalogState, List<String>) action,
  ) async {
    final deleted = <String>[];
    final warnings = <LocalBackupCatalogIncident>[];
    try {
      return await _locked((root) async {
        final state = await _load(root);
        warnings.addAll(state.incidents);
        try {
          await action(root, state, deleted);
        } finally {
          warnings.clear();
          warnings.addAll(state.incidents);
        }
        return LocalBackupMaintenanceResult(
          deletedBackupIds: deleted,
          incidents: warnings,
        );
      });
    } on LocalBackupFailure catch (e) {
      if (e.code == LocalBackupFailureCode.operationInProgress) rethrow;
      warnings.add(
        LocalBackupCatalogIncident(
          e.code == LocalBackupFailureCode.incompatibleCatalog
              ? LocalBackupCatalogIssue.futureFormat
              : LocalBackupCatalogIssue.storageFailure,
        ),
      );
    } catch (_) {
      warnings.add(
        const LocalBackupCatalogIncident(
          LocalBackupCatalogIssue.storageFailure,
        ),
      );
    }
    return LocalBackupMaintenanceResult(
      deletedBackupIds: deleted,
      incidents: warnings,
    );
  }

  Future<bool> _delete(
    String root,
    _CatalogState state,
    dynamic e,
    String reason,
    String? operation,
    List<String> deleted,
  ) async {
    final d = e['descriptor'];
    final id = d['backupId'] as String;
    final tombstones = p.join(root, 'local-backups', 'tombstones');
    await _storage.safe(root, tombstones);
    await _persistence.createDirectory(tombstones);
    final deletion = <String, dynamic>{
      'kind': 'autofinance.localBackupDeletion',
      'formatVersion': 1,
      'backupId': id,
      'creationOrder': d['creationOrder'],
      'deletedAtUtc': backupUtc(_clock()),
      'reason': reason,
      'restoreOperationId': operation,
    };
    checkBackupDeletion(deletion, id);
    await _storage.writeEnvelope(
      root,
      p.join(tombstones, '$id.json'),
      deletion,
    );
    state.deletions[id] = deletion;
    e['availability'] = 'deletionPending';
    await _storage.commitCatalog(root, state.catalog);
    return _finishDeletion(root, state, id, deleted);
  }

  Future<bool> _finishDeletion(
    String root,
    _CatalogState state,
    String id,
    List<String> deleted,
  ) async {
    final directory = p.join(root, 'local-backups', 'backups', id);
    try {
      final contents = await _children(root, directory);
      if (!contents.every(
        (f) =>
            f is File &&
            {
              'autofinance.sqlite',
              'manifest.json',
            }.contains(p.basename(f.path)),
      )) {
        state.warn(LocalBackupCatalogIssue.invalidMetadata, id: id);
        return false;
      }
      // Only these two files and an empty directory; never recursive or outside root.
      for (final name in ['autofinance.sqlite', 'manifest.json']) {
        final path = p.join(directory, name);
        await _storage.safe(root, path);
        final type = await FileSystemEntity.type(path, followLinks: false);
        if (type == FileSystemEntityType.file) {
          await _persistence.deleteFile(path);
        } else if (type != FileSystemEntityType.notFound) {
          invalidBackupMetadata();
        }
      }
      if (await Directory(directory).exists()) {
        await _persistence.deleteEmptyDirectory(directory);
      }
      state.entries.removeWhere((e) => e['descriptor']['backupId'] == id);
      await _storage.commitCatalog(root, state.catalog);
      deleted.add(id);
      return true;
    } catch (_) {
      state.warn(LocalBackupCatalogIssue.deletionPending, id: id);
      return false;
    }
  }

  @override
  Future<LocalBackupMaintenanceResult> retryPendingDeletions({
    Set<String> protectedBackupIds = const {},
  }) => _maintenance((root, state, deleted) async {
    // A pending deletion is allowed here; all other ambiguous artifacts block.
    if (state.incidents.any(
      (i) =>
          i.issue != LocalBackupCatalogIssue.deletionPending &&
          i.issue != LocalBackupCatalogIssue.catalogWritePending &&
          i.issue != LocalBackupCatalogIssue.hashMismatch &&
          i.issue != LocalBackupCatalogIssue.sizeMismatch &&
          i.issue != LocalBackupCatalogIssue.missingFile,
    )) {
      return;
    }
    for (final id in state.deletions.keys) {
      if (protectedBackupIds.contains(id)) {
        state.warn(LocalBackupCatalogIssue.protectedBackup, id: id);
        continue;
      }
      final exists =
          await FileSystemEntity.type(
            p.join(root, 'local-backups', 'backups', id),
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound;
      if (!exists &&
          !state.entries.any((e) => e['descriptor']['backupId'] == id)) {
        continue;
      }
      final retention = state.deletions[id]!['reason'] == 'retention';
      final requiredSurvivors = retention ? 3 : 1;
      var survivors = 0;
      for (final e in state.entries.where(
        (e) =>
            e['descriptor']['backupId'] != id &&
            (!retention || e['descriptor']['origin'] == 'preRestore'),
      )) {
        if (await _revalidate(root, e)) {
          if (++survivors == requiredSurvivors) break;
        }
      }
      await _storage.commitCatalog(root, state.catalog);
      if (survivors < requiredSurvivors) {
        state.warn(LocalBackupCatalogIssue.insufficientValidBackups, id: id);
        return;
      }
      if (!await _finishDeletion(root, state, id, deleted)) return;
    }
  });
}
