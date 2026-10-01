import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:myautofinance/app/drive_access_factory.dart';
import 'package:myautofinance/features/synchronization/data/android_drive_session_store.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';

/// Ejecutar exclusivamente en instalación de prueba: limpia su sesión local.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const manual = bool.fromEnvironment('MANUAL_DRIVE_TEST');
  const serverClientId = String.fromEnvironment(
    'GOOGLE_ANDROID_SERVER_CLIENT_ID',
  );
  const scenario = String.fromEnvironment(
    'DRIVE_TEST_SCENARIO',
    defaultValue: 'authorize',
  );

  testWidgets('Keystore Android: registro atómico y borrado local', (
    tester,
  ) async {
    const store = KeystoreDriveSessionStore();
    await store.clear();
    final original = DriveSession(
      account: DriveAccount(permissionId: 'synthetic-account'),
      validUntil: DateTime.utc(2026, 10, 1),
      grantedScopes: const {driveFileScope},
    );
    try {
      await store.write(original);
      final restored = (await store.read())!;
      expect(
        restored.account.permissionId == original.account.permissionId,
        true,
      );
      final replacement = DriveSession(
        account: original.account,
        validUntil: original.validUntil,
        grantedScopes: original.grantedScopes,
        folder: DriveFolderBinding(
          accountId: original.account.permissionId,
          folderId: 'synthetic-folder',
        ),
      );
      await store.write(replacement);
      expect(
        (await store.read())!.folder!.folderId == replacement.folder!.folderId,
        true,
      );
    } finally {
      await store.clear();
    }
    await store.clear();
    expect(await store.read(), isNull);
  }, skip: !Platform.isAndroid || !manual);

  testWidgets('Autorización manual Android con cuenta tester registrada', (
    tester,
  ) async {
    expect(
      serverClientId.isNotEmpty,
      true,
      reason: 'Falta el cliente Web público del proyecto de prueba.',
    );
    expect(
      ['authorize', 'cancel', 'change', 'configuration'].contains(scenario),
      true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Text(
            'Prueba técnica Drive: $scenario. Usa exclusivamente cuentas tester. '
            'En cancel, cancela el segundo selector. En change, elige otra cuenta tester.',
          ),
        ),
      ),
    );
    final client = http.Client();
    final access = createAndroidDriveAccess(
      serverClientId: serverClientId,
      client: client,
    );
    var disposed = false;
    try {
      if (scenario == 'configuration') {
        final result = await access.requestAccess();
        // CredentialManager puede reportar canceled para firma/paquete erróneos.
        expect(
          {
            DriveAccessIssue.clientConfigurationError,
            DriveAccessIssue.cancelled,
          }.contains(result.issue),
          true,
        );
        expect(result.session, isNull);
        return;
      }
      final first = await access.requestAccess();
      expect(
        first.status,
        DriveAccessStatus.authorized,
        reason: 'No se ha acreditado autorización real.',
      );
      final account = first.account!;
      expect(first.session!.grantedScopes, {driveFileScope});
      expect(first.session!.folder, isNull);
      final restored = await access.restoreLocalSession();
      expect(restored.account!.permissionId == account.permissionId, true);
      final renewed = await access.renewAccess();
      expect(renewed.status, DriveAccessStatus.authorized);
      expect(renewed.account!.permissionId == account.permissionId, true);
      if (scenario == 'cancel') {
        // Nueva instancia sin cuenta en memoria; el registro se conserva.
        await access.dispose();
        disposed = true;
        final other = createAndroidDriveAccess(
          serverClientId: serverClientId,
          client: client,
        );
        try {
          final result = await other.requestAccess();
          expect(result.issue, DriveAccessIssue.cancelled);
          expect(result.account!.permissionId == account.permissionId, true);
          expect(
            (await other.restoreLocalSession()).account!.permissionId ==
                account.permissionId,
            true,
          );
        } finally {
          await other.disconnect();
          await other.dispose();
        }
      } else if (scenario == 'change') {
        final changed = await access.changeAccount();
        expect(changed.status, DriveAccessStatus.authorized);
        expect(changed.account!.permissionId != account.permissionId, true);
        expect(changed.session!.folder, isNull);
      } else {
        final reconnect = await access.requestAccess();
        expect(reconnect.status, DriveAccessStatus.authorized);
        expect(reconnect.account!.permissionId == account.permissionId, true);
      }
    } finally {
      if (disposed) {
        await const KeystoreDriveSessionStore().clear();
      } else {
        await access.disconnect();
      }
      await access.dispose();
      client.close();
    }
  }, skip: !Platform.isAndroid || !manual);
}
