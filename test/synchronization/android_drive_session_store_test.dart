import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/features/synchronization/data/android_drive_session_store.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('autofinance/drive_session');
  const store = KeystoreDriveSessionStore();
  String? stored;
  bool fail = false;
  setUp(() {
    stored = null;
    fail = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (fail) {
            throw PlatformException(
              code: 'private',
              message: 'SYNTHETIC_SECRET',
            );
          }
          switch (call.method) {
            case 'read':
              return stored;
            case 'write':
              stored = call.arguments as String;
              return null;
            case 'clear':
              stored = null;
              return null;
          }
          throw MissingPluginException();
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test(
    'registro único versionado: restauración de identidad y carpeta sin tokens',
    () async {
      final session = DriveSession(
        account: DriveAccount(permissionId: 'synthetic-id'),
        validUntil: DateTime.utc(2026, 10, 1),
        grantedScopes: const {driveFileScope},
        folder: DriveFolderBinding(
          accountId: 'synthetic-id',
          folderId: 'synthetic-folder',
        ),
      );
      await store.write(session);
      final data = jsonDecode(stored!) as Map<String, dynamic>;
      expect(
        data.keys,
        unorderedEquals([
          'version',
          'accountId',
          'emailAddress',
          'validUntil',
          'scopes',
          'folderId',
        ]),
      );
      final result = (await store.read())!;
      expect(result.account.permissionId, 'synthetic-id');
      expect(result.folder!.accountId, 'synthetic-id');
      expect(result.validUntil, session.validUntil);
      await store.clear();
      await store.clear();
      expect(await store.read(), isNull);
    },
  );
  for (final invalid in [
    'SYNTHETIC_SECRET',
    '{"version":99}',
    '{"version":1,"accountId":""}',
  ]) {
    test('registro inválido no se borra ni se imprime: $invalid', () async {
      stored = invalid;
      await expectLater(
        store.read(),
        throwsA(
          isA<DriveAccessFailure>().having(
            (e) => e.issue,
            'issue',
            DriveAccessIssue.secureStorageFailure,
          ),
        ),
      );
      expect(stored, invalid);
    });
  }
  test('fallos nativos no filtran el texto de PlatformException', () async {
    fail = true;
    try {
      await store.clear();
      failTest();
    } on DriveAccessFailure catch (error) {
      expect(error.toString(), isNot(contains('SYNTHETIC_SECRET')));
      expect(error.issue, DriveAccessIssue.secureStorageFailure);
    }
  });
}

Never failTest() => throw StateError('Debe fallar');
