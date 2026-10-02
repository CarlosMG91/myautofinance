import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_restore_image_policy.dart';
import 'package:myautofinance/app/drive_access_factory.dart';
import 'package:myautofinance/app/drive_download_factory.dart';
import 'package:myautofinance/app/sync_state_factory.dart';
import 'package:myautofinance/features/synchronization/data/drive_metadata_credential.dart';
import 'package:myautofinance/features/synchronization/data/validated_drive_downloader.dart';
import 'package:myautofinance/features/synchronization/drive_download.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';
import 'package:sqlite3/sqlite3.dart';

class _Provider implements DriveSessionProvider, DriveMetadataCredentialSource {
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
  Future<void> clearLocalSession() async {}
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

class _Policy implements LocalRestoreImagePolicy {
  _Policy(this.after);
  final Future<void> Function(String) after;
  @override
  Future<LocalBackupImage> inspect(String path) async {
    final image = await const SqliteRestoreImagePolicy().inspect(path);
    await after(path);
    return image;
  }

  @override
  Future<void> migrate(String path) => throw UnimplementedError();
}

class _DownloadTransform implements DriveTransferClient {
  _DownloadTransform(this.inner, this.transform);
  final DriveTransferClient inner;
  final DriveDownloadCandidate Function(DriveDownloadCandidate) transform;
  @override
  Future<DriveDownloadCandidate> download({
    required String accountId,
    required String fileId,
    required int expectedBytes,
    required String temporaryDirectory,
    required DriveTransferCancellation cancellation,
    void Function(DriveTransferProgress)? onProgress,
  }) async => transform(
    await inner.download(
      accountId: accountId,
      fileId: fileId,
      expectedBytes: expectedBytes,
      temporaryDirectory: temporaryDirectory,
      cancellation: cancellation,
      onProgress: onProgress,
    ),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late LocalDatabaseStore store;
  late DriveAccessInstallation drive;
  late DriveDownloader downloader;
  late InstallationSyncState state;
  late _Remote remote;
  late List<int> original;
  late DriveSession? session;
  Future<DriveDownloadResult> download({
    DriveTransferCancellation? cancellation,
    Future<bool> Function(DriveDownloadReview)? review,
    void Function(DriveTransferProgress)? progress,
  }) => downloader.download(
    cancellation: cancellation ?? DriveTransferCancellation(),
    review: review ?? (_) async => true,
    onProgress: progress,
  );
  Future<void> cleanBaseline({String fileId = 'copy'}) async {
    final image = (await store.open()).readState();
    final operation = await state.beginUpload(
      accountId: 'account',
      fileId: fileId,
      capturedImage: await image,
    );
    await state.completeUpload(
      operationId: operation.id,
      remote: DriveFileMetadata(
        id: fileId,
        name: 'autofinance.sqlite',
        mimeType: 'application/octet-stream',
        parents: ['folder'],
        trashed: false,
        version: '7',
        modifiedTime: DateTime.utc(2026, 10, 2),
      ),
    );
  }

  Future<void> edit() async {
    final db = await store.open();
    await db.writeTransaction(
      () => db.customStatement(
        "INSERT INTO categories(id,name,is_income,created_at,updated_at) VALUES("
        "'11111111-1111-4111-8111-111111111111','Sintética',0,"
        "'2026-10-02T12:00:00.000Z','2026-10-02T12:00:00.000Z')",
      ),
    );
  }

  Future<void> unchanged() async {
    expect(identical(drive.access.snapshot.session, session), isTrue);
    expect(remote.requests.every((r) => r.method == 'GET'), isTrue);
    final snapshot = await store.createConsistentBackup();
    // Sin ediciones intencionadas en esta comprobación.
    expect(await File(snapshot.path).readAsBytes(), original);
    await File(snapshot.path).parent.delete(recursive: true);
  }

  Future<void> stagingEmpty() async {
    final root = Directory('${support.path}/sqlite/drive-downloads');
    if (await root.exists()) expect(await root.list().toList(), isEmpty);
  }

  setUp(() async {
    support = await Directory.systemTemp.createTemp('autofinance-download-');
    store = LocalDatabaseStore(supportDirectory: () async => support);
    final snapshot = await store.createConsistentBackup();
    original = await File(snapshot.path).readAsBytes();
    await File(snapshot.path).parent.delete(recursive: true);
    remote = _Remote()..bytes = List.of(original);
    final provider = _Provider();
    drive = DriveAccessInstallation(
      provider: provider,
      credentials: provider,
      client: remote.client,
      now: () => DateTime.utc(2026, 10, 2),
    );
    await drive.access.restoreLocalSession();
    session = drive.access.snapshot.session;
    state = createInstallationSyncState(
      store: store,
      supportDirectory: () async => support,
    );
    downloader = createDriveDownloader(
      drive: drive,
      store: store,
      supportDirectory: () async => support,
    );
  });
  tearDown(() async {
    await drive.dispose();
    remote.client.close();
    await store.close();
    await support.delete(recursive: true);
  });
  test(
    'construcción pasiva, revisión, validación y descarte sin instalar',
    () async {
      expect(remote.requests, isEmpty);
      final result = await download(
        review: (r) async {
          expect(remote.downloads, 0);
          expect(r.accountId, 'account');
          expect(r.remote.version, '7');
          expect(r.remote.modifiedTime, DateTime.utc(2026, 10, 2, 12));
          expect(r.requiresConfirmation, isTrue);
          return true;
        },
      );
      expect(result.status, DriveDownloadStatus.ready);
      expect(result.candidate!.sha256, sha256.convert(original).toString());
      expect(
        await File('${support.path}/drive-sync/state.json').exists(),
        isFalse,
      );
      await unchanged();
      expect(await downloader.discard(result.candidate!), isTrue);
      expect(await downloader.discard(result.candidate!), isFalse);
      await stagingEmpty();
    },
  );
  test(
    'sin cambios valida igualmente y conserva relación de sincronía',
    () async {
      await cleanBaseline();
      final result = await download(
        review: (r) async {
          expect(r.requiresConfirmation, isFalse);
          return true;
        },
      );
      expect(result.status, DriveDownloadStatus.ready);
      final sync = await state.inspect(accountId: 'account', fileId: 'copy');
      expect(sync.knownRemoteVersion, '7');
      expect(sync.pending, isNull);
      expect(sync.localStatus, SyncLocalStatus.clean);
      await unchanged();
      await downloader.discard(result.candidate!);
    },
  );
  test(
    'cambios locales requieren confirmación y cancelar no descarga',
    () async {
      await cleanBaseline();
      await edit();
      final before = await (await store.open()).readState();
      final result = await download(
        review: (r) async {
          expect(r.localStatus, SyncLocalStatus.changed);
          expect(r.requiresConfirmation, isTrue);
          return false;
        },
      );
      expect(result.status, DriveDownloadStatus.cancelled);
      expect(remote.downloads, 0);
      expect(
        (await (await store.open()).readState()).revision,
        before.revision,
      );
      await stagingEmpty();
    },
  );
  test('confirmación expresa permite descargar con cambios locales', () async {
    await cleanBaseline();
    await edit();
    final before = await (await store.open()).readState();
    final result = await download();
    expect(result.status, DriveDownloadStatus.ready);
    expect(result.candidate!.localState.revision, before.revision);
    expect((await (await store.open()).readState()).revision, before.revision);
    await downloader.discard(result.candidate!);
  });
  test(
    'cancelar mientras espera confirmación termina y conserva activa',
    () async {
      final pending = Completer<bool>();
      final entered = Completer<void>();
      final cancellation = DriveTransferCancellation();
      final result = download(
        cancellation: cancellation,
        review: (_) {
          entered.complete();
          return pending.future;
        },
      );
      await entered.future;
      cancellation.cancel();
      expect((await result).status, DriveDownloadStatus.cancelled);
      pending.complete(true);
      expect(remote.downloads, 0);
      await unchanged();
    },
  );
  test('cancelación previa evita incluso metadatos', () async {
    final result = await download(
      cancellation: DriveTransferCancellation()..cancel(),
    );
    expect(result.status, DriveDownloadStatus.cancelled);
    expect(remote.requests, isEmpty);
    await unchanged();
  });
  test(
    'cancelación en progreso elimina parcial y no anuncia complete',
    () async {
      final cancellation = DriveTransferCancellation();
      final phases = <DriveTransferPhase>[];
      final result = await download(
        cancellation: cancellation,
        progress: (p) {
          phases.add(p.phase);
          if (p.bytes > 0) cancellation.cancel();
        },
      );
      expect(result.status, DriveDownloadStatus.cancelled);
      expect(phases, isNot(contains(DriveTransferPhase.complete)));
      await stagingEmpty();
      await unchanged();
    },
  );
  for (final stage in ['metadata', 'media', 'recheck']) {
    test('fallo de red en $stage conserva activa y limpia staging', () async {
      if (stage == 'metadata') remote.offline = true;
      if (stage == 'media') remote.failMedia = true;
      if (stage == 'recheck') {
        remote.duringDownload = () async {
          remote.offline = true;
        };
      }
      final result = await download();
      expect(
        result.status,
        stage == 'media'
            ? DriveDownloadStatus.failed
            : DriveDownloadStatus.remoteUnavailable,
      );
      expect(result.candidate, isNull);
      await stagingEmpty();
      await unchanged();
    });
  }
  for (final mutation in ['version', 'duplicate']) {
    test('remoto cambia durante descarga: $mutation se rechaza', () async {
      remote.duringDownload = () async {
        if (mutation == 'version') {
          remote.version = '8';
        } else {
          remote.duplicate = true;
        }
      };
      expect((await download()).status, DriveDownloadStatus.remoteChanged);
      await stagingEmpty();
      await unchanged();
    });
  }
  test('tamaño incompleto rechazado por transporte', () async {
    remote.body = original.sublist(0, original.length - 1);
    final result = await download();
    expect(result.status, DriveDownloadStatus.failed);
    expect(result.transferFailure!.issue, DriveTransferIssue.invalidResponse);
    await stagingEmpty();
    await unchanged();
  });
  test('MD5 incorrecto se rechaza antes de SQLite', () async {
    remote.checksum = '0' * 32;
    expect((await download()).status, DriveDownloadStatus.hashMismatch);
    await stagingEmpty();
    await unchanged();
  });
  test('sin hash remoto se valida SQLite y se calcula SHA256 local', () async {
    remote.includeHash = false;
    final result = await download();
    expect(result.status, DriveDownloadStatus.ready);
    await unchanged();
    await downloader.discard(result.candidate!);
  });
  for (final invalid in ['corrupt', 'future', 'foreign']) {
    test('SQLite $invalid rechazado con motivo específico', () async {
      if (invalid == 'corrupt') {
        remote.bytes = List.filled(original.length, 0);
      } else {
        final file = File('${support.path}/invalid.sqlite');
        await file.writeAsBytes(original);
        final db = sqlite3.open(file.path);
        db.execute(
          invalid == 'future'
              ? 'PRAGMA user_version=999'
              : 'PRAGMA application_id=0',
        );
        db.close();
        remote.bytes = await file.readAsBytes();
      }
      final result = await download();
      expect(result.status, DriveDownloadStatus.invalidImage);
      expect(result.imageIssue, switch (invalid) {
        'future' => LocalRestoreCandidateIssue.futureSchema,
        'foreign' => LocalRestoreCandidateIssue.foreignFormat,
        _ => LocalRestoreCandidateIssue.integrityFailure,
      });
      await stagingEmpty();
      await unchanged();
    });
  }
  for (final invalid in ['size', 'hash', 'noCopy', 'duplicate']) {
    test('metadatos $invalid impiden transferencia', () async {
      if (invalid == 'size') remote.includeSize = false;
      if (invalid == 'hash') remote.checksum = 'invalid';
      if (invalid == 'noCopy') remote.noCopy = true;
      if (invalid == 'duplicate') remote.duplicate = true;
      final result = await download();
      expect(result.status, switch (invalid) {
        'noCopy' => DriveDownloadStatus.noCopy,
        'duplicate' => DriveDownloadStatus.remoteUnavailable,
        _ => DriveDownloadStatus.invalidMetadata,
      });
      expect(remote.downloads, 0);
      await unchanged();
    });
  }
  test('edición durante confirmación exige nueva revisión', () async {
    expect(
      (await download(
        review: (_) async {
          await edit();
          return true;
        },
      )).status,
      DriveDownloadStatus.localChanged,
    );
    expect(remote.downloads, 0);
    await stagingEmpty();
  });
  test('edición durante descarga rechaza candidata', () async {
    remote.duringDownload = edit;
    expect((await download()).status, DriveDownloadStatus.localChanged);
    await stagingEmpty();
  });
  test('operación pendiente impide empezar descarga', () async {
    await state.beginUpload(
      accountId: 'account',
      fileId: 'copy',
      capturedImage: await (await store.open()).readState(),
    );
    expect(
      (await download()).status,
      DriveDownloadStatus.reconciliationRequired,
    );
    expect(remote.downloads, 0);
    await unchanged();
  });
  test(
    'operaciones concurrentes se rechazan y cancelación libera coordinador',
    () async {
      final entered = Completer<void>(), decision = Completer<bool>();
      final first = download(
        review: (_) {
          entered.complete();
          return decision.future;
        },
      );
      await entered.future;
      expect((await download()).status, DriveDownloadStatus.busy);
      decision.complete(false);
      expect((await first).status, DriveDownloadStatus.cancelled);
      final retry = await download();
      expect(retry.status, DriveDownloadStatus.ready);
      await downloader.discard(retry.candidate!);
    },
  );
  test('cancelación durante validación limpia staging', () async {
    final cancellation = DriveTransferCancellation();
    downloader = ValidatedDriveDownloader(
      access: drive.access,
      copies: drive.copies,
      transfers: drive.transfers,
      readSyncState: (a, f) async => InstallationSyncSnapshot(
        accountId: a,
        fileId: f,
        localStatus: SyncLocalStatus.unknown,
      ),
      readDataset: () async => (await store.open()).readState(),
      readContrast: () async =>
          const LocalSyncContrast(restoreEpoch: null, required: false),
      policy: _Policy((_) async {
        cancellation.cancel();
      }),
      temporaryDirectory: () async =>
          Directory('${support.path}/sqlite/drive-downloads'),
    );
    expect(
      (await download(cancellation: cancellation)).status,
      DriveDownloadStatus.cancelled,
    );
    await stagingEmpty();
    await unchanged();
  });
  test('imagen mutada durante validación se rechaza por SHA256', () async {
    downloader = ValidatedDriveDownloader(
      access: drive.access,
      copies: drive.copies,
      transfers: drive.transfers,
      readSyncState: (a, f) async => InstallationSyncSnapshot(
        accountId: a,
        fileId: f,
        localStatus: SyncLocalStatus.unknown,
      ),
      readDataset: () async => (await store.open()).readState(),
      readContrast: () async =>
          const LocalSyncContrast(restoreEpoch: null, required: false),
      policy: _Policy((path) async {
        final file = File(path);
        final bytes = await file.readAsBytes();
        bytes[100] ^= 1;
        await file.writeAsBytes(bytes);
      }),
      temporaryDirectory: () async =>
          Directory('${support.path}/sqlite/drive-downloads'),
    );
    expect((await download()).status, DriveDownloadStatus.hashMismatch);
    await stagingEmpty();
    await unchanged();
  });
  test('fallo del almacenamiento de staging preserva activa', () async {
    await File('${support.path}/sqlite/drive-downloads')
        .writeAsString('occupied');
    expect((await download()).status, DriveDownloadStatus.failed);
    expect(remote.downloads, 0);
    await unchanged();
  });
  test('otra identidad permanece intacta al cancelar revisión', () async {
    await cleanBaseline(fileId: 'other-copy');
    final file = File('${support.path}/drive-sync/state.json');
    final before = await file.readAsBytes();
    final result = await download(
      review: (r) async {
        expect(r.localStatus, SyncLocalStatus.unknown);
        expect(r.requiresConfirmation, isTrue);
        return false;
      },
    );
    expect(result.status, DriveDownloadStatus.cancelled);
    expect(await file.readAsBytes(), before);
    await unchanged();
  });
  test(
    'pendiente de otra identidad no se invalida al preparar descarga',
    () async {
      await state.beginUpload(
        accountId: 'account',
        fileId: 'other-copy',
        capturedImage: await (await store.open()).readState(),
      );
      final file = File('${support.path}/drive-sync/state.json');
      final before = await file.readAsBytes();
      expect(
        (await download()).status,
        DriveDownloadStatus.reconciliationRequired,
      );
      expect(await file.readAsBytes(), before);
      expect(remote.downloads, 0);
      await unchanged();
    },
  );
  test('cambio de sesión durante confirmación evita transferencia', () async {
    expect(
      (await download(
        review: (_) async {
          await drive.access.disconnect();
          return true;
        },
      )).status,
      DriveDownloadStatus.remoteUnavailable,
    );
    expect(remote.downloads, 0);
    await stagingEmpty();
  });
  test('fallo de limpieza se comunica sin borrar una ruta sustituta', () async {
    String? stagingPath;
    downloader = ValidatedDriveDownloader(
      access: drive.access,
      copies: drive.copies,
      transfers: drive.transfers,
      readSyncState: (a, f) async => InstallationSyncSnapshot(
        accountId: a,
        fileId: f,
        localStatus: SyncLocalStatus.unknown,
      ),
      readDataset: () async => (await store.open()).readState(),
      readContrast: () async =>
          const LocalSyncContrast(restoreEpoch: null, required: false),
      policy: _Policy((path) async {
        final staging = File(path).parent.parent;
        stagingPath = staging.path;
        await staging.rename('${staging.path}.held');
        await File(staging.path).writeAsString('replacement');
      }),
      temporaryDirectory: () async =>
          Directory('${support.path}/sqlite/drive-downloads'),
    );
    final result = await download();
    expect(result.status, DriveDownloadStatus.failed);
    expect(result.cleanupPending, isTrue);
    expect(result.candidate, isNull);
    expect(await File(stagingPath!).readAsString(), 'replacement');
    await unchanged();
  });
  for (final alteration in ['length', 'outside']) {
    test(
      'resultado del transporte $alteration se rechaza de forma segura',
      () async {
        final outside = File('${support.path}/unrelated.sqlite');
        await outside.writeAsBytes(original);
        downloader = ValidatedDriveDownloader(
          access: drive.access,
          copies: drive.copies,
          transfers: _DownloadTransform(
            drive.transfers,
            (candidate) => DriveDownloadCandidate(
              path: alteration == 'outside' ? outside.path : candidate.path,
              bytes: candidate.bytes + 1,
            ),
          ),
          readSyncState: (a, f) async => InstallationSyncSnapshot(
            accountId: a,
            fileId: f,
            localStatus: SyncLocalStatus.unknown,
          ),
          readDataset: () async => (await store.open()).readState(),
          readContrast: () async =>
              const LocalSyncContrast(restoreEpoch: null, required: false),
          policy: const SqliteRestoreImagePolicy(),
          temporaryDirectory: () async =>
              Directory('${support.path}/sqlite/drive-downloads'),
        );
        expect(
          (await download()).status,
          alteration == 'length'
              ? DriveDownloadStatus.sizeMismatch
              : DriveDownloadStatus.failed,
        );
        expect(await outside.readAsBytes(), original);
        await stagingEmpty();
        await unchanged();
      },
    );
  }
}
