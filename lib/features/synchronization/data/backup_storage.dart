import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../domain/local_backup_creation.dart';
import 'backup_catalog.dart';
import 'backup_json.dart';
import 'native_backup_persistence.dart';

final class BackupCatalogSlots {
  final valid = <String, Map<String, dynamic>>{};
  final damaged = <String>[];
  bool get conflict =>
      valid.length == 2 &&
      valid.values.first['generation'] == valid.values.last['generation'] &&
      jsonEncode(valid.values.first) != jsonEncode(valid.values.last);
  Map<String, dynamic>? get latest {
    if (valid.isEmpty || conflict) return null;
    return valid.values.reduce(
      (a, b) => backupCounter(a['generation']) >= backupCounter(b['generation'])
          ? a
          : b,
    );
  }
}

/// Escrituras de catálogo y comprobaciones de rutas compartidas con creación.
final class BackupStorage {
  BackupStorage(this._persistence, this._clock);
  final NativeBackupPersistence _persistence;
  final DateTime Function() _clock;
  Future<BackupCatalogSlots> loadSlots(String root) async {
    final result = BackupCatalogSlots();
    for (final slot in ['a', 'b']) {
      final path = p.join(root, 'local-backups', 'catalog-$slot.json');
      await safe(root, path);
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) continue;
      if (type != FileSystemEntityType.file) invalidBackupMetadata();
      final bytes = await File(path).readAsBytes();
      try {
        final value = decodeBackupEnvelope(bytes);
        checkBackupCatalog(value);
        result.valid[path] = value;
      } on LocalBackupFailure catch (e) {
        if (e.code == LocalBackupFailureCode.incompatibleCatalog) rethrow;
        result.damaged.add(path);
      } catch (_) {
        result.damaged.add(path);
      }
    }
    return result;
  }

  Future<void> commitCatalog(
    String root,
    Map<String, dynamic> catalog, {
    bool initial = false,
  }) async {
    final generation = backupCounter(catalog['generation']);
    if (!initial && generation == maxBackupCounter) {
      throw const LocalBackupFailure(LocalBackupFailureCode.counterExhausted);
    }
    if (!initial) catalog['generation'] = '${generation + 1}';
    catalog['writtenAtUtc'] = backupUtc(_clock());
    checkBackupCatalog(catalog);
    final base = p.join(root, 'local-backups');
    final pending = p.join(base, 'catalog-${const Uuid().v4()}.next');
    await writeEnvelope(root, pending, catalog);
    final a = p.join(base, 'catalog-a.json');
    final b = p.join(base, 'catalog-b.json');
    await safe(root, a);
    await safe(root, b);
    final slots = await loadSlots(root);
    final target = !slots.valid.containsKey(a)
        ? a
        : !slots.valid.containsKey(b)
        ? b
        : backupCounter(slots.valid[a]!['generation']) <=
              backupCounter(slots.valid[b]!['generation'])
        ? a
        : b;
    await _persistence.move(pending, target, replace: true);
    final confirmed = decodeBackupEnvelope(await File(target).readAsBytes());
    checkBackupCatalog(confirmed);
    if (jsonEncode(confirmed) != jsonEncode(catalog)) invalidBackupMetadata();
  }

  Future<void> writeEnvelope(
    String root,
    String path,
    Map<String, dynamic> payload,
  ) async {
    await safe(root, path);
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      invalidBackupMetadata();
    }
    final temporary = '$path.${const Uuid().v4()}.next';
    await File(temporary)
        .writeAsBytes(encodeBackupEnvelope(payload), flush: true);
    await _persistence.flushFile(temporary);
    final checked = decodeBackupEnvelope(await File(temporary).readAsBytes());
    if (jsonEncode(checked) != jsonEncode(payload)) invalidBackupMetadata();
    // Rename the complete file through the native persistence adapter, also
    // confirming its directory entry (the destination is always new).
    await _persistence.move(temporary, path);
  }

  Future<void> safe(String root, String path) async {
    final normalizedRoot = p.normalize(p.absolute(root));
    final normalized = p.normalize(p.absolute(path));
    if (!p.equals(normalizedRoot, normalized) &&
        !p.isWithin(normalizedRoot, normalized)) {
      invalidBackupMetadata();
    }
    var current = p.rootPrefix(normalized);
    for (final segment in p.split(normalized).skip(1)) {
      current = p.join(current, segment);
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.link) invalidBackupMetadata();
      if (type != FileSystemEntityType.notFound) {
        final resolved = type == FileSystemEntityType.directory
            ? await Directory(current).resolveSymbolicLinks()
            : await File(current).resolveSymbolicLinks();
        if (!p.equals(p.normalize(resolved), p.normalize(current))) {
          invalidBackupMetadata();
        }
      }
    }
  }
}
