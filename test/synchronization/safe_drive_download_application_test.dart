import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_restore_image_policy.dart';
import 'package:myautofinance/app/drive_access_factory.dart';
import 'package:myautofinance/app/drive_download_factory.dart';
import 'package:myautofinance/app/local_backup_factory.dart';
import 'package:myautofinance/app/sync_state_factory.dart';
import 'package:myautofinance/features/synchronization/data/drive_metadata_credential.dart';
import 'package:myautofinance/features/synchronization/data/backup_json.dart';
import 'package:myautofinance/features/synchronization/data/backup_storage.dart';
import 'package:myautofinance/features/synchronization/data/local_backup_service.dart';
import 'package:myautofinance/features/synchronization/data/local_restore_candidate_service.dart';
import 'package:myautofinance/features/synchronization/data/local_restore_service.dart';
import 'package:myautofinance/features/synchronization/data/native_backup_persistence.dart';
import 'package:myautofinance/features/synchronization/data/stored_installation_sync_state.dart';
import 'package:myautofinance/features/synchronization/data/safe_drive_download_application.dart';
import 'package:myautofinance/features/synchronization/drive_download.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

import '../support/integral_reference.dart';

class _Provider implements DriveSessionProvider, DriveMetadataCredentialSource {
  int clearCalls = 0;
  final session = DriveSession(
    account: DriveAccount(permissionId: 'account'),
    validUntil: DateTime.utc(2030),
    grantedScopes: const {driveFileScope},
    folder: DriveFolderBinding(accountId: 'account', folderId: 'folder'),
  );
  @override
  Future<DriveSession?> readLocalSession() async => session;
  @override
  Future<DriveMetadataCredential> readCredential({
    required String accountId,
  }) async =>
      DriveMetadataCredential(session: session, accessToken: 'synthetic');
  @override
  Future<DriveSession> authorize({
    required Set<String> scopes,
    required String? expectedAccountId,
    required bool selectAccount,
  }) => throw UnimplementedError();
  @override
  Future<DriveSession> renew({required String accountId}) =>
      throw UnimplementedError();
  @override
  Future<void> clearLocalSession() async {
    clearCalls++;
  }

  @override
  Future<void> rememberFolder(DriveFolderBinding folder) async {}
}

class _Remote {
  List<int> bytes = [];
  List<int>? body;
  String version = '7';
  String? checksum;
  bool includeHash = true, includeSize = true;
  bool noCopy = false, duplicate = false, offline = false, failMedia = false;
  int downloads = 0;
  Future<void> Function()? duringDownload;
  final requests = <http.Request>[];
  Map<String, dynamic> get file => {
    'id': 'copy',
    'name': 'autofinance.sqlite',
    'mimeType': 'application/octet-stream',
    'parents': ['folder'],
    'trashed': false,
    'version': version,
    'modifiedTime': '2026-10-02T12:00:00.000Z',
    if (includeSize) 'size': '${bytes.length}',
    if (includeHash) 'md5Checksum': checksum ?? md5.convert(bytes).toString(),
    'appProperties': driveAutofinanceCopyProperties,
  };
  late final client = MockClient((r) async {
    requests.add(r);
    if (offline) throw const SocketException('synthetic');
    http.Response json(Object value) => http.Response(jsonEncode(value), 200);
    if (r.url.queryParameters['alt'] == 'media') {
      downloads++;
      await duringDownload?.call();
      if (failMedia) throw const SocketException('synthetic');
      return http.Response.bytes(body ?? bytes, 200);
    }
    if (r.url.path.endsWith('/root')) {
      return json({'id': 'root', 'mimeType': driveFolderMimeType});
    }
    if (r.url.path.endsWith('/folder')) {
      return json({
        'id': 'folder',
        'name': 'Autofinance',
        'mimeType': driveFolderMimeType,
        'parents': ['root'],
        'trashed': false,
        'appProperties': driveAutofinanceFolderProperties,
      });
    }
    if (r.url.path.endsWith('/copy')) return json(file);
    return json({
      'files': [
        if (!noCopy) file,
        if (duplicate) {...file, 'id': 'duplicate'},
      ],
    });
  });
}

class _Faults extends NativeBackupPersistence {
  Future<void> Function(String, String)? before;
  Future<void> Function(String, String)? after;
  @override
  Future<void> move(
    String source,
    String target, {
    bool replace = false,
  }) async {
    await before?.call(source, target);
    await super.move(source, target, replace: replace);
    await after?.call(source, target);
  }
}

class _BeforeApply implements DriveDownloader {
  _BeforeApply(this.inner, this.action);
  final DriveDownloader inner;
  final Future<void> Function(ValidatedDriveDownload) action;
  @override
  Future<DriveDownloadResult> download({
    required DriveTransferCancellation cancellation,
    required Future<bool> Function(DriveDownloadReview) review,
    void Function(DriveTransferProgress)? onProgress,
  }) async {
    final result = await inner.download(
      cancellation: cancellation,
      review: review,
      onProgress: onProgress,
    );
    if (result.candidate != null) await action(result.candidate!);
    return result;
  }

  @override
  Future<bool> discard(ValidatedDriveDownload candidate) =>
      inner.discard(candidate);
}

class _Active implements LocalRestoreActiveDatabase {
  _Active(this.store);
  final LocalDatabaseStore store;
  int reopenCalls = 0;
  bool failFirstReopen = false;
  bool failClose = false;
  bool failBackup = false;
  @override
  Future<T> exclusivelyForRestore<T>(Future<T> Function() action) =>
      store.exclusivelyForRestore(action);
  @override
  Future<bool> canOpenExisting() => store.canOpenExisting();
  @override
  Future<LocalBackup> createConsistentBackup() {
    if (failBackup) throw const FileSystemException('synthetic backup failure');
    return store.createConsistentBackup();
  }

  @override
  Future<void> close() async {
    if (failClose) {
      failClose = false;
      throw const FileSystemException('synthetic close failure');
    }
    await store.close();
  }

  @override
  Future<LocalBackupImage> reopenAndValidate() async {
    final image = await store.reopenAndValidate();
    if (++reopenCalls == 1 && failFirstReopen) {
      throw const FileSystemException('synthetic validation failure');
    }
    return image;
  }

  @override
  void requireRecovery() => store.requireRecovery();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late LocalDatabaseStore store;
  late DriveAccessInstallation drive;
  late _Provider provider;
  late _Remote remote;
  late _Active active;
  late _Faults persistence;
  late StoredInstallationSyncState state;
  late DriveDownloadApplication service;
  late List<int> previous;
  late List<String> integralManuals;
  late DriveTransferCancellation cancellation;

  void beforeApply(Future<void> Function(ValidatedDriveDownload) action) {
    final current = service as SafeDriveDownloadApplication;
    service = SafeDriveDownloadApplication(
      downloader: _BeforeApply(current.downloader, action),
      restorer: current.restorer,
      syncState: state,
      access: drive.access,
      copies: drive.copies,
      readDataset: current.readDataset,
    );
  }

  // Comparar todas las tablas: la cabecera de SQLite cambia al reabrir.
  Future<Map<String, List<Map<String, Object?>>>> contents(
    List<int> bytes,
  ) async {
    final file = File(p.join(support.path, 'comparison.sqlite'));
    await file.writeAsBytes(bytes, flush: true);
    final db = sqlite3.open(file.path, mode: OpenMode.readOnly);
    try {
      return {
        for (final row in db.select(
          "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
        ))
          row['name'] as String: db
              .select('SELECT * FROM "${row['name']}" ORDER BY rowid')
              .map((r) => Map<String, Object?>.from(r))
              .toList(),
      };
    } finally {
      db.close();
      await file.delete();
    }
  }

  Future<DriveDownloadApplicationResult> apply({
    Future<bool> Function(DriveDownloadReview)? review,
  }) => service.downloadAndApply(
    cancellation: cancellation,
    review: review ?? (_) async => true,
  );
  Future<void> originalAvailable({String? knownVersion}) async {
    final snapshot = await store.createConsistentBackup();
    expect(
      await contents(await File(snapshot.path).readAsBytes()),
      await contents(previous),
    );
    await File(snapshot.path).parent.delete(recursive: true);
    final sync = await state.inspect(accountId: 'account', fileId: 'copy');
    expect(sync.localStatus, isNot(SyncLocalStatus.clean));
    expect(sync.knownRemoteVersion, knownVersion);
  }

  setUp(() async {
    support = await Directory.systemTemp.createTemp('autofinance-apply-');
    store = LocalDatabaseStore(supportDirectory: () async => support);
    final snapshot = await store.createConsistentBackup();
    remote = _Remote()..bytes = await File(snapshot.path).readAsBytes();
    await File(snapshot.path).parent.delete(recursive: true);
    final db = await store.open();
    await db.writeTransaction(
      () => db.customStatement(
        "INSERT INTO categories(id,name,is_income,created_at,updated_at) VALUES("
        "'11111111-1111-4111-8111-111111111111','Local pendiente',0,"
        "'2026-10-02T12:00:00.000Z','2026-10-02T12:00:00.000Z')",
      ),
    );
    final old = await store.createConsistentBackup();
    previous = await File(old.path).readAsBytes();
    await File(old.path).parent.delete(recursive: true);
    provider = _Provider();
    drive = DriveAccessInstallation(
      provider: provider,
      credentials: provider,
      client: remote.client,
      now: () => DateTime.utc(2026, 10, 2),
    );
    await drive.access.restoreLocalSession();
    active = _Active(store);
    persistence = _Faults();
    cancellation = DriveTransferCancellation();
    state = StoredInstallationSyncState(
      supportDirectory: () async => support,
      readDataset: () async => (await store.open()).readState(),
      contrastReader: createLocalSyncContrastReader(
        supportDirectory: () async => support,
      ),
    );
    service = SafeDriveDownloadApplication(
      downloader: createDriveDownloader(
        drive: drive,
        store: store,
        supportDirectory: () async => support,
      ),
      restorer: LocalRestoreService(
        active: active,
        creator: LocalBackupService(
          source: active,
          validator: const SqliteLocalBackupValidator(),
          supportDirectory: () async => support,
          persistence: persistence,
        ),
        preparer: LocalRestoreCandidateService(
          policy: const SqliteRestoreImagePolicy(),
          supportDirectory: () async => support,
          persistence: persistence,
        ),
        catalog: createLocalBackupCatalog(
          supportDirectory: () async => support,
          persistence: persistence,
        ),
        supportDirectory: () async => support,
        persistence: persistence,
      ),
      syncState: state,
      access: drive.access,
      copies: drive.copies,
      readDataset: () async => (await store.open()).readState(),
    );
  });
  tearDown(() async {
    await drive.dispose();
    remote.client.close();
    await store.close();
    await support.delete(recursive: true);
  });

  // T07: el mismo CSV y las fotos de T02, sin localizar una instalación real.
  Future<void> prepareIntegralImages() async {
    final db = await store.open();
    await db.writeTransaction(
      () => db.customStatement('DELETE FROM categories'),
    );
    await seedIntegralReference(db);
    final base = await store.createConsistentBackup();
    remote.bytes = await File(base.path).readAsBytes();
    await File(base.path).parent.delete(recursive: true);
    final creator = createLocalBackupCreator(
      store: store,
      supportDirectory: () async => support,
    );
    integralManuals = [(await creator.createManual()).backupId];
    final account = (await SqliteMovementRepository(db).readYear(2026))
        .first
        .data
        .accountId;
    await SqliteMovementRepository(db).create(
      MovementInput(
        accountId: account,
        valueDate: ValueDate(2026, 1, 31),
        concept: 'Corrección sintética T07',
        amountCents: -12345,
      ),
    );
    final changed = await store.createConsistentBackup();
    previous = await File(changed.path).readAsBytes();
    await File(changed.path).parent.delete(recursive: true);
    integralManuals.add((await creator.createManual()).backupId);
  }

  Future<void> verifyIntegralFigures({required bool changed}) async {
    final db = await store.open();
    final movements = SqliteMovementRepository(db);
    final january = await movements.readMonth(2026, 1);
    expect(
      january.fold<int>(0, (sum, row) => sum + row.data.amountCents),
      changed ? 110630 : 122975,
    );
    expect(await movements.readYear(2026), hasLength(changed ? 11 : 10));
    final cafes = january.where((row) => row.data.concept == 'Café').toList();
    expect(cafes, hasLength(2));
    expect(cafes.first.id, isNot(cafes.last.id));
    expect(
      (await db
              .customSelect('SELECT sum(amount_cents) AS n FROM budgets')
              .getSingle())
          .read<int>('n'),
      1320000,
    );
    final photos = SqliteWealthRepository(db);
    final januaryPhoto = await photos.read(Month(2026, 1));
    expect(januaryPhoto.status, WealthSnapshotStatus.complete);
    expect(
      januaryPhoto.values
          .where((v) => v.account.liquidity == Liquidity.liquid)
          .fold<int>(0, (sum, v) => sum + v.amountCents),
      900000,
    );
    expect(
      (await photos.read(Month(2026, 2))).status,
      WealthSnapshotStatus.absent,
    );
    expect(
      (await db.customSelect('PRAGMA integrity_check').getSingle())
          .data
          .values
          .single,
      'ok',
    );
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  }

  Future<Map<String, dynamic>> catalogSnapshot() async => (await BackupStorage(
    NativeBackupPersistence(),
    DateTime.now,
  ).loadSlots(p.join(support.path, 'sqlite'))).latest!;

  for (final fault in ['cancel', 'offline', 'truncated', 'future', 'backup']) {
    test('T07 base T02: $fault conserva datos, catálogo y remoto', () async {
      await prepareIntegralImages();
      final remoteBefore = List<int>.of(remote.bytes);
      final versionBefore = remote.version;
      final catalog = createLocalBackupCatalog(
        supportDirectory: () async => support,
      );
      final before = (await catalog.read()).entries
          .map((e) => e.backupId)
          .toList();
      final catalogBefore = await catalogSnapshot();
      Future<void> verifyCatalog() async {
        final current = await catalogSnapshot();
        // El creador reserva un ordinal durable antes de capturar SQLite.
        // Un respaldo fallido puede consumirlo sin publicar ninguna entrada.
        expect(
          backupCounter(current['nextCreationOrder']),
          backupCounter(catalogBefore['nextCreationOrder']) +
              (fault == 'backup' ? 1 : 0),
        );
        expect(
          backupCounter(current['generation']),
          greaterThanOrEqualTo(backupCounter(catalogBefore['generation'])),
        );
        final expected = {...catalogBefore};
        for (final key in ['generation', 'writtenAtUtc', 'nextCreationOrder']) {
          current.remove(key);
          expected.remove(key);
        }
        expect(current, expected); // Entradas, hashes, epoch y contraste.
      }

      remote.offline = fault == 'offline';
      active.failBackup = fault == 'backup';
      if (fault == 'truncated') remote.body = remote.bytes.take(512).toList();
      if (fault == 'future') {
        final file = File(p.join(support.path, 'future.sqlite'));
        await file.writeAsBytes(remote.bytes, flush: true);
        final db = sqlite3.open(file.path);
        db.execute('PRAGMA user_version=99');
        db.close();
        remote.bytes = await file.readAsBytes();
      }
      final offeredBytes = List<int>.of(remote.bytes);
      final result = await apply(
        review: (review) async {
          expect(review.requiresConfirmation, isTrue);
          return fault != 'cancel';
        },
      );
      expect(result.status, isNot(DriveDownloadApplicationStatus.downloaded));
      if (fault == 'cancel') {
        expect(result.status, DriveDownloadApplicationStatus.cancelled);
        expect(remote.downloads, 0);
      }
      expect(result.remote, isNull);
      await originalAvailable(); // Todas las tablas, datasetId y revisión.
      await verifyIntegralFigures(changed: true);
      expect((await catalog.read()).entries.map((e) => e.backupId), before);
      await verifyCatalog();
      expect(remote.bytes, offeredBytes);
      if (fault != 'future') expect(remote.bytes, remoteBefore);
      expect(remote.version, versionBefore);
      final calls = remote.requests.length;
      await store.close();
      store = LocalDatabaseStore(supportDirectory: () async => support);
      await originalAvailable();
      await verifyIntegralFigures(changed: true);
      await verifyCatalog();
      expect(remote.requests.length, calls);
    });
  }

  test(
    'T07 base T02: descargar y recuperar explícitamente la versión local',
    () async {
      await prepareIntegralImages();
      final remoteBefore = List<int>.of(remote.bytes);
      final result = await apply();
      expect(result.status, DriveDownloadApplicationStatus.downloaded);
      await verifyIntegralFigures(changed: false);
      final downloaded = await store.createConsistentBackup();
      expect(
        await contents(await File(downloaded.path).readAsBytes()),
        await contents(remoteBefore),
      );
      await File(downloaded.path).parent.delete(recursive: true);
      final saved = result.restore!.previousBackupId!;
      final restored = await createLocalRestorer(
        store: store,
        supportDirectory: () async => support,
      ).restore(saved, confirmed: true);
      expect(restored.status, LocalRestoreStatus.restored);
      final calls = remote.requests.length;
      await store.close();
      store = LocalDatabaseStore(supportDirectory: () async => support);
      await originalAvailable(knownVersion: '7');
      await verifyIntegralFigures(changed: true);
      expect(
        (await createLocalSyncContrastReader(
          supportDirectory: () async => support,
        ).read()).required,
        isTrue,
      );
      expect(
        (await drive.access.restoreLocalSession()).account?.permissionId,
        'account',
      );
      expect(provider.clearCalls, 0);
      expect(remote.requests.length, calls);
      expect(remote.bytes, remoteBefore);
      expect(remote.version, '7');
      final listing = await createLocalBackupCatalog(
        supportDirectory: () async => support,
      ).read();
      expect(
        listing.entries.map((e) => e.backupId),
        containsAll([...integralManuals, saved, restored.previousBackupId!]),
      );
      // La versión descargada también sigue recuperable, sin contactar Drive.
      expect(
        (await createLocalRestorer(
          store: store,
          supportDirectory: () async => support,
        ).restore(restored.previousBackupId!, confirmed: true)).status,
        LocalRestoreStatus.restored,
      );
      await verifyIntegralFigures(changed: false);
    },
  );

  test('confirmación rechazada conserva activa sin transferencia', () async {
    expect(remote.requests, isEmpty);
    final result = await apply(
      review: (review) async {
        expect(review.requiresConfirmation, isTrue);
        return false;
      },
    );
    expect(result.status, DriveDownloadApplicationStatus.cancelled);
    expect(remote.downloads, 0);
    await originalAvailable();
  });

  test(
    'descargar no abandona una subida pendiente de otra identidad',
    () async {
      final pending = await state.beginUpload(
        accountId: 'other-account',
        fileId: 'other-file',
        capturedImage: await (await store.open()).readState(),
      );
      final result = await apply();
      expect(result.status, DriveDownloadApplicationStatus.downloadRejected);
      expect(remote.downloads, 0);
      await expectLater(
        state.beginDownload(
          accountId: 'account',
          remote: DriveFileMetadata(
            id: 'copy',
            name: 'autofinance.sqlite',
            mimeType: 'application/octet-stream',
            parents: ['folder'],
            trashed: false,
            version: '7',
          ),
        ),
        throwsA(isA<SyncStateFailure>()),
      );
      expect(
        (await state.inspect(
          accountId: 'other-account',
          fileId: 'other-file',
        )).pending!.id,
        pending.id,
      );
    },
  );

  test(
    'primera descarga: datos, versión, fecha y respaldo recuperable',
    () async {
      // Comprobar también la composición pública, sin operaciones al crearla.
      service = createDriveDownloadApplication(
        drive: drive,
        store: store,
        supportDirectory: () async => support,
      );
      expect(remote.requests, isEmpty);
      final result = await apply();
      expect(result.status, DriveDownloadApplicationStatus.downloaded);
      expect(result.remote!.version, '7');
      expect(result.restore!.previousBackupId, isNotNull);
      final db = await store.open();
      expect(await db.customSelect('SELECT * FROM categories').get(), isEmpty);
      final image = await store.createConsistentBackup();
      expect(
        await contents(await File(image.path).readAsBytes()),
        await contents(remote.bytes),
      );
      await File(image.path).parent.delete(recursive: true);
      final sync = await state.inspect(accountId: 'account', fileId: 'copy');
      expect(sync.localStatus, SyncLocalStatus.clean);
      expect(sync.knownRemoteVersion, '7');
      expect(result.remote!.modifiedTime, DateTime.utc(2026, 10, 2, 12));
      final backupPath = p.join(
        support.path,
        'sqlite',
        'local-backups',
        'backups',
        result.restore!.previousBackupId!,
        'autofinance.sqlite',
      );
      expect(await File(backupPath).readAsBytes(), previous);
      final calls = remote.requests.length;
      await store.close();
      store = LocalDatabaseStore(supportDirectory: () async => support);
      await store.open();
      final restarted = createInstallationSyncState(
        store: store,
        supportDirectory: () async => support,
      );
      expect(
        (await restarted.inspect(
          accountId: 'account',
          fileId: 'copy',
        )).localStatus,
        SyncLocalStatus.clean,
      );
      expect(remote.requests.length, calls);
      final restored = await createLocalRestorer(
        store: store,
        supportDirectory: () async => support,
      ).restore(result.restore!.previousBackupId!, confirmed: true);
      expect(restored.status, LocalRestoreStatus.restored);
      final recovered = await store.createConsistentBackup();
      expect(
        await contents(await File(recovered.path).readAsBytes()),
        await contents(previous),
      );
      await File(recovered.path).parent.delete(recursive: true);
    },
  );

  for (final fault in ['backup', 'close', 'replace', 'reopen']) {
    test('fallo en $fault conserva anterior y no marca sincronizado', () async {
      active.failBackup = fault == 'backup';
      active.failClose = fault == 'close';
      active.failFirstReopen = fault == 'reopen';
      var fired = false;
      if (fault == 'replace') {
        persistence.before = (source, target) async {
          if (!fired &&
              target == p.join(support.path, 'sqlite', 'autofinance.sqlite')) {
            fired = true;
            throw const FileSystemException('synthetic replace failure');
          }
        };
      }
      final result = await apply();
      expect(result.status, isNot(DriveDownloadApplicationStatus.downloaded));
      expect(result.remote, isNull);
      await originalAvailable();
      await store.close();
      store = LocalDatabaseStore(supportDirectory: () async => support);
      await originalAvailable();
    });
  }

  test(
    'edición posterior a validar impide aplicar sin nueva confirmación',
    () async {
      beforeApply((_) async {
        final db = await store.open();
        await db.writeTransaction(
          () => db.customStatement(
            "UPDATE categories SET name='Cambio durante descarga'",
          ),
        );
        final image = await store.createConsistentBackup();
        previous = await File(image.path).readAsBytes();
        await File(image.path).parent.delete(recursive: true);
      });
      final result = await apply();
      expect(result.status, DriveDownloadApplicationStatus.localChanged);
      expect(active.reopenCalls, 0);
      await originalAvailable();
    },
  );

  test('versión remota cambiada antes de aplicar conserva activa', () async {
    beforeApply((_) async => remote.version = '8');
    final result = await apply();
    expect(result.status, DriveDownloadApplicationStatus.remoteChanged);
    expect(active.reopenCalls, 0);
    await originalAvailable();
  });

  test('candidata manipulada después de validar es rechazada', () async {
    beforeApply((image) async {
      await File(image.path)
          .writeAsBytes([0], mode: FileMode.append, flush: true);
    });
    final result = await apply();
    expect(result.status, DriveDownloadApplicationStatus.failed);
    expect(active.reopenCalls, 0);
    await originalAvailable();
  });

  test('fallo al guardar sincronía revierte y deja estado honesto', () async {
    final syncPersistence = _Faults();
    var saves = 0;
    syncPersistence.before = (source, target) async {
      if (p.basename(target) == 'state.json' && ++saves == 3) {
        // Selección de identidad, operación pendiente, vínculo final.
        throw const FileSystemException('synthetic sync save failure');
      }
    };
    state = StoredInstallationSyncState(
      supportDirectory: () async => support,
      readDataset: () async => (await store.open()).readState(),
      contrastReader: createLocalSyncContrastReader(
        supportDirectory: () async => support,
      ),
      persistence: syncPersistence,
    );
    beforeApply((_) async {});
    final result = await apply();
    expect(saves, greaterThanOrEqualTo(3));
    expect(result.status, DriveDownloadApplicationStatus.rolledBack);
    await originalAvailable();
  });

  for (final phase in ['protected', 'isolating', 'installed', 'validated']) {
    test('cancelar en $phase revierte sin acreditar versión', () async {
      persistence.after = (source, target) async {
        if (p.basename(target).startsWith('journal-')) {
          final journal = decodeBackupEnvelope(
            await File(target).readAsBytes(),
          );
          if (journal['phase'] == phase) cancellation.cancel();
        }
      };
      final result = await apply();
      expect(result.status, DriveDownloadApplicationStatus.cancelled);
      await originalAvailable();
    });
  }

  for (final phase in ['installing', 'validated']) {
    test(
      'interrupción en $phase: recuperación local y sync pendiente al reiniciar',
      () async {
        var interrupted = false;
        persistence.before = (source, target) async {
          if (interrupted) {
            throw const FileSystemException('synthetic interruption');
          }
        };
        persistence.after = (source, target) async {
          if (p.basename(target).startsWith('journal-')) {
            final journal = decodeBackupEnvelope(
              await File(target).readAsBytes(),
            );
            if (journal['phase'] == phase) {
              interrupted = true;
              throw const FileSystemException('synthetic interruption');
            }
          }
        };
        final result = await apply();
        expect(result.status, DriveDownloadApplicationStatus.recoveryRequired);
        final calls = remote.requests.length;
        await store.close();
        store = LocalDatabaseStore(supportDirectory: () async => support);
        await store.open();
        final restarted = createInstallationSyncState(
          store: store,
          supportDirectory: () async => support,
        );
        final sync = await restarted.inspect(
          accountId: 'account',
          fileId: 'copy',
        );
        expect(sync.localStatus, SyncLocalStatus.pending);
        expect(sync.knownRemoteVersion, isNull);
        expect(remote.requests.length, calls);
        final image = await store.createConsistentBackup();
        expect(
          await contents(await File(image.path).readAsBytes()),
          await contents(phase == 'validated' ? remote.bytes : previous),
        );
        await File(image.path).parent.delete(recursive: true);
        // Repetir es una nueva acción explícita: limpiar solo pending download
        // ya recuperado y exigir revisión; nunca acreditar la imagen por azar.
        service = createDriveDownloadApplication(
          drive: drive,
          store: store,
          supportDirectory: () async => support,
        );
        final retry = await apply(
          review: (review) async {
            expect(review.requiresConfirmation, isTrue);
            return true;
          },
        );
        expect(retry.status, DriveDownloadApplicationStatus.downloaded);
        expect(
          (await restarted.inspect(
            accountId: 'account',
            fileId: 'copy',
          )).localStatus,
          SyncLocalStatus.clean,
        );
      },
    );
  }
}
