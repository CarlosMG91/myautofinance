import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myautofinance/app/drive_access_factory.dart';
import 'package:myautofinance/features/synchronization/data/android_drive_session_provider.dart';
import 'package:myautofinance/features/synchronization/data/android_drive_session_store.dart';
import 'package:myautofinance/features/synchronization/data/android_google_authorization.dart';
import 'package:myautofinance/features/synchronization/data/drive_metadata_credential.dart';
import 'package:myautofinance/features/synchronization/data/windows_drive_session_provider.dart';
import 'package:myautofinance/features/synchronization/data/windows_drive_session_store.dart';
import 'package:myautofinance/features/synchronization/data/windows_google_authorization.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';

// Solo proveedores externos/almacenes falsos. Se ejecutan los adaptadores OAuth,
// la sesión, la composición, HTTP y ambos localizadores de producción.
class AndroidStore implements AndroidDriveSessionStore {
  DriveSession? value;
  bool unreadable = false;
  @override
  Future<DriveSession?> read() async {
    if (unreadable) throw StateError('synthetic-storage');
    return value;
  }

  @override
  Future<void> write(DriveSession session) async => value = session;
  @override
  Future<void> clear() async => value = null;
}

class WindowsStore implements WindowsDriveSessionStore {
  WindowsDriveCredential? value;
  bool unreadable = false;
  @override
  Future<WindowsDriveCredential?> read() async {
    if (unreadable) throw StateError('synthetic-storage');
    return value;
  }

  @override
  Future<void> write(WindowsDriveCredential credential) async =>
      value = credential;
  @override
  Future<void> clear() async => value = null;
}

class AndroidAuthorization implements AndroidGoogleAuthorization {
  DriveAccessIssue? failure;
  bool revoked = false;
  final calls = <bool>[];
  @override
  Future<String> accessToken({
    required bool interactive,
    required bool selectAccount,
  }) async {
    calls.add(interactive);
    if (failure != null) throw DriveAccessFailure(failure!);
    if (revoked) {
      throw const DriveAccessFailure(DriveAccessIssue.credentialExpired);
    }
    return 'synthetic-android-token';
  }

  @override
  void forget() {}
}

class WindowsAuthorization implements WindowsGoogleAuthorization {
  DriveAccessIssue? failure;
  int calls = 0;
  @override
  Future<WindowsAuthorizationCode> authorize({
    required bool selectAccount,
    required bool requireConsent,
    String? loginHint,
  }) async {
    calls++;
    if (failure != null) throw DriveAccessFailure(failure!);
    return WindowsAuthorizationCode(
      'synthetic-code',
      'synthetic-verifier',
      Uri.parse('http://127.0.0.1:12345/'),
    );
  }

  @override
  void cancel() {}
}

class Remote {
  final files = <Map<String, Object>>[];
  final requests = <http.Request>[];
  bool offline = false, revoked = false;
  int? metadataStatus;
  String account = 'synthetic-account';
  String scope = driveFileScope;
  late final client = MockClient(_respond);

  Iterable<http.Request> get fileRequests =>
      requests.where((r) => r.url.path.startsWith('/drive/v3/files'));
  int get creations => fileRequests.where((r) => r.method == 'POST').length;
  Map<String, Object> folder(String id) => {
    'id': id,
    'name': 'Autofinance',
    'mimeType': driveFolderMimeType,
    'parents': ['synthetic-root'],
    'trashed': false,
    'appProperties': driveAutofinanceFolderProperties,
  };
  Map<String, Object> copy(String id) => {
    'id': id,
    'name': driveAutofinanceCopyName,
    'mimeType': 'application/octet-stream',
    'parents': ['synthetic-folder'],
    'trashed': false,
    'appProperties': driveAutofinanceCopyProperties,
    'modifiedTime': '2026-10-02T00:00:00Z',
    'version': '2',
  };

  Future<http.Response> _respond(http.Request request) async {
    requests.add(request);
    expect(request.followRedirects, false);
    expect(request.url.scheme, 'https');
    expect(request.url.queryParameters['alt'], isNull);
    if (offline) throw const SocketException('synthetic-network');
    final path = request.url.path;
    http.Response json(Object body, [int status = 200]) =>
        http.Response(jsonEncode(body), status);
    if (request.url.host == 'oauth2.googleapis.com') {
      if (path == '/tokeninfo') {
        return json({'scope': scope, 'expires_in': '3600'});
      }
      expect(path, '/token');
      expect(request.bodyFields.containsKey('client_secret'), false);
      if (revoked) return json({'error': 'invalid_grant'}, 400);
      return json({
        'access_token': 'synthetic-windows-token',
        'refresh_token': 'synthetic-refresh',
        'token_type': 'Bearer',
        'expires_in': 3600,
        'scope': scope,
      });
    }
    expect(request.url.host, 'www.googleapis.com');
    expect(
      request.headers['Authorization']?.startsWith('Bearer synthetic-'),
      true,
    );
    if (path == '/drive/v3/about') {
      return json({
        'user': {'permissionId': account},
      });
    }
    if (metadataStatus != null) return json({'error': {}}, metadataStatus!);
    if (path == '/drive/v3/files/root') {
      return json({'id': 'synthetic-root', 'mimeType': driveFolderMimeType});
    }
    if (request.method == 'POST') {
      expect(path, '/drive/v3/files');
      expect(
        request.headers['Content-Type'],
        'application/json; charset=utf-8',
      );
      expect(jsonDecode(request.body), {
        'name': 'Autofinance',
        'mimeType': driveFolderMimeType,
        'parents': ['root'],
        'appProperties': driveAutofinanceFolderProperties,
      });
      final created = folder('synthetic-folder');
      files.add(created);
      return json(created, 201);
    }
    expect(request.method, 'GET');
    if (path == '/drive/v3/files') {
      expect(request.url.queryParameters['spaces'], 'drive');
      final query = request.url.queryParameters['q']!;
      expect(query, contains('trashed=false'));
      expect(query, isNot(contains('name=')));
      final role = query.contains('databaseCopyV1')
          ? 'databaseCopyV1'
          : 'backupFolderV1';
      final matches = files
          .where((f) => (f['appProperties'] as Map)['autofinanceRole'] == role)
          .toList();
      // Segunda página: comprueba que ambas instalaciones completan la búsqueda.
      if (matches.length > 1 &&
          request.url.queryParameters['pageToken'] == null) {
        return json({
          'files': [matches.first],
          'nextPageToken': 'synthetic-next',
        });
      }
      return json({
        'files': request.url.queryParameters['pageToken'] == null
            ? matches
            : matches.skip(1).toList(),
      });
    }
    final matches = files.where(
      (f) => f['id'] == request.url.pathSegments.last,
    );
    return matches.isEmpty ? json({'error': {}}, 404) : json(matches.single);
  }
}

class Installation {
  Installation(this.android, this.remote);
  final bool android;
  final Remote remote;
  final androidStore = AndroidStore();
  final windowsStore = WindowsStore();
  final androidAuth = AndroidAuthorization();
  final windowsAuth = WindowsAuthorization();
  DateTime now = DateTime.utc(2026, 10, 2);
  late DriveMetadataCredentialSource credentials;

  DriveAccessInstallation compose() {
    final DriveSessionProvider provider;
    if (android) {
      final value = AndroidDriveSessionProvider(
        authorization: androidAuth,
        store: androidStore,
        client: remote.client,
        now: () => now,
      );
      provider = value;
      credentials = value;
    } else {
      final value = WindowsDriveSessionProvider(
        clientId: '123-synthetic.apps.googleusercontent.com',
        authorization: windowsAuth,
        store: windowsStore,
        client: remote.client,
        now: () => now,
      );
      provider = value;
      credentials = value;
    }
    final flow = DriveAccessInstallation(
      provider: provider,
      credentials: credentials,
      client: remote.client,
      now: () => now,
    );
    addTearDown(flow.dispose);
    return flow;
  }

  void failAuthorization(DriveAccessIssue issue) {
    androidAuth.failure = windowsAuth.failure = issue;
  }
}

Matcher accessFailure(DriveAccessIssue issue) =>
    throwsA(isA<DriveAccessFailure>().having((e) => e.issue, 'issue', issue));
Matcher metadataFailure(DriveMetadataIssue issue) =>
    throwsA(isA<DriveMetadataFailure>().having((e) => e.issue, 'issue', issue));

void main() {
  for (final android in [false, true]) {
    final platform = android ? 'Android' : 'Windows';
    group(platform, () {
      late Remote remote;
      late Installation installation;
      late DriveAccessInstallation flow;
      setUp(() {
        remote = Remote();
        installation = Installation(android, remote);
        flow = installation.compose();
        addTearDown(remote.client.close);
      });

      Future<void> connectAndCreate() async {
        expect(
          (await flow.access.requestAccess()).status,
          DriveAccessStatus.authorized,
        );
        expect(
          (await flow.folders.requestFolder()).status,
          DriveFolderStatus.created,
        );
      }

      test(
        '$platform → otro dispositivo: carpeta única, sin_copia y sesiones independientes',
        () async {
          expect(remote.requests, isEmpty);
          expect(
            (await flow.access.restoreLocalSession()).status,
            DriveAccessStatus.disconnected,
          );
          expect(remote.requests, isEmpty);
          expect((await flow.access.requestAccess()).session!.grantedScopes, {
            driveFileScope,
          });
          expect(remote.fileRequests, isEmpty);
          expect(
            (await flow.folders.findFolder()).status,
            DriveFolderStatus.notFound,
          );
          expect(remote.creations, 0);
          final created = await flow.folders.requestFolder();
          expect(created.status, DriveFolderStatus.created);
          final firstCopy = await flow.copies.findCopy();
          expect(firstCopy.status, DriveCopyStatus.noCopy);
          expect(firstCopy.copy, isNull);

          final otherInstallation = Installation(!android, remote);
          final other = otherInstallation.compose();
          expect(
            (await other.access.restoreLocalSession()).status,
            DriveAccessStatus.disconnected,
          );
          expect(
            (await other.access.requestAccess()).status,
            DriveAccessStatus.authorized,
          );
          final found = await other.folders.findFolder();
          expect(found.status, DriveFolderStatus.found);
          expect(found.folder!.id, created.folder!.id);
          expect(
            (await other.folders.requestFolder()).status,
            DriveFolderStatus.found,
          );
          expect(
            (await other.copies.findCopy()).status,
            DriveCopyStatus.noCopy,
          );
          expect(remote.creations, 1);
          expect(remote.files.single['mimeType'], driveFolderMimeType);

          final restarted = installation.compose();
          final before = remote.requests.length;
          expect(
            (await restarted.access.restoreLocalSession())
                .session!
                .folder!
                .folderId,
            created.folder!.id,
          );
          expect(remote.requests.length, before);
          if (android) {
            await expectLater(
              restarted.folders.findFolder(),
              metadataFailure(DriveMetadataIssue.credentialUnavailable),
            );
          }
          expect(
            (await restarted.access.renewAccess()).status,
            DriveAccessStatus.authorized,
          );
          expect(
            (await restarted.folders.findFolder()).folder!.id,
            created.folder!.id,
          );
          expect(
            (await restarted.copies.findCopy()).status,
            DriveCopyStatus.noCopy,
          );
          await restarted.access.disconnect();
          expect(
            (await other.folders.findFolder()).folder!.id,
            created.folder!.id,
          );
          expect(remote.files.length, 1);
          expect(remote.creations, 1);
        },
      );

      for (final issue in [
        DriveAccessIssue.permissionDenied,
        DriveAccessIssue.cancelled,
        DriveAccessIssue.clientConfigurationError,
      ]) {
        test('$platform: $issue no crea ni consulta archivos', () async {
          installation.failAuthorization(issue);
          expect((await flow.access.requestAccess()).issue, issue);
          await expectLater(
            flow.folders.requestFolder(),
            accessFailure(DriveAccessIssue.credentialExpired),
          );
          expect(
            (await flow.copies.findCopy()).status,
            DriveCopyStatus.inaccessible,
          );
          expect(remote.fileRequests, isEmpty);
        });
      }

      test(
        '$platform: credencial local, ligada a cuenta, sin OAuth/red implícitos',
        () async {
          await connectAndCreate();
          final count = remote.requests.length;
          final credential = await installation.credentials.readCredential(
            accountId: remote.account,
          );
          expect(credential.session.folder!.folderId, 'synthetic-folder');
          expect(
            credential.toString(),
            isNot(contains(credential.accessToken)),
          );
          await expectLater(
            installation.credentials.readCredential(accountId: 'other'),
            accessFailure(DriveAccessIssue.accountChangeRequired),
          );
          expect(remote.requests.length, count);
          installation.now = installation.now.add(const Duration(hours: 2));
          await expectLater(
            installation.credentials.readCredential(accountId: remote.account),
            accessFailure(DriveAccessIssue.credentialExpired),
          );
          expect(
            (await flow.copies.findCopy()).accessIssue,
            DriveAccessIssue.credentialExpired,
          );
          expect(remote.requests.length, count);
          await flow.access.disconnect();
          await expectLater(
            installation.credentials.readCredential(accountId: remote.account),
            accessFailure(DriveAccessIssue.credentialExpired),
          );
        },
      );

      test('$platform: red ausente durante OAuth no guarda sesión', () async {
        remote.offline = true;
        expect(
          (await flow.access.requestAccess()).issue,
          DriveAccessIssue.unavailable,
        );
        expect(installation.androidStore.value, isNull);
        expect(installation.windowsStore.value, isNull);
        expect(remote.fileRequests, isEmpty);
      });

      test(
        '$platform: un scope ampliado se rechaza antes de acceder a archivos',
        () async {
          remote.scope =
              '$driveFileScope https://www.googleapis.com/auth/drive';
          expect(
            (await flow.access.requestAccess()).issue,
            DriveAccessIssue.permissionDenied,
          );
          expect(installation.androidStore.value, isNull);
          expect(installation.windowsStore.value, isNull);
          expect(remote.fileRequests, isEmpty);
        },
      );

      test('$platform: almacén ilegible impide usar la credencial', () async {
        await connectAndCreate();
        installation.androidStore.unreadable =
            installation.windowsStore.unreadable = true;
        final count = remote.requests.length;
        final result = await flow.copies.findCopy();
        expect(result.status, DriveCopyStatus.inaccessible);
        expect(
          result.metadataFailure!.issue,
          DriveMetadataIssue.credentialUnavailable,
        );
        expect(remote.requests.length, count);
      });

      test(
        '$platform: revocación invalida credencial, conserva identidad/carpeta',
        () async {
          await connectAndCreate();
          remote.revoked = installation.androidAuth.revoked = true;
          final renewed = await flow.access.renewAccess();
          expect(renewed.issue, DriveAccessIssue.credentialExpired);
          expect(renewed.session, isNull);
          expect(renewed.account!.permissionId, remote.account);
          await expectLater(
            installation.credentials.readCredential(accountId: remote.account),
            accessFailure(DriveAccessIssue.credentialExpired),
          );
          final count = remote.requests.length;
          expect(
            (await flow.copies.findCopy()).status,
            DriveCopyStatus.inaccessible,
          );
          expect(remote.requests.length, count);
          final stored = android
              ? installation.androidStore.value!
              : installation.windowsStore.value!.session;
          expect(stored.folder!.folderId, 'synthetic-folder');
          if (!android) {
            expect(installation.windowsStore.value!.accessToken, isNull);
          }
        },
      );

      test(
        '$platform: pérdida de red no equivale a sin_copia y desconecta localmente',
        () async {
          await connectAndCreate();
          remote.offline = true;
          final copy = await flow.copies.findCopy();
          expect(copy.status, DriveCopyStatus.inaccessible);
          expect(
            copy.metadataFailure!.issue,
            DriveMetadataIssue.networkFailure,
          );
          await expectLater(
            flow.folders.requestFolder(),
            metadataFailure(DriveMetadataIssue.networkFailure),
          );
          expect(remote.creations, 1);
          expect(
            (await flow.access.renewAccess()).issue,
            DriveAccessIssue.unavailable,
          );
          final count = remote.requests.length;
          expect(
            (await flow.access.disconnect()).status,
            DriveAccessStatus.disconnected,
          );
          expect(remote.requests.length, count);
          expect(remote.files.length, 1);
        },
      );

      for (final (status, issue) in [
        (401, DriveMetadataIssue.credentialExpired),
        (403, DriveMetadataIssue.permissionDenied),
        (503, DriveMetadataIssue.serverUnavailable),
      ]) {
        test(
          '$platform: HTTP $status sin renovación, reintento ni falsa ausencia',
          () async {
            await connectAndCreate();
            remote.metadataStatus = status;
            final count = remote.requests.length;
            final copy = await flow.copies.findCopy();
            expect(copy.status, DriveCopyStatus.inaccessible);
            expect(copy.metadataFailure!.issue, issue);
            expect(remote.requests.length, count + 1);
            expect(remote.creations, 1);
          },
        );
      }

      test(
        '$platform: duplicados de carpeta y copia, incluida segunda página, no se eligen',
        () async {
          await connectAndCreate();
          remote.files.add(remote.folder('synthetic-duplicate'));
          final folders = await flow.folders.requestFolder();
          expect(folders.status, DriveFolderStatus.ambiguous);
          expect(folders.folder, isNull);
          expect(folders.candidateIds.length, 2);
          expect(remote.creations, 1);
          remote.files.removeLast();
          // Solo metadatos sintéticos de archivos preexistentes; no se suben bytes.
          remote.files.addAll([remote.copy('copy-a'), remote.copy('copy-b')]);
          final copy = await flow.copies.findCopy();
          expect(copy.status, DriveCopyStatus.ambiguous);
          expect(copy.copy, isNull);
          expect(copy.candidates.length, 2);
          expect(remote.creations, 1);
        },
      );

      test(
        '$platform: otra cuenta no hereda carpeta ni token anterior',
        () async {
          await connectAndCreate();
          remote.account = 'synthetic-other-account';
          final changed = await flow.access.changeAccount();
          expect(changed.status, DriveAccessStatus.authorized);
          expect(changed.session!.folder, isNull);
          await expectLater(
            installation.credentials.readCredential(
              accountId: 'synthetic-account',
            ),
            accessFailure(DriveAccessIssue.accountChangeRequired),
          );
          expect(
            (await flow.copies.findCopy()).issue,
            DriveCopyIssue.folderNotSelected,
          );
          expect(remote.creations, 1);
        },
      );
    });
  }
}
