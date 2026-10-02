import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:myautofinance/app/drive_access_factory.dart';
import 'package:myautofinance/app/drive_upload_factory.dart';
import 'package:myautofinance/app/drive_download_factory.dart';
import 'package:myautofinance/app/drive_reconciliation_factory.dart';
import 'package:myautofinance/app/local_backup_factory.dart';
import 'package:myautofinance/app/sync_state_factory.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/synchronization/data/drive_metadata_credential.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';
import 'package:myautofinance/features/synchronization/drive_download.dart';
import 'package:myautofinance/features/synchronization/drive_reconciliation.dart';

import '../support/recovery_reference.dart';

// Misma cuenta sintética; cada instalación tiene su propio estado y SQLite.
class _Provider implements DriveSessionProvider, DriveMetadataCredentialSource {
  DriveSession session = DriveSession(
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
      DriveMetadataCredential(session: session, accessToken: 'synthetic-token');
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
  Future<void> clearLocalSession() async {}
  @override
  Future<void> rememberFolder(DriveFolderBinding folder) async {}
}

/// Servidor sin escritura condicional: sesiones independientes y un archivo.
/// Conserva revisiones solo para observar la carrera; no promete retención.
class _Drive {
  Map<String, dynamic>? file;
  final revisions = <List<int>>[];
  final sessions =
      <String, ({Map<String, dynamic> metadata, List<int> bytes})>{};
  int starts = 0, commits = 0, downloads = 0;
  bool interruptUpload = false, loseAck = false;
  bool truncateDownload = false, interruptDownload = false;
  Future<void> Function()? beforePublish;

  http.Client client() => MockClient((r) async {
    http.Response json(Object value, [int status = 200]) =>
        http.Response(jsonEncode(value), status);
    final path = r.url.path;
    if (r.url.queryParameters['alt'] == 'media') {
      downloads++;
      if (interruptDownload) {
        throw const SocketException('synthetic interruption');
      }
      final bytes = revisions.last;
      return http.Response.bytes(
        truncateDownload ? bytes.sublist(0, bytes.length ~/ 2) : bytes,
        200,
      );
    }
    if (path.endsWith('/root')) {
      return json({'id': 'root', 'mimeType': driveFolderMimeType});
    }
    if (path.endsWith('/folder')) {
      return json({
        'id': 'folder',
        'name': 'Autofinance',
        'mimeType': driveFolderMimeType,
        'parents': ['root'],
        'trashed': false,
        'appProperties': driveAutofinanceFolderProperties,
      });
    }
    if (r.method == 'GET') {
      if (path.endsWith('/copy')) {
        return file == null ? json({}, 404) : json(file!);
      }
      return json({
        'files': [if (file != null) file],
      });
    }
    if (r.method == 'POST' || r.method == 'PATCH') {
      final id = '${++starts}';
      sessions[id] = (
        metadata: jsonDecode(r.body) as Map<String, dynamic>,
        bytes: <int>[],
      );
      return http.Response(
        '',
        200,
        headers: {
          'location':
              'https://www.googleapis.com/upload/drive/v3/files?upload_id=$id',
        },
      );
    }
    expect(r.method, 'PUT');
    expect(r.headers.keys.any((k) => k.toLowerCase() == 'if-match'), isFalse);
    final session = sessions[r.url.queryParameters['upload_id']]!;
    if (interruptUpload) throw const SocketException('synthetic interruption');
    session.bytes.addAll(r.bodyBytes);
    final total = int.parse(r.headers['Content-Range']!.split('/').last);
    if (session.bytes.length < total) {
      return http.Response(
        '',
        308,
        headers: {'range': 'bytes=0-${session.bytes.length - 1}'},
      );
    }
    // El gate real ya leyó la versión; bloquear aquí abre la carrera.
    await beforePublish?.call();
    publish(
      session.bytes,
      session.metadata['appProperties'] as Map<String, dynamic>,
    );
    commits++;
    if (loseAck) throw const SocketException('synthetic lost acknowledgement');
    return json(file!);
  });

  void publish(List<int> bytes, Map<String, dynamic> properties) {
    revisions.add(List.of(bytes));
    file = {
      'id': 'copy',
      'name': driveAutofinanceCopyName,
      'mimeType': 'application/octet-stream',
      'parents': ['folder'],
      'trashed': false,
      'version': '${revisions.length}',
      'modifiedTime': '2026-10-02T15:00:00.000Z',
      'size': '${bytes.length}',
      'md5Checksum': md5.convert(bytes).toString(),
      'appProperties': properties,
    };
  }
}

class _Installation {
  _Installation(this.directory, this.store, this.drive);
  final Directory directory;
  LocalDatabaseStore store;
  final DriveAccessInstallation drive;
  InstallationSyncState get state => createInstallationSyncState(
    store: store,
    supportDirectory: () async => directory,
  );
  Future<InstallationSyncSnapshot> inspect() =>
      state.inspect(accountId: 'account', fileId: 'copy');
  Future<DriveUploadResult> upload({
    void Function(DriveTransferProgress)? progress,
  }) => createDriveUploader(
    drive: drive,
    store: store,
    supportDirectory: () async => directory,
  ).upload(cancellation: DriveTransferCancellation(), onProgress: progress);
  Future<DriveDownloadApplicationResult> download({
    Future<bool> Function(DriveDownloadReview)? review,
    DriveTransferCancellation? cancellation,
    void Function(DriveTransferProgress)? progress,
  }) =>
      createDriveDownloadApplication(
        drive: drive,
        store: store,
        supportDirectory: () async => directory,
      ).downloadAndApply(
        cancellation: cancellation ?? DriveTransferCancellation(),
        review: review ?? (_) async => true,
        onProgress: progress,
      );
  DriveReconciliation get reconciliation => createDriveReconciliation(
    drive: drive,
    store: store,
    supportDirectory: () async => directory,
  );
  Future<void> edit(String concept, int cents) async {
    final db = await store.open();
    final account =
        (await db
                .customSelect(
                  "SELECT id FROM accounts WHERE name='Cuenta principal'",
                )
                .getSingle())
            .read<String>('id');
    await SqliteMovementRepository(db).create(
      MovementInput(
        accountId: account,
        valueDate: ValueDate(2026, 1, 31),
        concept: concept,
        amountCents: cents,
      ),
    );
  }

  Future<void> restart() async {
    await store.close();
    store = LocalDatabaseStore(supportDirectory: () async => directory);
    await store.open();
  }

  Future<void> dispose() async {
    await drive.dispose();
    await store.close();
    await directory.delete(recursive: true);
  }
}

Future<Map<String, Object?>> _contents(LocalDatabase db) async {
  final tables = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT GLOB 'sqlite_*' ORDER BY name",
      )
      .get();
  return {
    for (final t in tables)
      t.read<String>('name'): [
        for (final r
            in await db
                .customSelect(
                  'SELECT * FROM "${t.read<String>('name')}" ORDER BY rowid',
                )
                .get())
          r.data,
      ],
  };
}

Future<void> _usable(
  _Installation installation,
  Map<String, Object?> expected,
) async {
  await installation.restart();
  final db = await installation.store.open();
  expect(await _contents(db), expected);
  expect(
    (await db.customSelect('PRAGMA integrity_check').getSingle())
        .data
        .values
        .single,
    'ok',
  );
  expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(
    () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning,
  );
  late _Drive remote;
  late _Installation windows, android;
  late Map<String, Object?> original;
  Future<_Installation> create(String name) async {
    final directory = await Directory.systemTemp.createTemp('drive-$name-');
    final provider = _Provider();
    final drive = DriveAccessInstallation(
      provider: provider,
      credentials: provider,
      client: remote.client(),
      now: () => DateTime.utc(2026, 10, 2),
    );
    await drive.access.restoreLocalSession();
    return _Installation(
      directory,
      LocalDatabaseStore(supportDirectory: () async => directory),
      drive,
    );
  }

  setUp(() async {
    remote = _Drive();
    windows = await create('windows');
    android = await create('android');
    await seedRecoveryReference(await windows.store.open());
    original = await _contents(await windows.store.open());
  });
  tearDown(() async {
    await windows.dispose();
    await android.dispose();
  });
  Future<void> sharedVersion() async {
    expect((await windows.upload()).status, DriveUploadStatus.uploaded);
    expect(
      (await android.download()).status,
      DriveDownloadApplicationStatus.downloaded,
    );
    await _usable(android, original);
  }

  test('caso I: dos instalaciones, cifras, divergencia, cancelar, aplicar y recuperar', () async {
    final first = await windows.upload();
    expect(first.status, DriveUploadStatus.uploaded);
    expect(first.remote!.version, '1');
    expect(first.remote!.modifiedTime, DateTime.utc(2026, 10, 2, 15));
    expect(
      (await android.download(
        review: (review) async {
          expect(review.accountId, 'account');
          expect(review.remote.version, first.remote!.version);
          expect(review.remote.modifiedTime, first.remote!.modifiedTime);
          return true;
        },
      )).status,
      DriveDownloadApplicationStatus.downloaded,
    );
    await _usable(android, original);
    final db = await android.store.open();
    final movements = SqliteMovementRepository(db);
    final wealth = SqliteWealthRepository(db);
    final january = await wealth.read(Month(2026, 1));
    expect(january.status, WealthSnapshotStatus.complete);
    expect(
      january.values
          .where((v) => v.account.liquidity == Liquidity.liquid)
          .fold<int>(0, (s, v) => s + v.amountCents),
      900000,
    );
    expect(
      (await wealth.read(Month(2026, 2))).status,
      WealthSnapshotStatus.absent,
    );
    final year = await movements.readYear(2026);
    expect(year, hasLength(10));
    expect(year.fold<int>(0, (s, r) => s + r.data.amountCents), 232965);
    expect(
      (await movements.readMonth(
        2026,
        1,
      )).fold<int>(0, (s, r) => s + r.data.amountCents),
      122975,
    );
    expect(
      (await db
              .customSelect(
                'SELECT COUNT(*) AS n, SUM(amount_cents) AS total FROM budgets',
              )
              .getSingle())
          .data,
      {'n': 48, 'total': 1320000},
    );
    await android.edit('Android sintético', -12345);
    final androidData = await _contents(db);
    final second = await android.upload();
    expect(second.status, DriveUploadStatus.uploaded);
    expect(second.remote!.id, first.remote!.id);
    expect(second.remote!.version, '2');
    await windows.edit('Windows sin publicar', -500);
    final local = await _contents(await windows.store.open());
    final starts = remote.starts;
    expect((await windows.upload()).status, DriveUploadStatus.divergence);
    expect(remote.starts, starts);
    expect(remote.file!['version'], '2');
    await _usable(windows, local);
    final media = remote.downloads;
    expect(
      (await windows.download(
        review: (review) async {
          expect(review.requiresConfirmation, isTrue);
          expect(review.remote.version, '2');
          return false;
        },
      )).status,
      DriveDownloadApplicationStatus.cancelled,
    );
    expect(remote.downloads, media);
    await _usable(windows, local);
    final applied = await windows.download();
    expect(applied.status, DriveDownloadApplicationStatus.downloaded);
    expect(applied.restore!.previousBackupId, isNotNull);
    await _usable(windows, androidData);
    expect((await windows.inspect()).knownRemoteVersion, '2');
    final restored = await createLocalRestorer(
      store: windows.store,
      supportDirectory: () async => windows.directory,
    ).restore(applied.restore!.previousBackupId!, confirmed: true);
    expect(restored.status, LocalRestoreStatus.restored);
    await _usable(windows, local);
    expect(
      (await windows.inspect()).localStatus,
      SyncLocalStatus.contrastRequired,
    );
    expect(remote.file!['version'], '2');
  });

  for (final fault in ['network', 'truncated', 'invalid', 'cancel']) {
    test(
      'descarga $fault conserva todas las tablas y permite reintento manual',
      () async {
        await sharedVersion();
        await android.edit('Pendiente local', -700);
        final local = await _contents(await android.store.open());
        final validBytes = List<int>.of(remote.revisions.last);
        final validFile = Map<String, dynamic>.of(remote.file!);
        remote.interruptDownload = fault == 'network';
        remote.truncateDownload = fault == 'truncated';
        if (fault == 'invalid') {
          remote.publish(
            utf8.encode('not a SQLite database'),
            driveAutofinanceCopyProperties,
          );
        }
        final cancellation = DriveTransferCancellation();
        final result = await android.download(
          cancellation: cancellation,
          progress: (p) {
            if (fault == 'cancel' &&
                p.phase == DriveTransferPhase.transferring) {
              cancellation.cancel();
            }
          },
        );
        expect(result.status, isNot(DriveDownloadApplicationStatus.downloaded));
        await _usable(android, local);
        remote.interruptDownload = false;
        remote.truncateDownload = false;
        remote.revisions[remote.revisions.length - 1] = validBytes;
        remote.file = validFile;
        expect(
          (await android.download()).status,
          DriveDownloadApplicationStatus.downloaded,
        );
        await _usable(android, original);
      },
    );
  }

  test(
    'subida interrumpida conserva remoto previo y bloquea repetición incierta',
    () async {
      await sharedVersion();
      await android.edit('Nuevo en Android', -300);
      final edited = await _contents(await android.store.open());
      final previous = List<int>.of(remote.revisions.last);
      remote.interruptUpload = true;
      expect(
        (await android.upload()).status,
        isNot(DriveUploadStatus.uploaded),
      );
      expect(remote.revisions.last, previous);
      await _usable(android, edited);
      remote.interruptUpload = false;
      // Un fallo en el último bloque puede haber llegado: consultar antes de repetir.
      expect(
        (await android.reconciliation.query()).status,
        DriveReconciliationStatus.indeterminate,
      );
      final starts = remote.starts;
      expect(
        (await android.upload()).status,
        DriveUploadStatus.reconciliationRequired,
      );
      expect(remote.starts, starts);
      // Una nueva versión observable resuelve el conflicto mediante descarga explícita.
      await windows.edit('Nueva versión Windows', -100);
      expect((await windows.upload()).status, DriveUploadStatus.uploaded);
      expect(
        await android.reconciliation.choose(DriveConflictChoice.downloadLatest),
        isTrue,
      );
      expect(
        (await android.download()).status,
        DriveDownloadApplicationStatus.downloaded,
      );
      await _usable(android, await _contents(await windows.store.open()));
    },
  );

  test(
    'acuse perdido tras publicar se reconoce tras reinicio sin reenviar',
    () async {
      await sharedVersion();
      await android.edit('Nuevo en Android', -300);
      remote.loseAck = true;
      expect(
        (await android.upload()).status,
        DriveUploadStatus.reconciliationRequired,
      );
      final commits = remote.commits;
      await android.restart();
      expect(
        (await android.reconciliation.query()).status,
        DriveReconciliationStatus.uploaded,
      );
      expect(remote.commits, commits);
      expect((await android.inspect()).pending, isNull);
      remote.loseAck = false;
      expect(
        (await windows.download()).status,
        DriveDownloadApplicationStatus.downloaded,
      );
      expect(
        await _contents(await windows.store.open()),
        await _contents(await android.store.open()),
      );
    },
  );

  test('edición durante subida conserva snapshot remoto y cambios locales pendientes', () async {
    await sharedVersion();
    final captured = await _contents(await android.store.open());
    remote.beforePublish = () => android.edit('Durante subida', -250);
    expect((await android.upload()).status, DriveUploadStatus.uploaded);
    remote.beforePublish = null;
    expect((await android.inspect()).localStatus, SyncLocalStatus.changed);
    expect(
      (await windows.download()).status,
      DriveDownloadApplicationStatus.downloaded,
    );
    await _usable(windows, captured);
    expect(await _contents(await android.store.open()), isNot(captured));
  });

  test('carrera aceptada: ambos gates pasan V1; última escritura sin condición gana', () async {
    await sharedVersion();
    await windows.edit('Escritor Windows', -100);
    await android.edit('Escritor Android', -200);
    final windowsData = await _contents(await windows.store.open());
    final androidData = await _contents(await android.store.open());
    final entered = Completer<void>(), release = Completer<void>();
    var arrivals = 0;
    remote.beforePublish = () async {
      if (++arrivals == 1) {
        entered.complete();
        await release.future.timeout(const Duration(seconds: 10));
      }
    };
    final first = windows.upload();
    await entered.future.timeout(const Duration(seconds: 10));
    final second = await android.upload();
    expect(second.status, DriveUploadStatus.uploaded);
    expect(second.remote!.version, '2');
    release.complete();
    final last = await first;
    expect(last.status, DriveUploadStatus.uploaded);
    expect(last.remote!.version, '3');
    expect(last.raceNotice, contains('simultáneas'));
    remote.beforePublish = null;
    expect(remote.revisions, hasLength(3));
    await _usable(windows, windowsData);
    await _usable(android, androidData);
    expect((await android.upload()).status, DriveUploadStatus.divergence);
    expect(
      (await android.download()).status,
      DriveDownloadApplicationStatus.downloaded,
    );
    await _usable(android, windowsData);
  });
}
