import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myautofinance/features/synchronization/data/windows_drive_session_provider.dart';
import 'package:myautofinance/features/synchronization/data/windows_drive_session_store.dart';
import 'package:myautofinance/features/synchronization/data/windows_google_authorization.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';

const clientId = '123-synthetic.apps.googleusercontent.com';
final start = DateTime.utc(2026, 10);
Matcher issue(DriveAccessIssue value) =>
    isA<DriveAccessFailure>().having((e) => e.issue, 'issue', value);

class Store implements WindowsDriveSessionStore {
  WindowsDriveCredential? value;
  bool failsRead = false, failsWrite = false, failsClear = false;
  int writes = 0;
  @override
  Future<WindowsDriveCredential?> read() async {
    if (failsRead) throw StateError('private-storage');
    return value;
  }

  @override
  Future<void> write(WindowsDriveCredential c) async {
    if (failsWrite) throw StateError('private-storage');
    writes++;
    value = c;
  }

  @override
  Future<void> clear() async {
    if (failsClear) throw StateError('private-storage');
    value = null;
  }
}

class Authorization implements WindowsGoogleAuthorization {
  int calls = 0;
  bool? selected, consent;
  DriveAccessIssue? failure;
  @override
  Future<WindowsAuthorizationCode> authorize({
    required bool selectAccount,
    required bool requireConsent,
    String? loginHint,
  }) async {
    calls++;
    selected = selectAccount;
    consent = requireConsent;
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

void main() {
  late Store store;
  late Authorization auth;
  late DateTime now;
  late WindowsDriveSessionProvider provider;
  late Map<String, dynamic> tokens;
  late int tokenStatus, aboutStatus;
  late String account;
  late List<http.Request> requests;
  late http.Client client;
  bool breakNetwork = false;
  Completer<http.Response>? pending;

  Future<DriveSession> authorize({bool select = false, String? expected}) =>
      provider.authorize(
        scopes: {driveFileScope},
        expectedAccountId: expected,
        selectAccount: select,
      );
  Future<void> seed() async {
    await authorize(select: true);
    await provider.rememberFolder(
      DriveFolderBinding(accountId: 'account-a', folderId: 'folder-a'),
    );
    requests.clear();
  }

  setUp(() {
    store = Store();
    auth = Authorization();
    now = start;
    tokens = {
      'access_token': 'synthetic-access',
      'refresh_token': 'synthetic-refresh',
      'token_type': 'Bearer',
      'expires_in': 3600,
      'scope': driveFileScope,
    };
    tokenStatus = 200;
    aboutStatus = 200;
    account = 'account-a';
    requests = [];
    breakNetwork = false;
    pending = null;
    client = MockClient((request) async {
      requests.add(request);
      expect(request.followRedirects, false);
      expect(request.url.queryParameters, isNot(contains('access_token')));
      if (breakNetwork) throw StateError('private-network-token');
      if (pending != null) return pending!.future;
      if (request.url.host == 'oauth2.googleapis.com') {
        expect(request.method, 'POST');
        expect(request.url.path, '/token');
        expect(request.bodyFields['client_id'], clientId);
        expect(request.bodyFields, isNot(contains('client_secret')));
        return http.Response(jsonEncode(tokens), tokenStatus);
      }
      expect(
        request.url.toString(),
        'https://www.googleapis.com/drive/v3/about?fields=user%28permissionId%2CemailAddress%29',
      );
      expect(request.headers['Authorization'], 'Bearer synthetic-access');
      return http.Response(
        jsonEncode({
          'user': {
            'permissionId': account,
            'emailAddress': 'synthetic@example.invalid',
          },
        }),
        aboutStatus,
      );
    });
    provider = WindowsDriveSessionProvider(
      clientId: clientId,
      authorization: auth,
      store: store,
      client: client,
      now: () => now,
      requestTimeout: const Duration(milliseconds: 100),
    );
  });
  tearDown(() => client.close());

  test('No acceso al construir/restaurar; código y verifier llegan solo al endpoint token', () async {
    expect(await provider.readLocalSession(), null);
    expect(requests, isEmpty);
    expect(auth.calls, 0);
    final session = await authorize(select: true);
    expect(session.account.permissionId, 'account-a');
    expect(session.validUntil, start.add(const Duration(seconds: 3540)));
    expect(session.grantedScopes, {driveFileScope});
    expect(requests.first.bodyFields['code_verifier'], 'synthetic-verifier');
    expect(requests.first.bodyFields['code'], 'synthetic-code');
    expect(
      requests.first.bodyFields['redirect_uri'],
      'http://127.0.0.1:12345/',
    );
    expect(auth.selected, true);
    expect(auth.consent, true);
    expect(store.value!.refreshToken, 'synthetic-refresh');
    expect(store.value.toString(), 'WindowsDriveCredential');
    expect(session.toString(), isNot(contains('synthetic')));
    requests.clear();
    expect(
      (await provider.readLocalSession())!.account.permissionId,
      'account-a',
    );
    expect(requests, isEmpty);
  });

  test('Segunda petición y reinicio reutilizan credencial sin navegador; verifican cuenta', () async {
    await seed();
    final restarted = WindowsDriveSessionProvider(
      clientId: clientId,
      authorization: auth,
      store: store,
      client: client,
      now: () => now,
    );
    final session = await restarted.authorize(
      scopes: {driveFileScope},
      expectedAccountId: 'account-a',
      selectAccount: false,
    );
    expect(auth.calls, 1);
    expect(requests.length, 1);
    expect(requests.single.method, 'GET');
    expect(session.folder!.folderId, 'folder-a');
  });

  test(
    'Token caducado renueva, conserva carpeta y rota refresh token sin UI',
    () async {
      await seed();
      now = now.add(const Duration(hours: 2));
      tokens['refresh_token'] = 'synthetic-rotated';
      final session = await authorize(expected: 'account-a');
      expect(auth.calls, 1);
      expect(requests.first.bodyFields, {
        'client_id': clientId,
        'grant_type': 'refresh_token',
        'refresh_token': 'synthetic-refresh',
      });
      expect(session.validUntil.isAfter(now), true);
      expect(session.folder!.folderId, 'folder-a');
      expect(store.value!.refreshToken, 'synthetic-rotated');
    },
  );

  test(
    'Renovación sin scope ni refresh repetidos conserva la concesión anterior',
    () async {
      await seed();
      tokens.remove('scope');
      tokens.remove('refresh_token');
      await provider.renew(accountId: 'account-a');
      expect(store.value!.refreshToken, 'synthetic-refresh');
      expect(store.value!.session.grantedScopes, {driveFileScope});
      expect(auth.calls, 1);
    },
  );

  test('401 de token en caché intenta renovar sin consentimiento', () async {
    await seed();
    aboutStatus = 401;
    await expectLater(
      authorize(),
      throwsA(issue(DriveAccessIssue.credentialExpired)),
    );
    expect(requests.map((r) => r.method), ['GET', 'POST', 'GET']);
    expect(store.value!.accessToken, null);
    expect(store.value!.refreshToken, null);
    expect(auth.calls, 1);
  });

  test('Revocación invalid_grant borra tokens de forma duradera y solo otra acción reautoriza', () async {
    await seed();
    tokens = {
      'error': 'invalid_grant',
      'error_description': 'private-description',
    };
    tokenStatus = 400;
    await expectLater(
      provider.renew(accountId: 'account-a'),
      throwsA(issue(DriveAccessIssue.credentialExpired)),
    );
    expect(store.value!.accessToken, null);
    expect(store.value!.refreshToken, null);
    expect(store.value!.session.validUntil.isBefore(now), true);
    expect(store.value!.session.folder!.folderId, 'folder-a');
    expect(store.value!.session.account.permissionId, 'account-a');
    expect(auth.calls, 1);
    tokens = {
      'access_token': 'synthetic-access',
      'refresh_token': 'new-refresh',
      'token_type': 'Bearer',
      'expires_in': 3600,
      'scope': driveFileScope,
    };
    tokenStatus = 200;
    await authorize(expected: 'account-a');
    expect(auth.calls, 2);
    expect(auth.consent, true);
    expect(store.value!.session.folder!.folderId, 'folder-a');
  });

  for (final failure in [
    DriveAccessIssue.cancelled,
    DriveAccessIssue.permissionDenied,
    DriveAccessIssue.authorizationTimeout,
    DriveAccessIssue.loopbackUnavailable,
  ]) {
    test(
      'Fallo interactivo $failure conserva registro y carpeta anteriores',
      () async {
        await seed();
        final previous = store.value;
        auth.failure = failure;
        await expectLater(authorize(select: true), throwsA(issue(failure)));
        expect(store.value, same(previous));
        expect(requests, isEmpty);
      },
    );
  }

  test('Cambio implícito rechazado antes de persistir; recordar otra carpeta también', () async {
    await seed();
    final previous = store.value;
    account = 'account-b';
    await expectLater(
      authorize(select: true),
      throwsA(issue(DriveAccessIssue.accountChangeRequired)),
    );
    expect(store.value, same(previous));
    await expectLater(
      provider.rememberFolder(
        DriveFolderBinding(accountId: 'account-b', folderId: 'folder-b'),
      ),
      throwsA(issue(DriveAccessIssue.accountChangeRequired)),
    );
    expect(store.value, same(previous));
  });

  test('Renovación con otra cuenta invalida acceso sin arrastrar carpeta a esa cuenta', () async {
    await seed();
    account = 'account-b';
    await expectLater(
      provider.renew(accountId: 'account-a'),
      throwsA(issue(DriveAccessIssue.credentialExpired)),
    );
    expect(store.value!.refreshToken, null);
    expect(store.value!.session.account.permissionId, 'account-a');
    expect(store.value!.session.folder!.accountId, 'account-a');
  });

  test('Reconexión sin refresh nuevo conserva el antiguo solo para la misma cuenta', () async {
    await seed();
    tokens.remove('refresh_token');
    await authorize(select: true);
    expect(store.value!.refreshToken, 'synthetic-refresh');
    expect(auth.consent, false);
  });

  for (final scope in [
    '',
    '$driveFileScope https://www.googleapis.com/auth/drive',
    'openid',
  ]) {
    test('Scope efectivo insuficiente/ampliado se rechaza: $scope', () async {
      tokens['scope'] = scope;
      await expectLater(
        authorize(select: true),
        throwsA(issue(DriveAccessIssue.permissionDenied)),
      );
      expect(store.value, null);
    });
  }

  for (final entry in <MapEntry<String, dynamic>>[
    const MapEntry('access_token', ''),
    const MapEntry('access_token', 1),
    const MapEntry('token_type', 'other'),
    const MapEntry('expires_in', '3600'),
    const MapEntry('scope', 3),
    const MapEntry('refresh_token', 3),
  ]) {
    test(
      'Respuesta malformada ${entry.key} se rechaza sin persistir',
      () async {
        tokens[entry.key] = entry.value;
        await expectLater(
          authorize(select: true),
          throwsA(issue(DriveAccessIssue.invalidSession)),
        );
        expect(store.value, null);
      },
    );
  }

  test('Caducidad y ausencia de credencial renovable se notifican', () async {
    tokens['expires_in'] = 60;
    await expectLater(
      authorize(select: true),
      throwsA(issue(DriveAccessIssue.credentialExpired)),
    );
    tokens['expires_in'] = 3600;
    tokens.remove('refresh_token');
    await expectLater(
      authorize(select: true),
      throwsA(issue(DriveAccessIssue.credentialExpired)),
    );
    expect(store.value, null);
  });

  test('PKCE rechazado invalid_grant y configuración invalid_client no guardan sesión', () async {
    for (final error in ['invalid_grant', 'invalid_client']) {
      tokens = {'error': error};
      tokenStatus = 400;
      await expectLater(
        authorize(select: true),
        throwsA(
          issue(
            error == 'invalid_grant'
                ? DriveAccessIssue.credentialExpired
                : DriveAccessIssue.clientConfigurationError,
          ),
        ),
      );
      expect(store.value, null);
    }
  });

  test(
    'Red/timeout no filtran errores ni destruyen la credencial anterior',
    () async {
      await seed();
      final previous = store.value;
      breakNetwork = true;
      await expectLater(
        provider.renew(accountId: 'account-a'),
        throwsA(issue(DriveAccessIssue.unavailable)),
      );
      expect(store.value, same(previous));
      breakNetwork = false;
      pending = Completer<http.Response>();
      await expectLater(
        provider.renew(accountId: 'account-a'),
        throwsA(issue(DriveAccessIssue.unavailable)),
      );
      expect(store.value, same(previous));
      pending!.complete(http.Response('{}', 500));
    },
  );

  test(
    'Fallos de lectura/escritura/borrado dan secureStorageFailure',
    () async {
      store.failsRead = true;
      await expectLater(
        provider.readLocalSession(),
        throwsA(issue(DriveAccessIssue.secureStorageFailure)),
      );
      store.failsRead = false;
      store.failsWrite = true;
      await expectLater(
        authorize(select: true),
        throwsA(issue(DriveAccessIssue.secureStorageFailure)),
      );
      store.failsWrite = false;
      await seed();
      store.failsClear = true;
      await expectLater(
        provider.clearLocalSession(),
        throwsA(issue(DriveAccessIssue.secureStorageFailure)),
      );
      store.failsClear = false;
      await provider.clearLocalSession();
      await provider.clearLocalSession();
      expect(store.value, null);
    },
  );

  test(
    'Desconexión es local, idempotente y no revoca permisos remotos',
    () async {
      await seed();
      breakNetwork = true;
      await provider.clearLocalSession();
      await provider.clearLocalSession();
      expect(requests, isEmpty);
      expect(store.value, null);
    },
  );

  test('Cliente cambiado, cuenta incorrecta y scopes solicitados no abren navegador', () async {
    await seed();
    await expectLater(
      authorize(expected: 'account-b'),
      throwsA(issue(DriveAccessIssue.accountChangeRequired)),
    );
    await expectLater(
      provider.authorize(
        scopes: {driveFileScope, 'openid'},
        expectedAccountId: null,
        selectAccount: true,
      ),
      throwsA(issue(DriveAccessIssue.invalidSession)),
    );
    final other = WindowsDriveSessionProvider(
      clientId: '456-other.apps.googleusercontent.com',
      authorization: auth,
      store: store,
      client: client,
    );
    await expectLater(
      other.readLocalSession(),
      throwsA(issue(DriveAccessIssue.clientConfigurationError)),
    );
    expect(auth.calls, 1);
    expect(requests, isEmpty);
  });

  test('Coordinador reutiliza sesión, cambia cuenta expresamente y bloquea tras borrado fallido', () async {
    final access = DriveAccessSession(provider: provider, now: () => now);
    expect((await access.requestAccess()).status, DriveAccessStatus.authorized);
    await access.rememberFolder(
      DriveFolderBinding(accountId: 'account-a', folderId: 'folder-a'),
    );
    expect((await access.requestAccess()).status, DriveAccessStatus.authorized);
    expect(auth.calls, 1);
    account = 'account-b';
    expect((await access.changeAccount()).account!.permissionId, 'account-b');
    expect(access.snapshot.session!.folder, null);
    store.failsClear = true;
    expect(
      (await access.disconnect()).issue,
      DriveAccessIssue.secureStorageFailure,
    );
    expect(
      (await access.requestAccess()).issue,
      DriveAccessIssue.secureStorageFailure,
    );
    store.failsClear = false;
    expect((await access.disconnect()).status, DriveAccessStatus.disconnected);
    await access.dispose();
  });

  test('Proveedor excluye peticiones concurrentes', () async {
    await seed();
    pending = Completer<http.Response>();
    final first = provider.renew(accountId: 'account-a');
    await expectLater(
      provider.readLocalSession(),
      throwsA(issue(DriveAccessIssue.operationInProgress)),
    );
    pending!.complete(http.Response('{}', 500));
    await expectLater(first, throwsA(issue(DriveAccessIssue.unavailable)));
  });
}
