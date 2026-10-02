import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:myautofinance/app/drive_access_factory.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';

/// Barrera del recorrido manual: solo identidad/OAuth y metadatos.
/// Ninguna petición de medios, archivo vacío, PATCH o DELETE llega a la red.
class _MetadataAuditClient extends http.BaseClient {
  _MetadataAuditClient({required this.allowFolderCreation});
  final bool allowFolderCreation;
  final _delegate = http.Client();
  int fileRequests = 0, folderCreations = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final uri = request.url;
    if (uri.scheme != 'https' || request.followRedirects) {
      throw StateError('Transporte no permitido en la prueba.');
    }
    final oauth =
        uri.host == 'oauth2.googleapis.com' &&
        ((uri.path == '/token' && request.method == 'POST') ||
            (uri.path == '/tokeninfo' && request.method == 'GET'));
    final about =
        uri.host == 'www.googleapis.com' &&
        uri.path == '/drive/v3/about' &&
        request.method == 'GET';
    final files =
        uri.host == 'www.googleapis.com' &&
        (uri.path == '/drive/v3/files' ||
            uri.path.startsWith('/drive/v3/files/')) &&
        uri.queryParameters['alt'] == null &&
        uri.queryParameters['fields'] != null;
    var folderPost = false;
    if (files &&
        uri.path == '/drive/v3/files' &&
        request.method == 'POST' &&
        request is http.Request) {
      final body = jsonDecode(request.body);
      folderPost =
          body is Map &&
          body.length == 4 &&
          body['name'] == 'Autofinance' &&
          body['mimeType'] == driveFolderMimeType &&
          body['parents'] is List &&
          (body['parents'] as List).length == 1 &&
          (body['parents'] as List).single == 'root' &&
          body['appProperties'] is Map &&
          (body['appProperties'] as Map).length == 1 &&
          body['appProperties']['autofinanceRole'] == 'backupFolderV1';
    }
    if (!oauth &&
        !about &&
        !(files && (request.method == 'GET' || folderPost))) {
      throw StateError('Operación fuera del contrato de metadatos.');
    }
    if (folderPost && (!allowFolderCreation || folderCreations != 0)) {
      throw StateError('Creación de carpeta no autorizada por el comando.');
    }
    if (files) fileRequests++;
    if (folderPost) folderCreations++;
    return _delegate.send(request);
  }

  @override
  void close() => _delegate.close();
}

/// Opt-in explícito en una instalación dedicada. No usa SQLite ni la app real.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const manual = bool.fromEnvironment('MANUAL_DRIVE_TEST');
  const action = String.fromEnvironment(
    'DRIVE_FOLDER_ACTION',
    defaultValue: 'reuse',
  );
  const expectedFingerprint = String.fromEnvironment(
    'DRIVE_EXPECTED_FOLDER_SHA256',
  );
  const androidClient = String.fromEnvironment(
    'GOOGLE_ANDROID_SERVER_CLIENT_ID',
  );
  const windowsClient = String.fromEnvironment('GOOGLE_WINDOWS_CLIENT_ID');

  testWidgets(
    'OAuth → carpeta visible → sin_copia, solo metadatos',
    (tester) async {
      expect({'create', 'reuse'}.contains(action), true);
      if (action == 'reuse') {
        expect(
          RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedFingerprint),
          true,
          reason: 'Reutilización requiere la huella privada del primer dispositivo.',
        );
      }
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Text(
              'Prueba técnica MA-TSK-049. Usa la misma cuenta tester en ambos dispositivos. '
              'El comando create permite crear solo la carpeta; reuse solo consulta. '
              'No se transfieren datos.',
            ),
          ),
        ),
      );
      final client = _MetadataAuditClient(
        allowFolderCreation: action == 'create',
      );
      final flow = Platform.isAndroid
          ? createAndroidDriveInstallation(
              serverClientId: androidClient,
              client: client,
            )
          : createWindowsDriveInstallation(
              clientId: windowsClient,
              client: client,
            );
      try {
        await flow.access.disconnect();
        expect(
          (await flow.access.restoreLocalSession()).status,
          DriveAccessStatus.disconnected,
        );
        expect(client.fileRequests, 0);
        final authorized = await flow.access.requestAccess();
        expect(
          authorized.status,
          DriveAccessStatus.authorized,
          reason: 'No se ha acreditado OAuth real de Autofinance.',
        );
        expect(authorized.session!.grantedScopes, {driveFileScope});
        expect(client.fileRequests, 0);
        final initial = await flow.folders.findFolder();
        expect(client.folderCreations, 0);
        final folder = action == 'create'
            ? await flow.folders.requestFolder()
            : initial;
        expect(
          {
            DriveFolderStatus.found,
            DriveFolderStatus.created,
          }.contains(folder.status),
          true,
          reason: 'No se ha acreditado carpeta única válida en Mi unidad.',
        );
        if (action == 'reuse') expect(folder.status, DriveFolderStatus.found);
        final fingerprint = sha256
            .convert(utf8.encode(folder.folder!.id))
            .toString();
        if (expectedFingerprint.isNotEmpty) {
          // Comparar como booleano evita imprimir identidades ante un fallo.
          expect(
            fingerprint == expectedFingerprint,
            true,
            reason: 'No se ha acreditado reutilización de la misma carpeta.',
          );
        }
        final copy = await flow.copies.findCopy();
        expect(copy.status, DriveCopyStatus.noCopy);
        expect(copy.copy, isNull);
        final stored = await flow.access.restoreLocalSession();
        expect(stored.session!.folder!.folderId == folder.folder!.id, true);
        expect(
          (await flow.access.renewAccess()).status,
          DriveAccessStatus.authorized,
        );
        expect(
          (action == 'create'
                  ? await flow.folders.requestFolder()
                  : await flow.folders.findFolder())
              .status,
          DriveFolderStatus.found,
        );
        expect((await flow.copies.findCopy()).status, DriveCopyStatus.noCopy);
        expect(
          client.folderCreations,
          action == 'create' && initial.status == DriveFolderStatus.notFound
              ? 1
              : 0,
        );
        binding.reportData = {
          'ticket': 'MA-TSK-049',
          'platform': Platform.isAndroid ? 'android' : 'windows',
          'folderAction': action,
          // Pseudónimo para comparar resultados privados; no añadir al repositorio.
          'folderFingerprint': fingerprint,
          'sameFolderChecked': expectedFingerprint.isNotEmpty,
          'copyStatus': 'sin_copia',
          'folderCreations': client.folderCreations,
          'fileRequests': client.fileRequests,
          'mediaTransfers': 0,
        };
        debugPrint(
          'MA-TSK-049: sin_copia; guardar en privado la huella de carpeta $fingerprint',
        );
      } finally {
        await flow.access.disconnect();
        await flow.dispose();
        client.close();
      }
    },
    skip: !manual || !(Platform.isAndroid || Platform.isWindows),
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
