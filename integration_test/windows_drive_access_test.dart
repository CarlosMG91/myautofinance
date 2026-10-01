import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:myautofinance/app/drive_access_factory.dart';
import 'package:myautofinance/features/synchronization/data/windows_drive_session_store.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';

/// Solo instalaciones dedicadas de prueba. No escribe ni transfiere copias.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const native = bool.fromEnvironment('WINDOWS_CREDENTIAL_TEST');
  const manual = bool.fromEnvironment('MANUAL_DRIVE_TEST');
  const clientId = String.fromEnvironment('GOOGLE_WINDOWS_CLIENT_ID');
  const scenario = String.fromEnvironment(
    'DRIVE_TEST_SCENARIO',
    defaultValue: 'authorize',
  );

  testWidgets('Credential Manager nativo: persistencia y borrado verificable', (
    tester,
  ) async {
    runApp(const MaterialApp(home: SizedBox.shrink()));
    const store = CredentialManagerDriveSessionStore();
    await store.clear();
    try {
      final credential = WindowsDriveCredential(
        clientId: '123-synthetic.apps.googleusercontent.com',
        accessToken: 'synthetic-access',
        refreshToken: 'synthetic-refresh',
        session: DriveSession(
          account: DriveAccount(permissionId: 'synthetic-account'),
          validUntil: DateTime.utc(2030),
          grantedScopes: {driveFileScope},
        ),
      );
      await store.write(credential);
      final restored = await const CredentialManagerDriveSessionStore().read();
      // Comparar sin imprimir tokens en mensajes de expectativas.
      expect(restored?.refreshToken == credential.refreshToken, true);
      expect(restored?.accessToken == credential.accessToken, true);
      expect(
        restored?.session.account.permissionId == 'synthetic-account',
        true,
      );
    } finally {
      await store.clear();
    }
    expect(await store.read(), null);
    await store.clear();
  }, skip: !Platform.isWindows || !native);

  testWidgets(
    'OAuth Windows manual: navegador, restauración y renovación',
    (tester) async {
      runApp(const MaterialApp(home: SizedBox.shrink()));
      final client = http.Client();
      final handle = createWindowsDriveAccess(
        clientId: clientId,
        client: client,
      );
      final access = handle.access;
      try {
        await access.disconnect();
        if (scenario == 'timeout') {
          // Dejar abierto el navegador sin responder durante tres minutos.
          expect(
            (await access.requestAccess()).issue,
            DriveAccessIssue.authorizationTimeout,
          );
        } else if (scenario == 'configuration') {
          expect(
            (await access.requestAccess()).issue,
            DriveAccessIssue.clientConfigurationError,
          );
        } else if (scenario == 'cancel') {
          final pending = access.requestAccess();
          await Future<void>.delayed(const Duration(seconds: 5));
          handle.cancelAuthorization();
          expect((await pending).issue, DriveAccessIssue.cancelled);
        } else {
          final first = await access.requestAccess();
          expect(first.status, DriveAccessStatus.authorized);
          expect(first.session?.grantedScopes, {driveFileScope});
          final accountId = first.account!.permissionId;
          final secondHandle = createWindowsDriveAccess(
            clientId: clientId,
            client: client,
          );
          final second = secondHandle.access;
          try {
            expect(
              (await second.restoreLocalSession()).status,
              DriveAccessStatus.authorized,
            );
            expect(
              (await second.requestAccess()).account?.permissionId == accountId,
              true,
            );
            expect(
              (await second.renewAccess()).status,
              DriveAccessStatus.authorized,
            );
          } finally {
            await second.dispose();
          }
        }
      } finally {
        await access.disconnect();
        await access.dispose();
        client.close();
      }
    },
    skip: !Platform.isWindows || !manual,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
