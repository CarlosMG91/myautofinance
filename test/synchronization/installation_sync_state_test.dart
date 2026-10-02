import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/local_backup_factory.dart';
import 'package:myautofinance/app/sync_state_factory.dart';
import 'package:myautofinance/core/persistence/unit_of_work.dart';
import 'package:myautofinance/features/synchronization/data/stored_installation_sync_state.dart';
import 'package:myautofinance/features/synchronization/data/native_backup_persistence.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';
import 'package:path/path.dart' as p;

const image = DatasetState(
  datasetId: '11111111-1111-4111-8111-111111111111',
  revision: 4,
);

class _Contrast implements LocalSyncContrastReader {
  LocalSyncContrast value = const LocalSyncContrast(
    restoreEpoch: null,
    required: true,
  );
  @override
  Future<LocalSyncContrast> read() async => value;
}

class _Fault extends NativeBackupPersistence {
  bool fail = false;
  @override
  Future<void> move(
    String source,
    String target, {
    bool replace = false,
  }) async {
    if (fail && p.basename(target) == 'state.json') {
      throw const FileSystemException('synthetic');
    }
    await super.move(source, target, replace: replace);
  }
}

DriveFileMetadata remote(String version, {String id = 'file-a'}) =>
    DriveFileMetadata(
      id: id,
      name: 'autofinance.sqlite',
      mimeType: 'application/vnd.sqlite3',
      parents: ['folder'],
      trashed: false,
      version: version,
    );
Matcher failure(SyncStateIssue issue) =>
    isA<SyncStateFailure>().having((e) => e.issue, 'issue', issue);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late _Contrast contrast;
  late DatasetState current;
  late _Fault persistence;
  StoredInstallationSyncState service() => StoredInstallationSyncState(
    supportDirectory: () async => support,
    readDataset: () async => current,
    contrastReader: contrast,
    persistence: persistence,
    now: () => DateTime.utc(2026, 10, 2, 12),
  );
  Future<InstallationSyncSnapshot> inspect(
    InstallationSyncState state, {
    String account = 'account-a',
    String file = 'file-a',
  }) => state.inspect(accountId: account, fileId: file);
  Future<void> upload(InstallationSyncState state) async {
    final op = await state.beginUpload(
      accountId: 'account-a',
      fileId: 'file-a',
      capturedImage: current,
    );
    await state.completeUpload(operationId: op.id, remote: remote('10'));
  }

  setUp(() async {
    support = await Directory.systemTemp.createTemp('autofinance-sync-state-');
    contrast = _Contrast();
    current = image;
    persistence = _Fault();
  });
  tearDown(() async => support.delete(recursive: true));

  test(
    'desconocido no es limpio; consultar metadatos no vincula SQLite',
    () async {
      final state = service();
      expect(
        (await inspect(state)).localStatus,
        SyncLocalStatus.contrastRequired,
      );
      contrast.value = const LocalSyncContrast(
        restoreEpoch: null,
        required: false,
      );
      await state.recordCheck(accountId: 'account-a', remote: remote('10'));
      final read = await inspect(service());
      expect(read.localStatus, SyncLocalStatus.unknown);
      expect(read.knownRemoteVersion, isNull);
      expect(read.checkedAt, DateTime.utc(2026, 10, 2, 12));
    },
  );
  test('reinicio conserva versión, revisión y fecha sin tokens; observa divergencia', () async {
    await upload(service());
    final state = service();
    final read = await inspect(state);
    expect(read.localStatus, SyncLocalStatus.clean);
    expect(read.knownRemoteVersion, '10');
    expect(read.correspondingLocalState!.revision, 4);
    await state.recordCheck(accountId: 'account-a', remote: remote('11'));
    expect((await inspect(service())).remoteChanged, isTrue);
    await expectLater(
      state.beginUpload(
        accountId: 'account-a',
        fileId: 'file-a',
        capturedImage: image,
      ),
      throwsA(failure(SyncStateIssue.remoteDivergence)),
    );
    final bytes = await File(p.join(support.path, 'drive-sync', 'state.json'))
        .readAsString();
    expect(bytes, isNot(contains('token')));
    expect(await Directory(p.join(support.path, 'sqlite')).exists(), isFalse);
  });
  test(
    'ediciones antes y durante transferencia no se marcan como subidas',
    () async {
      final state = service();
      final op = await state.beginUpload(
        accountId: 'account-a',
        fileId: 'file-a',
        capturedImage: image,
      );
      current = DatasetState(datasetId: image.datasetId, revision: 6);
      await service().completeUpload(operationId: op.id, remote: remote('10'));
      final read = await inspect(service());
      expect(read.correspondingLocalState!.revision, 4);
      expect(read.localStatus, SyncLocalStatus.changed);
      current = const DatasetState(
        datasetId: '22222222-2222-4222-8222-222222222222',
        revision: 4,
      );
      expect((await inspect(service())).localStatus, SyncLocalStatus.changed);
    },
  );
  test('cambiar cuenta o archivo invalida incluso al volver', () async {
    final state = service();
    await upload(state);
    expect(
      (await inspect(state, account: 'account-b')).knownRemoteVersion,
      isNull,
    );
    expect((await inspect(service())).knownRemoteVersion, isNull);
    await upload(state);
    expect((await inspect(state, file: 'file-b')).knownRemoteVersion, isNull);
    expect((await inspect(service())).knownRemoteVersion, isNull);
  });
  test('cambio de cuenta durante operación invalida acuse tardío', () async {
    final state = service();
    final op = await state.beginUpload(
      accountId: 'account-a',
      fileId: 'file-a',
      capturedImage: image,
    );
    await inspect(state, account: 'account-b');
    await expectLater(
      state.completeUpload(operationId: op.id, remote: remote('10')),
      throwsA(failure(SyncStateIssue.staleOperation)),
    );
  });
  test(
    'operación pendiente persiste, bloquea otra y abandono queda desconocido',
    () async {
      final op = await service().beginUpload(
        accountId: 'account-a',
        fileId: 'file-a',
        capturedImage: image,
      );
      final state = service();
      expect((await inspect(state)).pending!.id, op.id);
      await expectLater(
        state.beginUpload(
          accountId: 'account-a',
          fileId: 'file-a',
          capturedImage: image,
        ),
        throwsA(failure(SyncStateIssue.operationInProgress)),
      );
      await state.abandonPending(operationId: op.id);
      expect((await inspect(service())).knownRemoteVersion, isNull);
    },
  );
  test(
    'restauración exige contraste aunque linaje/revisión sean idénticos',
    () async {
      final state = service();
      await upload(state);
      contrast.value = const LocalSyncContrast(
        restoreEpoch: 'restore-1',
        required: true,
      );
      expect(
        (await inspect(state)).localStatus,
        SyncLocalStatus.contrastRequired,
      );
      await state.recordCheck(accountId: 'account-a', remote: remote('10'));
      expect(
        (await inspect(state)).localStatus,
        SyncLocalStatus.contrastRequired,
      );
      await upload(state);
      expect((await inspect(service())).localStatus, SyncLocalStatus.clean);
      contrast.value = const LocalSyncContrast(
        restoreEpoch: 'restore-1',
        required: true,
        unreliable: true,
      );
      expect(
        (await inspect(state)).localStatus,
        SyncLocalStatus.contrastRequired,
      );
    },
  );
  test(
    'restauración durante subida y archivo incorrecto conservan pendiente',
    () async {
      final state = service();
      final op = await state.beginUpload(
        accountId: 'account-a',
        fileId: 'file-a',
        capturedImage: image,
      );
      await expectLater(
        state.completeUpload(
          operationId: op.id,
          remote: remote('10', id: 'file-b'),
        ),
        throwsA(failure(SyncStateIssue.staleOperation)),
      );
      contrast.value = const LocalSyncContrast(
        restoreEpoch: 'restore-1',
        required: true,
      );
      await expectLater(
        state.completeUpload(operationId: op.id, remote: remote('10')),
        throwsA(failure(SyncStateIssue.installationNotConfirmed)),
      );
      expect((await inspect(service())).localStatus, SyncLocalStatus.pending);
    },
  );
  for (final status in [
    LocalRestoreStatus.cancelled,
    LocalRestoreStatus.rejected,
    LocalRestoreStatus.rolledBack,
    LocalRestoreStatus.recoveryRequired,
  ]) {
    test('descarga $status no vincula base', () async {
      final state = service();
      final op = await state.beginDownload(
        accountId: 'account-a',
        remote: remote('20'),
        downloadedImage: image,
      );
      expect((await inspect(service())).knownRemoteVersion, isNull);
      await state.installDownload(
        operationId: op.id,
        install: () async => LocalRestoreResult(status),
      );
      expect((await inspect(service())).pending!.id, op.id);
      expect((await inspect(state)).knownRemoteVersion, isNull);
    });
  }
  test('solo descarga instalada y validada vincula versión remota', () async {
    final state = service();
    final op = await state.beginDownload(
      accountId: 'account-a',
      remote: remote('20'),
      downloadedImage: image,
    );
    await state.installDownload(
      operationId: op.id,
      install: () async {
        contrast.value = const LocalSyncContrast(
          restoreEpoch: 'restore-1',
          required: true,
        );
        return const LocalRestoreResult(LocalRestoreStatus.restored);
      },
    );
    expect((await inspect(service())).knownRemoteVersion, '20');
    expect((await inspect(state)).localStatus, SyncLocalStatus.clean);
  });
  test('descarga pendiente desde el inicio de red requiere imagen validada antes de aplicar', () async {
    final op = await service().beginDownload(
      accountId: 'account-a',
      remote: remote('20'),
    );
    expect((await inspect(service())).pending!.image, isNull);
    var called = false;
    await expectLater(
      service().installDownload(
        operationId: op.id,
        install: () async {
          called = true;
          return const LocalRestoreResult(LocalRestoreStatus.restored);
        },
      ),
      throwsA(failure(SyncStateIssue.installationNotConfirmed)),
    );
    expect(called, isFalse);
    await service().recordDownloadedImage(
      operationId: op.id,
      downloadedImage: image,
    );
    expect((await inspect(service())).pending!.image!.revision, image.revision);
    await service().installDownload(
      operationId: op.id,
      install: () async {
        contrast.value = const LocalSyncContrast(
          restoreEpoch: 'restore-1',
          required: true,
        );
        return const LocalRestoreResult(LocalRestoreStatus.restored);
      },
    );
    expect((await inspect(service())).localStatus, SyncLocalStatus.clean);
  });
  test(
    'éxito sin nuevo epoch o con otra imagen no acredita instalación',
    () async {
      final state = service();
      final op = await state.beginDownload(
        accountId: 'account-a',
        remote: remote('20'),
        downloadedImage: image,
      );
      await expectLater(
        state.installDownload(
          operationId: op.id,
          install: () async =>
              const LocalRestoreResult(LocalRestoreStatus.restored),
        ),
        throwsA(failure(SyncStateIssue.installationNotConfirmed)),
      );
      contrast.value = const LocalSyncContrast(
        restoreEpoch: 'restore-1',
        required: true,
      );
      current = DatasetState(datasetId: image.datasetId, revision: 5);
      await expectLater(
        state.installDownload(
          operationId: op.id,
          install: () async =>
              const LocalRestoreResult(LocalRestoreStatus.restored),
        ),
        throwsA(failure(SyncStateIssue.installationNotConfirmed)),
      );
      expect((await inspect(service())).knownRemoteVersion, isNull);
    },
  );
  test('fallo de publicación local conserva pendiente al reiniciar', () async {
    final state = service();
    final op = await state.beginUpload(
      accountId: 'account-a',
      fileId: 'file-a',
      capturedImage: image,
    );
    persistence.fail = true;
    await expectLater(
      state.completeUpload(operationId: op.id, remote: remote('10')),
      throwsA(failure(SyncStateIssue.storageFailure)),
    );
    persistence.fail = false;
    expect((await inspect(service())).pending!.id, op.id);
    await service().completeUpload(operationId: op.id, remote: remote('10'));
    expect((await inspect(service())).localStatus, SyncLocalStatus.clean);
  });
  test('estado dañado no se degrada a limpio ni se sobrescribe', () async {
    await upload(service());
    final file = File(p.join(support.path, 'drive-sync', 'state.json'));
    await file.writeAsString('damaged synthetic');
    await expectLater(
      inspect(service()),
      throwsA(failure(SyncStateIssue.storageFailure)),
    );
    expect(await file.readAsString(), 'damaged synthetic');
  });
  test(
    'exclusión entre instancias protege instalación y rechaza carreras',
    () async {
      final state = service();
      final op = await state.beginDownload(
        accountId: 'account-a',
        remote: remote('20'),
        downloadedImage: image,
      );
      final entered = Completer<void>();
      final finish = Completer<void>();
      final installing = state.installDownload(
        operationId: op.id,
        install: () async {
          entered.complete();
          await finish.future;
          return const LocalRestoreResult(LocalRestoreStatus.cancelled);
        },
      );
      await entered.future;
      await expectLater(
        inspect(state),
        throwsA(failure(SyncStateIssue.operationInProgress)),
      );
      await expectLater(
        inspect(service()),
        throwsA(failure(SyncStateIssue.operationInProgress)),
      );
      finish.complete();
      await installing;
    },
  );
  test(
    'SQLite y restaurador reales: edición, reinicio y descarga instalada',
    () async {
      final store = LocalDatabaseStore(supportDirectory: () async => support);
      addTearDown(store.close);
      final db = await store.open();
      final captured = await store.createConsistentBackup();
      final state = createInstallationSyncState(
        store: store,
        supportDirectory: () async => support,
      );
      final op = await state.beginUpload(
        accountId: 'account-a',
        fileId: 'file-a',
        capturedImage: captured.state,
      );
      await db.writeTransaction(
        () => db.customStatement(
          "INSERT INTO categories(id,name,is_income,created_at,updated_at) VALUES('11111111-1111-4111-8111-111111111111','Sintética',0,'2026-10-02T12:00:00.000Z','2026-10-02T12:00:00.000Z')",
        ),
      );
      await state.completeUpload(operationId: op.id, remote: remote('10'));
      expect((await inspect(state)).localStatus, SyncLocalStatus.changed);
      final creator = createLocalBackupCreator(
        store: store,
        supportDirectory: () async => support,
      );
      final backup = await creator.createManual();
      final restorer = createLocalRestorer(
        store: store,
        supportDirectory: () async => support,
      );
      final candidate = await store.createConsistentBackup();
      final download = await state.beginDownload(
        accountId: 'account-a',
        remote: remote('20'),
        downloadedImage: candidate.state,
      );
      await state.installDownload(
        operationId: download.id,
        install: () => restorer.restore(backup.backupId, confirmed: true),
      );
      expect((await inspect(state)).localStatus, SyncLocalStatus.clean);
      await store.close();
      final restarted = createInstallationSyncState(
        store: store,
        supportDirectory: () async => support,
      );
      expect((await inspect(restarted)).knownRemoteVersion, '20');
      await restorer.restore(backup.backupId, confirmed: true);
      expect(
        (await inspect(restarted)).localStatus,
        SyncLocalStatus.contrastRequired,
      );
    },
  );
}
