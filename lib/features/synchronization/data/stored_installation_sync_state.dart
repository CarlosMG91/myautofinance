import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/persistence/unit_of_work.dart';
import '../domain/drive_metadata.dart';
import '../domain/installation_sync_state.dart';
import '../domain/local_restore.dart';
import '../domain/local_backup_creation.dart';
import '../domain/local_sync_contrast.dart';
import 'backup_json.dart';
import 'backup_storage.dart';
import 'native_backup_persistence.dart';

/// Archivo separado de SQLite y sus copias. Reemplazo durable y bloqueo nativo
/// compartido entre instancias/procesos; sin tokens ni respuestas externas.
final class StoredInstallationSyncState implements InstallationSyncState {
  StoredInstallationSyncState({
    required this.supportDirectory,
    required this.readDataset,
    required this.contrastReader,
    NativeBackupPersistence? persistence,
    DateTime Function()? now,
  }) : _persistence = persistence ?? NativeBackupPersistence(),
       _now = now ?? DateTime.now;

  final Future<Directory> Function() supportDirectory;
  final Future<DatasetState> Function() readDataset;
  final LocalSyncContrastReader contrastReader;
  final NativeBackupPersistence _persistence;
  final DateTime Function() _now;
  bool _busy = false;

  Future<T> _run<T>(Future<T> Function(_State state) action) async {
    if (_busy) throw const SyncStateFailure(SyncStateIssue.operationInProgress);
    _busy = true;
    try {
      final support = (await supportDirectory()).absolute.path;
      final root = p.join(support, 'drive-sync');
      final storage = BackupStorage(_persistence, _now);
      await storage.safe(support, root);
      if (!await Directory(support).exists()) {
        await Directory(support).create(recursive: true);
      }
      await _persistence.createDirectory(root);
      final path = p.join(root, 'state.json');
      final lock = p.join(root, 'state.lock');
      await storage.safe(root, lock);
      return await _persistence.exclusively(lock, () async {
        await storage.safe(root, path);
        final state = await File(path).exists()
            ? _State.decode(
                decodeBackupEnvelope(await File(path).readAsBytes()),
              )
            : _State();
        Future<void> save() async {
          final next = p.join(root, '${const Uuid().v4()}.next');
          await storage.writeEnvelope(root, next, state.encode());
          await _persistence.move(next, path, replace: true);
        }

        state.save = save;
        return await action(state);
      });
    } on SyncStateFailure {
      rethrow;
    } on LocalBackupFailure catch (failure) {
      throw SyncStateFailure(
        failure.code == LocalBackupFailureCode.operationInProgress
            ? SyncStateIssue.operationInProgress
            : SyncStateIssue.storageFailure,
      );
    } catch (_) {
      throw const SyncStateFailure(SyncStateIssue.storageFailure);
    } finally {
      _busy = false;
    }
  }

  Future<void> _select(_State state, String account, String file) async {
    _text(account);
    _text(file);
    if (state.account != account || state.file != file) {
      state.account = account;
      state.file = file;
      state.clear();
      await state.save();
    }
  }

  @override
  Future<InstallationSyncSnapshot> inspect({
    required String accountId,
    required String fileId,
  }) => _run((state) async {
    await _select(state, accountId, fileId);
    final contrast = await contrastReader.read();
    final current = await readDataset();
    final status = state.pending != null
        ? SyncLocalStatus.pending
        : contrast.unreliable ||
              (contrast.required &&
                  (!state.contrasted ||
                      state.epoch != contrast.restoreEpoch)) ||
              (state.contrasted && state.epoch != contrast.restoreEpoch)
        ? SyncLocalStatus.contrastRequired
        : state.image == null
        ? SyncLocalStatus.unknown
        : _same(current, state.image!)
        ? SyncLocalStatus.clean
        : SyncLocalStatus.changed;
    return InstallationSyncSnapshot(
      accountId: accountId,
      fileId: fileId,
      localStatus: status,
      knownRemoteVersion: state.version,
      correspondingLocalState: state.image,
      observedRemoteVersion: state.observed,
      checkedAt: state.checked,
      pending: state.pending,
    );
  });

  @override
  Future<void> recordCheck({
    required String accountId,
    required DriveFileMetadata remote,
  }) => _run((state) async {
    _version(remote.version);
    await _select(state, accountId, remote.id);
    state.observed = remote.version;
    state.checked = _now().toUtc();
    await state.save();
  });

  Future<PendingSyncOperation> _begin(
    _State state,
    String account,
    String file,
    DatasetState? image,
    SyncOperationKind kind,
    String? version,
  ) async {
    if (image != null) _image(image);
    await _select(state, account, file);
    if (state.pending != null) {
      throw const SyncStateFailure(SyncStateIssue.operationInProgress);
    }
    if (kind == SyncOperationKind.upload &&
        state.version != null &&
        state.observed != null &&
        state.version != state.observed) {
      throw const SyncStateFailure(SyncStateIssue.remoteDivergence);
    }
    final contrast = await contrastReader.read();
    if (contrast.unreliable) {
      throw const SyncStateFailure(SyncStateIssue.installationNotConfirmed);
    }
    final operation = PendingSyncOperation(
      id: const Uuid().v4(),
      kind: kind,
      image: image,
      restoreEpoch: contrast.restoreEpoch,
      remoteVersion: version,
    );
    state.pending = operation;
    await state.save();
    return operation;
  }

  @override
  Future<PendingSyncOperation> beginUpload({
    required String accountId,
    required String fileId,
    required DatasetState capturedImage,
  }) => _run(
    (state) => _begin(
      state,
      accountId,
      fileId,
      capturedImage,
      SyncOperationKind.upload,
      null,
    ),
  );

  @override
  Future<PendingSyncOperation> beginDownload({
    required String accountId,
    required DriveFileMetadata remote,
    DatasetState? downloadedImage,
  }) => _run((state) {
    _version(remote.version);
    return _begin(
      state,
      accountId,
      remote.id,
      downloadedImage,
      SyncOperationKind.download,
      remote.version,
    );
  });

  @override
  Future<void> recordDownloadedImage({
    required String operationId,
    required DatasetState downloadedImage,
  }) => _run((state) async {
    final operation = _pending(state, operationId, SyncOperationKind.download);
    _image(downloadedImage);
    if (operation.image != null && !_same(operation.image!, downloadedImage)) {
      throw const SyncStateFailure(SyncStateIssue.staleOperation);
    }
    state.pending = PendingSyncOperation(
      id: operation.id,
      kind: operation.kind,
      image: downloadedImage,
      restoreEpoch: operation.restoreEpoch,
      remoteVersion: operation.remoteVersion,
    );
    await state.save();
  });

  PendingSyncOperation _pending(
    _State state,
    String id, [
    SyncOperationKind? kind,
  ]) {
    final pending = state.pending;
    if (pending == null ||
        pending.id != id ||
        (kind != null && pending.kind != kind)) {
      throw const SyncStateFailure(SyncStateIssue.staleOperation);
    }
    return pending;
  }

  Future<void> _bind(
    _State state,
    PendingSyncOperation operation,
    String version,
    String? epoch,
  ) async {
    state.image = operation.image;
    state.version = version;
    state.observed = version;
    state.checked = _now().toUtc();
    state.epoch = epoch;
    state.contrasted = true;
    state.pending = null;
    await state.save();
  }

  @override
  Future<void> completeUpload({
    required String operationId,
    required DriveFileMetadata remote,
  }) => _run((state) async {
    final operation = _pending(state, operationId, SyncOperationKind.upload);
    _version(remote.version);
    if (remote.id != state.file) {
      throw const SyncStateFailure(SyncStateIssue.staleOperation);
    }
    final contrast = await contrastReader.read();
    if (contrast.unreliable ||
        contrast.restoreEpoch != operation.restoreEpoch) {
      throw const SyncStateFailure(SyncStateIssue.installationNotConfirmed);
    }
    await _bind(state, operation, remote.version!, contrast.restoreEpoch);
  });

  @override
  Future<LocalRestoreResult> installDownload({
    required String operationId,
    required Future<LocalRestoreResult> Function() install,
  }) => _run((state) async {
    final operation = _pending(state, operationId, SyncOperationKind.download);
    if (operation.image == null) {
      throw const SyncStateFailure(SyncStateIssue.installationNotConfirmed);
    }
    final result = await install();
    if (result.status != LocalRestoreStatus.restored) return result;
    final contrast = await contrastReader.read();
    final current = await readDataset();
    if (contrast.unreliable ||
        !_same(current, operation.image!) ||
        contrast.restoreEpoch == operation.restoreEpoch) {
      throw const SyncStateFailure(SyncStateIssue.installationNotConfirmed);
    }
    await _bind(
      state,
      operation,
      operation.remoteVersion!,
      contrast.restoreEpoch,
    );
    return result;
  });

  @override
  Future<void> abandonPending({required String operationId}) =>
      _run((state) async {
        _pending(state, operationId);
        state.clear();
        await state.save();
      });
}

bool _same(DatasetState a, DatasetState b) =>
    a.datasetId == b.datasetId && a.revision == b.revision;
Never _invalid() => throw const SyncStateFailure(SyncStateIssue.invalidState);
String _text(Object? value) {
  if (value is! String || value.trim().isEmpty || value.length > 1024) {
    _invalid();
  }
  return value;
}

String _version(Object? value) {
  final version = _text(value);
  if (!RegExp(r'^[1-9][0-9]*$').hasMatch(version)) _invalid();
  return version;
}

void _image(DatasetState value) {
  if (!datasetUuid.hasMatch(value.datasetId) || value.revision < 0) _invalid();
}

Map<String, dynamic> _encodeImage(DatasetState value) => {
  'datasetId': value.datasetId,
  'revision': '${value.revision}',
};
DatasetState _decodeImage(Object? value) {
  final map = backupObject(value, {'datasetId', 'revision'});
  final state = DatasetState(
    datasetId: _text(map['datasetId']),
    revision: backupCounter(map['revision'], positive: false),
  );
  _image(state);
  return state;
}

/// Consulta para preparar descargas, sin seleccionar identidad ni guardar estado.
extension DownloadSyncInspection on StoredInstallationSyncState {
  Future<InstallationSyncSnapshot> inspectForDownload({
    required String accountId,
    required String fileId,
  }) => _run((state) async {
    _text(accountId);
    _text(fileId);
    final contrast = await contrastReader.read();
    final current = await readDataset();
    final matches = state.account == accountId && state.file == fileId;
    final status = state.pending != null
        ? SyncLocalStatus.pending
        : !matches
        ? SyncLocalStatus.unknown
        : contrast.unreliable ||
              (contrast.required &&
                  (!state.contrasted ||
                      state.epoch != contrast.restoreEpoch)) ||
              (state.contrasted && state.epoch != contrast.restoreEpoch)
        ? SyncLocalStatus.contrastRequired
        : state.image == null
        ? SyncLocalStatus.unknown
        : _same(current, state.image!)
        ? SyncLocalStatus.clean
        : SyncLocalStatus.changed;
    return InstallationSyncSnapshot(
      accountId: accountId,
      fileId: fileId,
      localStatus: status,
      knownRemoteVersion: matches ? state.version : null,
      correspondingLocalState: matches ? state.image : null,
      pending: state.pending,
    );
  });
}

final class _State {
  String? account, file, version, observed, epoch;
  DatasetState? image;
  DateTime? checked;
  bool contrasted = false;
  PendingSyncOperation? pending;
  late Future<void> Function() save;
  void clear() {
    version = null;
    observed = null;
    epoch = null;
    image = null;
    checked = null;
    contrasted = false;
    pending = null;
  }

  Map<String, dynamic> encode() => {
    'schema': 1,
    'accountId': account,
    'fileId': file,
    'version': version,
    'observedVersion': observed,
    'image': image == null ? null : _encodeImage(image!),
    'checkedAt': checked?.toIso8601String(),
    'epoch': epoch,
    'contrasted': contrasted,
    'pending': pending == null
        ? null
        : {
            'id': pending!.id,
            'kind': pending!.kind.name,
            'image': pending!.image == null
                ? null
                : _encodeImage(pending!.image!),
            'epoch': pending!.restoreEpoch,
            'version': pending!.remoteVersion,
          },
  };
  static _State decode(Map<String, dynamic> json) {
    backupObject(json, {
      'schema',
      'accountId',
      'fileId',
      'version',
      'observedVersion',
      'image',
      'checkedAt',
      'epoch',
      'contrasted',
      'pending',
    });
    if (json['schema'] != 1 || json['contrasted'] is! bool) _invalid();
    final state = _State()
      ..account = _text(json['accountId'])
      ..file = _text(json['fileId'])
      ..version = json['version'] == null ? null : _version(json['version'])
      ..observed = json['observedVersion'] == null
          ? null
          : _version(json['observedVersion'])
      ..image = json['image'] == null ? null : _decodeImage(json['image'])
      ..epoch = json['epoch'] == null ? null : _text(json['epoch'])
      ..contrasted = json['contrasted'] as bool;
    if ((state.image == null) != (state.version == null) ||
        state.contrasted != (state.image != null)) {
      _invalid();
    }
    if (json['checkedAt'] != null) {
      final text = _text(json['checkedAt']);
      final date = DateTime.parse(text);
      if (!date.isUtc || date.toIso8601String() != text) _invalid();
      state.checked = date;
    }
    if (json['pending'] != null) {
      final map = backupObject(json['pending'], {
        'id',
        'kind',
        'image',
        'epoch',
        'version',
      });
      final kind = SyncOperationKind.values.byName(_text(map['kind']));
      final id = _text(map['id']);
      if (!backupUuid.hasMatch(id) ||
          (kind == SyncOperationKind.download) != (map['version'] != null) ||
          (kind == SyncOperationKind.upload && map['image'] == null)) {
        _invalid();
      }
      state.pending = PendingSyncOperation(
        id: id,
        kind: kind,
        image: map['image'] == null ? null : _decodeImage(map['image']),
        restoreEpoch: map['epoch'] == null ? null : _text(map['epoch']),
        remoteVersion: map['version'] == null ? null : _version(map['version']),
      );
    }
    return state;
  }
}
