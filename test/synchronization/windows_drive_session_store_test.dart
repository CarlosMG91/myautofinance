import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/features/synchronization/data/windows_drive_session_store.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('autofinance/windows_drive');
  const store = CredentialManagerDriveSessionStore();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final failure = isA<DriveAccessFailure>().having(
    (e) => e.issue,
    'issue',
    DriveAccessIssue.secureStorageFailure,
  );
  String? raw;
  var fails = false;
  final methods = <String>[];
  final session = DriveSession(
    account: DriveAccount(
      permissionId: 'synthetic-account',
      emailAddress: 'test@example.invalid',
    ),
    validUntil: DateTime.utc(2026, 10, 1, 12),
    grantedScopes: {driveFileScope},
    folder: DriveFolderBinding(
      accountId: 'synthetic-account',
      folderId: 'synthetic-folder',
    ),
  );
  final credential = WindowsDriveCredential(
    clientId: '123-synthetic.apps.googleusercontent.com',
    session: session,
    accessToken: 'synthetic-access',
    refreshToken: 'synthetic-refresh',
  );

  setUp(() {
    raw = null;
    fails = false;
    methods.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (fails) throw PlatformException(code: 'private-platform-error');
      switch (call.method) {
        case 'read':
          return raw;
        case 'write':
          raw = call.arguments as String;
          return null;
        case 'clear':
          raw = null;
          return null;
      }
      throw MissingPluginException();
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('Registro único versionado contiene credenciales internas y metadatos juntos', () async {
    expect(await store.read(), null);
    await store.write(credential);
    final data = jsonDecode(raw!) as Map<String, dynamic>;
    expect(data['version'], 1);
    expect(data['clientId'], credential.clientId);
    expect(data['refreshToken'], 'synthetic-refresh');
    final restored = (await store.read())!;
    expect(restored.accessToken, 'synthetic-access');
    expect(restored.refreshToken, 'synthetic-refresh');
    expect(restored.session.account.permissionId, 'synthetic-account');
    expect(restored.session.folder!.folderId, 'synthetic-folder');
    expect(restored.session.validUntil, session.validUntil);
    expect(restored.session.grantedScopes, {driveFileScope});
    expect(methods, ['read', 'write', 'read']);
  });

  test('Credencial invalidada conserva identidad/carpeta sin tokens', () async {
    await store.write(
      WindowsDriveCredential(
        clientId: credential.clientId,
        session: DriveSession(
          account: session.account,
          validUntil: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          grantedScopes: {driveFileScope},
          folder: session.folder,
        ),
      ),
    );
    final restored = (await store.read())!;
    expect(restored.refreshToken, null);
    expect(restored.accessToken, null);
    expect(restored.session.folder!.accountId, 'synthetic-account');
  });

  for (final corrupt in ['{}', 'not-json', '{"version":2}']) {
    test('Registro ilegible $corrupt falla sin borrado silencioso', () async {
      raw = corrupt;
      await expectLater(store.read(), throwsA(failure));
      expect(raw, corrupt);
      expect(methods, ['read']);
    });
  }

  for (final entry in <MapEntry<String, dynamic>>[
    const MapEntry('scopes', ['openid']),
    const MapEntry('refreshToken', 1),
    const MapEntry('refreshToken', ''),
    const MapEntry('accountId', ''),
    const MapEntry('validUntil', 'bad-date'),
  ]) {
    test('Dato corrupto ${entry.key} se rechaza', () async {
      await store.write(credential);
      final data = jsonDecode(raw!) as Map<String, dynamic>;
      data[entry.key] = entry.value;
      raw = jsonEncode(data);
      await expectLater(store.read(), throwsA(failure));
    });
  }

  test(
    'No permite persistir scope ampliado ni carpeta de otra cuenta',
    () async {
      for (final invalid in [
        DriveSession(
          account: session.account,
          validUntil: session.validUntil,
          grantedScopes: {driveFileScope, 'openid'},
        ),
        DriveSession(
          account: session.account,
          validUntil: session.validUntil,
          grantedScopes: {driveFileScope},
          folder: DriveFolderBinding(
            accountId: 'other',
            folderId: 'other-folder',
          ),
        ),
      ]) {
        await expectLater(
          store.write(
            WindowsDriveCredential(
              clientId: credential.clientId,
              session: invalid,
            ),
          ),
          throwsA(failure),
        );
      }
      expect(methods, isEmpty);
    },
  );

  test(
    'Fallos nativos/missing plugin no filtran mensajes ni anuncian borrado',
    () async {
      fails = true;
      await expectLater(store.read(), throwsA(failure));
      await expectLater(store.write(credential), throwsA(failure));
      await expectLater(store.clear(), throwsA(failure));
      messenger.setMockMethodCallHandler(channel, null);
      await expectLater(store.read(), throwsA(failure));
    },
  );

  test('Borra credenciales y carpeta juntos, idempotente', () async {
    await store.write(credential);
    await store.clear();
    await store.clear();
    expect(await store.read(), null);
    expect(raw, null);
  });
}
