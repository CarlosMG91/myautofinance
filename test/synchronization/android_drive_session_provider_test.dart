import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myautofinance/features/synchronization/data/android_drive_session_provider.dart';
import 'package:myautofinance/features/synchronization/data/android_drive_session_store.dart';
import 'package:myautofinance/features/synchronization/data/android_google_authorization.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';

final clock = DateTime.utc(2026, 10, 1);
DriveSession session({String id = 'synthetic-a', DriveFolderBinding? folder}) =>
    DriveSession(
      account: DriveAccount(permissionId: id),
      validUntil: clock.add(const Duration(minutes: 15)),
      grantedScopes: const {driveFileScope},
      folder: folder,
    );

final class Store implements AndroidDriveSessionStore {
  DriveSession? value;
  bool fail = false;
  int writes = 0;
  @override
  Future<DriveSession?> read() async => value;
  @override
  Future<void> write(DriveSession session) async {
    if (fail) throw Exception('SYNTHETIC_SECRET');
    writes++;
    value = session;
  }

  @override
  Future<void> clear() async {
    if (fail) throw Exception('SYNTHETIC_SECRET');
    value = null;
  }
}

final class Authorization implements AndroidGoogleAuthorization {
  Object? error;
  Completer<String>? pending;
  final calls = <({bool interactive, bool selectAccount})>[];
  int forgotten = 0;
  @override
  Future<String> accessToken({
    required bool interactive,
    required bool selectAccount,
  }) async {
    calls.add((interactive: interactive, selectAccount: selectAccount));
    if (error != null) throw error!;
    return pending == null ? 'synthetic-token' : await pending!.future;
  }

  @override
  void forget() {
    forgotten++;
  }
}

Matcher issue(DriveAccessIssue expected) => throwsA(
  isA<DriveAccessFailure>().having((e) => e.issue, 'issue', expected),
);

void main() {
  late Store store;
  late Authorization auth;
  late AndroidDriveSessionProvider provider;
  late http.Client client;
  late List<http.Request> requests;
  String remoteId = 'synthetic-a';
  String granted = driveFileScope;
  int tokenStatus = 200;
  int aboutStatus = 200;
  Object? lifetime = '3600';
  bool malformed = false;
  setUp(() {
    store = Store();
    auth = Authorization();
    requests = [];
    remoteId = 'synthetic-a';
    granted = driveFileScope;
    tokenStatus = aboutStatus = 200;
    lifetime = '3600';
    malformed = false;
    client = MockClient((request) async {
      requests.add(request);
      expect(request.followRedirects, false);
      expect(request.headers['Authorization'], 'Bearer synthetic-token');
      if (request.url.host == 'oauth2.googleapis.com') {
        expect(request.url.path, '/tokeninfo');
        return http.Response(
          jsonEncode({'scope': granted, 'expires_in': lifetime}),
          tokenStatus,
        );
      }
      expect(request.url.path, '/drive/v3/about');
      expect(request.url.queryParameters, {
        'fields': 'user(permissionId,emailAddress)',
      });
      return http.Response(
        malformed
            ? '{"user":{}}'
            : jsonEncode({
                'user': {'permissionId': remoteId},
              }),
        aboutStatus,
      );
    });
    provider = AndroidDriveSessionProvider(
      authorization: auth,
      store: store,
      client: client,
      now: () => clock,
    );
  });
  tearDown(() => client.close());

  Future<DriveSession> authorize({String? expected, bool select = true}) =>
      provider.authorize(
        scopes: const {driveFileScope},
        expectedAccountId: expected,
        selectAccount: select,
      );

  test('restaurar no llama al SDK ni a la red', () async {
    store.value = session();
    expect(await provider.readLocalSession(), same(store.value));
    expect(auth.calls, isEmpty);
    expect(requests, isEmpty);
  });
  test('acción explícita valida scopes, caducidad e identidad Drive antes de guardar', () async {
    final result = await authorize();
    expect(result.account.permissionId, 'synthetic-a');
    expect(result.account.emailAddress, isNull);
    expect(result.grantedScopes, {driveFileScope});
    expect(result.validUntil, clock.add(const Duration(seconds: 3540)));
    expect(auth.calls.single, (interactive: true, selectAccount: true));
    expect(store.value, same(result));
    expect(store.writes, 1);
    expect(requests.length, 2);
  });
  for (final failure in [
    DriveAccessIssue.cancelled,
    DriveAccessIssue.permissionDenied,
    DriveAccessIssue.clientConfigurationError,
  ]) {
    test('$failure conserva sesión y carpeta anteriores', () async {
      final previous = session(
        folder: DriveFolderBinding(
          accountId: 'synthetic-a',
          folderId: 'synthetic-folder',
        ),
      );
      store.value = previous;
      auth.error = DriveAccessFailure(failure);
      await expectLater(
        authorize(expected: 'synthetic-a', select: false),
        issue(failure),
      );
      expect(store.value, same(previous));
      expect(store.writes, 0);
    });
  }
  test(
    'reconexión conserva carpeta aunque no se haya restaurado antes',
    () async {
      final previous = session(
        folder: DriveFolderBinding(
          accountId: 'synthetic-a',
          folderId: 'synthetic-folder',
        ),
      );
      store.value = previous;
      final result = await authorize(select: false);
      expect(result.folder, same(previous.folder));
    },
  );
  test('otra cuenta sin cambio expreso no sustituye la anterior', () async {
    final previous = session();
    store.value = previous;
    remoteId = 'synthetic-b';
    await expectLater(
      authorize(),
      issue(DriveAccessIssue.accountChangeRequired),
    );
    expect(store.value, same(previous));
    expect(store.writes, 0);
  });
  for (final scopes in [
    '',
    '$driveFileScope https://www.googleapis.com/auth/drive',
    '$driveFileScope openid',
  ]) {
    test('rechaza concesión ausente o ampliada: $scopes', () async {
      store.value = session();
      final previous = store.value;
      granted = scopes;
      await expectLater(authorize(), issue(DriveAccessIssue.permissionDenied));
      expect(store.value, same(previous));
      expect(requests.length, 1);
    });
  }
  test('no solicita permisos ajenos al contrato', () async {
    await expectLater(
      provider.authorize(
        scopes: const {'openid'},
        expectedAccountId: null,
        selectAccount: true,
      ),
      issue(DriveAccessIssue.invalidSession),
    );
    expect(auth.calls, isEmpty);
    expect(requests, isEmpty);
  });
  for (final expiry in [null, 'invalid', '0', '60']) {
    test('rechaza vigencia no comprobable: $expiry', () async {
      lifetime = expiry;
      await expectLater(authorize(), issue(DriveAccessIssue.credentialExpired));
      expect(store.value, isNull);
    });
  }
  test('identidad incompleta no se persiste', () async {
    malformed = true;
    await expectLater(authorize(), issue(DriveAccessIssue.invalidSession));
    expect(store.writes, 0);
  });
  for (final entry in [
    (401, DriveAccessIssue.credentialExpired),
    (403, DriveAccessIssue.permissionDenied),
    (429, DriveAccessIssue.unavailable),
    (500, DriveAccessIssue.unavailable),
  ]) {
    test(
      'HTTP ${entry.$1} produce error cerrado y conserva almacenamiento',
      () async {
        aboutStatus = entry.$1;
        store.value = session();
        final previous = store.value;
        await expectLater(authorize(), issue(entry.$2));
        expect(store.value, same(previous));
      },
    );
  }
  test('errores crudos no llegan al contrato', () async {
    auth.error = Exception('SYNTHETIC_SECRET');
    try {
      await authorize();
      fail('Debe fallar');
    } on DriveAccessFailure catch (error) {
      expect(error.issue, DriveAccessIssue.unavailable);
      expect(error.toString(), isNot(contains('SYNTHETIC_SECRET')));
    }
  });
  test('fallo atómico de almacenamiento mantiene la sesión', () async {
    store.value = session();
    final previous = store.value;
    store.fail = true;
    await expectLater(
      authorize(),
      issue(DriveAccessIssue.secureStorageFailure),
    );
    expect(store.value, same(previous));
  });
  test('renovación expresa no solicita selección ni UI', () async {
    store.value = session();
    await provider.renew(accountId: 'synthetic-a');
    expect(auth.calls.single, (interactive: false, selectAccount: false));
  });
  for (final failure in [
    DriveAccessIssue.credentialExpired,
    DriveAccessIssue.permissionDenied,
    DriveAccessIssue.accountChangeRequired,
  ]) {
    test(
      'revocación o cuenta diferente invalida la sesión preservando referencia: $failure',
      () async {
        store.value = session(
          folder: DriveFolderBinding(
            accountId: 'synthetic-a',
            folderId: 'synthetic-folder',
          ),
        );
        auth.error = DriveAccessFailure(failure);
        await expectLater(
          provider.renew(accountId: 'synthetic-a'),
          issue(DriveAccessIssue.credentialExpired),
        );
        expect(store.value!.validUntil.isAfter(clock), false);
        expect(store.value!.folder!.folderId, 'synthetic-folder');
        expect(auth.forgotten, 1);
      },
    );
  }
  test('renovación sin sesión no llama al SDK', () async {
    await expectLater(
      provider.renew(accountId: 'synthetic-a'),
      issue(DriveAccessIssue.credentialExpired),
    );
    expect(auth.calls, isEmpty);
  });
  test(
    'desconexión local idempotente no llama a red ni revoca permisos',
    () async {
      store.value = session();
      await provider.clearLocalSession();
      await provider.clearLocalSession();
      expect(store.value, isNull);
      expect(auth.calls, isEmpty);
      expect(requests, isEmpty);
    },
  );
  test('carpeta requiere cuenta coincidente y no opera en Drive', () async {
    store.value = session();
    await expectLater(
      provider.rememberFolder(
        DriveFolderBinding(
          accountId: 'synthetic-b',
          folderId: 'synthetic-folder',
        ),
      ),
      issue(DriveAccessIssue.accountChangeRequired),
    );
    await provider.rememberFolder(
      DriveFolderBinding(
        accountId: 'synthetic-a',
        folderId: 'synthetic-folder',
      ),
    );
    expect(store.value!.folder!.folderId, 'synthetic-folder');
    expect(requests, isEmpty);
  });
  test('peticiones concurrentes no abren otro flujo', () async {
    auth.pending = Completer<String>();
    final first = authorize();
    await Future<void>.delayed(Duration.zero);
    await expectLater(authorize(), issue(DriveAccessIssue.operationInProgress));
    auth.pending!.complete('synthetic-token');
    await first;
    expect(auth.calls.length, 1);
  });
  test('contrato común: cambio de cuenta borra carpeta y cancelar deja desconectado', () async {
    final access = DriveAccessSession(provider: provider, now: () => clock);
    store.value = session(
      folder: DriveFolderBinding(
        accountId: 'synthetic-a',
        folderId: 'synthetic-folder',
      ),
    );
    await access.restoreLocalSession();
    auth.error = const DriveAccessFailure(DriveAccessIssue.cancelled);
    final result = await access.changeAccount();
    expect(result.status, DriveAccessStatus.disconnected);
    expect(store.value, isNull);
    expect(auth.calls.single.selectAccount, true);
    await access.dispose();
  });
  test('contrato común: cambio explícito acepta otra identidad y descarta carpeta previa', () async {
    final access = DriveAccessSession(provider: provider, now: () => clock);
    store.value = session();
    await access.restoreLocalSession();
    remoteId = 'synthetic-b';
    final result = await access.changeAccount();
    expect(result.account!.permissionId, 'synthetic-b');
    expect(result.session!.folder, isNull);
    await access.dispose();
  });
}
