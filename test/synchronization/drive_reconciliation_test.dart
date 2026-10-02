import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/drive_access_factory.dart';
import 'package:myautofinance/app/drive_reconciliation_factory.dart';
import 'package:myautofinance/app/sync_state_factory.dart';
import 'package:myautofinance/features/synchronization/data/drive_metadata_credential.dart';
import 'package:myautofinance/features/synchronization/drive_reconciliation.dart';
import 'package:myautofinance/features/synchronization/drive_download.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';
import 'package:path/path.dart' as p;

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

/// HTTP falso: solo la red se sustituye; copia/SQLite/estado/gate son reales.
class _Remote {
  final requests = <http.Request>[];
  final revisions = <List<int>>[];
  Map<String, dynamic>? file;
  Map<String, dynamic>? initiating;
  final received = <int>[];
  bool loseAck = false, corruptAck = false, offline = false, duplicate = false;
  bool failChunk = false;
  int? commitStatus;
  Future<void> Function()? onStart, onCommit;
  late final client = MockClient((r) async {
    requests.add(r);
    if (offline) throw const SocketException('synthetic');
    http.Response json(Object body, [int status = 200]) =>
        http.Response(jsonEncode(body), status);
    final path = r.url.path;
    if (path == '/drive/v3/files/root') {
      return json({'id': 'root', 'mimeType': driveFolderMimeType});
    }
    if (path == '/drive/v3/files/folder') {
      return json({
        'id': 'folder',
        'name': 'Autofinance',
        'mimeType': driveFolderMimeType,
        'parents': ['root'],
        'trashed': false,
        'appProperties': driveAutofinanceFolderProperties,
      });
    }
    if (path == '/drive/v3/files/copy') {
      if (r.url.queryParameters['alt'] == 'media') {
        return http.Response.bytes(revisions.last, 200);
      }
      return file == null ? json({}, 404) : json(file!);
    }
    if (path == '/drive/v3/files') {
      return json({
        'files': [
          if (file != null) file,
          if (file != null && duplicate) {...file!, 'id': 'duplicate'},
        ],
      });
    }
    if (r.method == 'POST' || r.method == 'PATCH') {
      expect(path.startsWith('/upload/drive/v3/files'), isTrue);
      initiating = jsonDecode(r.body) as Map<String, dynamic>;
      received.clear();
      await onStart?.call();
      return http.Response(
        '',
        200,
        headers: {
          'location': 'https://www.googleapis.com/upload/drive/v3/files?upload_id=synthetic',
        },
      );
    }
    expect(r.method, 'PUT');
    expect(r.headers.containsKey('If-Match'), isFalse);
    final range = RegExp(r'bytes (\d+)-(\d+)/(\d+)')
        .firstMatch(r.headers['Content-Range']!)!;
    if (failChunk) throw const SocketException('synthetic');
    received.addAll(r.bodyBytes);
    if (int.parse(range[2]!) + 1 < int.parse(range[3]!)) {
      return http.Response(
        '',
        308,
        headers: {'range': 'bytes=0-${received.length - 1}'},
      );
    }
    final payload = List<int>.of(received);
    final properties = initiating!['appProperties'];
    await onCommit?.call();
    if (commitStatus != null) return json({'error': {}}, commitStatus!);
    file = {
      'id': 'copy',
      'name': driveAutofinanceCopyName,
      'mimeType': 'application/octet-stream',
      'parents': ['folder'],
      'trashed': false,
      'version': '${int.parse(file?['version'] as String? ?? '0') + 1}',
      'size': '${payload.length}',
      'modifiedTime': '2026-10-02T15:00:00.000Z',
      'md5Checksum': md5.convert(payload).toString(),
      'appProperties': properties,
    };
    revisions.add(payload);
    if (loseAck) throw const SocketException('synthetic-lost-ack');
    return json(corruptAck ? {...file!, 'md5Checksum': '0' * 32} : file!);
  });
  int get starts =>
      requests.where((r) => r.method == 'POST' || r.method == 'PATCH').length;
  int get puts => requests.where((r) => r.method == 'PUT').length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late LocalDatabaseStore store;
  late _Remote remote;
  late DriveAccessInstallation drive;
  late DriveUploader uploader;
  InstallationSyncState state() => createInstallationSyncState(
    store: store,
    supportDirectory: () async => support,
  );
  Future<InstallationSyncSnapshot> inspect() async => state().inspect(
    accountId: 'account',
    fileId: (await state().readFileId(accountId: 'account'))!,
  );
  Future<DriveUploadResult> upload({
    DriveTransferCancellation? cancel,
    void Function(DriveTransferProgress)? progress,
  }) => uploader.upload(
    cancellation: cancel ?? DriveTransferCancellation(),
    onProgress: progress,
  );
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

  setUp(() async {
    support = await Directory.systemTemp.createTemp('autofinance-upload-');
    store = LocalDatabaseStore(supportDirectory: () async => support);
    remote = _Remote();
    final provider = _Provider();
    drive = DriveAccessInstallation(
      provider: provider,
      credentials: provider,
      client: remote.client,
      now: () => DateTime.utc(2026, 10, 2),
    );
    await drive.access.restoreLocalSession();
    uploader = createReconcilingDriveUploader(
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

  DriveReconciliation resolver() => createDriveReconciliation(
    drive: drive,
    store: store,
    supportDirectory: () async => support,
  );

  for (final first in [true, false]) {
    test(
      'acuse perdido ${first ? "creación" : "actualización"}: reinicio y consulta sin duplicar',
      () async {
        if (!first) await upload();
        remote.loseAck = true;
        expect(
          (await upload()).status,
          DriveUploadStatus.reconciliationRequired,
        );
        final pending = (await inspect()).pending!;
        final count = remote.starts;
        await store.close();
        uploader = createReconcilingDriveUploader(
          drive: drive,
          store: store,
          supportDirectory: () async => support,
        );
        final result = await upload();
        expect(result.status, DriveUploadStatus.uploaded);
        expect(result.remote!.appProperties['uploadOperationId'], pending.id);
        expect(remote.starts, count);
        expect((await inspect()).pending, isNull);
        expect((await inspect()).knownRemoteVersion, result.remote!.version);
      },
    );
  }

  test('cancelar después de enviar: solo consulta y conserva ediciones posteriores', () async {
    final cancellation = DriveTransferCancellation();
    remote.onCommit = () async {
      cancellation.cancel();
      await edit();
    };
    expect(
      (await upload(cancel: cancellation)).status,
      DriveUploadStatus.reconciliationRequired,
    );
    expect(
      (await resolver().query()).status,
      DriveReconciliationStatus.uploaded,
    );
    expect((await inspect()).localStatus, SyncLocalStatus.changed);
    expect(remote.starts, 1);
  });

  test(
    'red desconocida exige nueva consulta; conservar no altera el pendiente',
    () async {
      remote.loseAck = true;
      await upload();
      final id = (await inspect()).pending!.id;
      remote.offline = true;
      final result = await resolver().query();
      expect(result.status, DriveReconciliationStatus.indeterminate);
      expect(result.requiresNewQuery, isTrue);
      expect(result.message, contains('Vuelve a consultar'));
      expect(await resolver().choose(DriveConflictChoice.keepLocal), isFalse);
      expect(
        await resolver().choose(DriveConflictChoice.downloadLatest),
        isFalse,
      );
      expect((await upload()).status, DriveUploadStatus.reconciliationRequired);
      expect((await inspect()).pending!.id, id);
      expect(remote.starts, 1);
      remote.offline = false;
      expect(
        (await resolver().query()).status,
        DriveReconciliationStatus.uploaded,
      );
    },
  );

  test(
    'misma versión sin marca no demuestra que una petición en vuelo falló',
    () async {
      await upload();
      remote.commitStatus = 503;
      await upload();
      expect((await inspect()).pending, isNotNull);
      expect(
        (await resolver().query()).status,
        DriveReconciliationStatus.indeterminate,
      );
      expect((await upload()).status, DriveUploadStatus.reconciliationRequired);
      expect(remote.starts, 2);
    },
  );

  test('hash incoherente, metadatos incompletos y candidatas múltiples conservan pendiente', () async {
    remote.loseAck = true;
    await upload();
    final checksum = remote.file!['md5Checksum'];
    remote.file!['md5Checksum'] = '0' * 32;
    expect(
      (await resolver().query()).status,
      DriveReconciliationStatus.indeterminate,
    );
    remote.file!['md5Checksum'] = checksum;
    remote.file!['version'] = '0';
    expect(
      (await resolver().query()).status,
      DriveReconciliationStatus.indeterminate,
    );
    remote.file!['version'] = '1';
    remote.duplicate = true;
    expect(
      (await resolver().query()).status,
      DriveReconciliationStatus.indeterminate,
    );
    expect((await inspect()).pending, isNotNull);
    expect(remote.starts, 1);
  });

  test('divergencia confirmada conserva ambas bases; descargar libera con contraste desconocido', () async {
    await upload();
    await edit();
    final local = await (await store.open()).readState();
    remote.loseAck = true;
    await upload();
    final properties = Map<String, dynamic>.from(
      remote.file!['appProperties'] as Map,
    );
    properties['uploadOperationId'] = 'otro-escritor';
    remote.file!['appProperties'] = properties;
    remote.file!['version'] = '3';
    final before = List<int>.of(remote.revisions.last);
    final result = await resolver().query();
    expect(result.status, DriveReconciliationStatus.conflict);
    expect(result.choices, containsAll(DriveConflictChoice.values));
    expect(result.message, contains('no se ha subido'));
    expect((await upload()).status, DriveUploadStatus.divergence);
    expect(await resolver().choose(DriveConflictChoice.keepLocal), isFalse);
    expect((await inspect()).pending, isNotNull);
    expect(await resolver().choose(DriveConflictChoice.downloadLatest), isTrue);
    expect((await inspect()).pending, isNull);
    expect((await inspect()).localStatus, SyncLocalStatus.contrastRequired);
    expect((await (await store.open()).readState()).revision, local.revision);
    expect(remote.revisions.last, before);
    expect(remote.starts, 2);
  });

  test('dos escritores pasan lectura previa: ambos publican y la última queda activa', () async {
    await upload();
    final secondRoot = await Directory.systemTemp.createTemp(
      'autofinance-writer-b-',
    );
    final secondStore = LocalDatabaseStore(
      supportDirectory: () async => secondRoot,
    );
    try {
      final path = File(
        p.join(secondRoot.path, 'sqlite', 'autofinance.sqlite'),
      );
      await path.parent.create(recursive: true);
      await path.writeAsBytes(remote.revisions.single);
      final secondState = createInstallationSyncState(
        store: secondStore,
        supportDirectory: () async => secondRoot,
      );
      final image = await (await secondStore.open()).readState();
      final op = await secondState.beginUpload(
        accountId: 'account',
        fileId: 'copy',
        capturedImage: image,
      );
      final metadata = await drive.copies.findCopy();
      await secondState.completeUpload(
        operationId: op.id,
        remote: metadata.copy!,
      );
      await edit();
      final second = createReconcilingDriveUploader(
        drive: drive,
        store: secondStore,
        supportDirectory: () async => secondRoot,
      );
      DriveUploadResult? secondResult;
      remote.onCommit = () async {
        remote.onCommit = null;
        // A ya comprobó versión 1. B todavía ve 1 y publica primero.
        secondResult = await second.upload(
          cancellation: DriveTransferCancellation(),
        );
      };
      final firstResult = await upload();
      expect(secondResult!.status, DriveUploadStatus.uploaded);
      expect(firstResult.status, DriveUploadStatus.uploaded);
      expect(secondResult!.remote!.version, '2');
      expect(firstResult.remote!.version, '3');
      expect(remote.revisions, hasLength(3));
      expect(remote.file!['appProperties'], firstResult.remote!.appProperties);
      final secondResolver = createDriveReconciliation(
        drive: drive,
        store: secondStore,
        supportDirectory: () async => secondRoot,
      );
      expect(
        (await secondResolver.query()).status,
        DriveReconciliationStatus.conflict,
      );
      final starts = remote.starts;
      expect(
        (await second.upload(cancellation: DriveTransferCancellation())).status,
        DriveUploadStatus.divergence,
      );
      expect(remote.starts, starts);
      expect(firstResult.raceNotice, contains('última'));
    } finally {
      await secondStore.close();
      await secondRoot.delete(recursive: true);
    }
  });

  test(
    'descargar usa revisión y staging validado sin aplicar la base',
    () async {
      await upload();
      await edit();
      final local = await (await store.open()).readState();
      remote.file!['version'] = '2';
      final flow = createDriveConflictFlow(
        drive: drive,
        store: store,
        supportDirectory: () async => support,
      );
      expect(flow.keepLocalLabel, 'Conservar datos locales');
      await flow.keepLocal();
      var reviews = 0;
      final result = await flow.downloadLatest(
        cancellation: DriveTransferCancellation(),
        review: (review) async {
          reviews++;
          expect(review.requiresConfirmation, isTrue);
          expect(review.remote.version, '2');
          return true;
        },
      );
      expect(result.status, DriveDownloadStatus.ready);
      expect(reviews, 1);
      expect((await (await store.open()).readState()).revision, local.revision);
      expect(remote.starts, 1);
      await flow.downloader.discard(result.candidate!);
    },
  );
}
