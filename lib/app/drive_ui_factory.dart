import 'dart:io';

import 'package:http/http.dart' as http;

import '../features/synchronization/presentation/drive_controller.dart';
import '../features/synchronization/synchronization.dart';
import 'drive_access_factory.dart';
import 'drive_download_factory.dart';
import 'drive_reconciliation_factory.dart';
import 'data/sqlite/local_database_store.dart';
import 'sync_state_factory.dart';

/// IDs públicos OAuth, nunca secretos. La construcción no hace red.
DriveController createDriveUi({
  required LocalDatabaseStore store,
  required Future<void> Function() onRecoveryRequired,
}) {
  const windowsId = String.fromEnvironment('GOOGLE_WINDOWS_CLIENT_ID');
  const androidId = String.fromEnvironment('GOOGLE_ANDROID_SERVER_CLIENT_ID');
  final configured = Platform.isWindows
      ? windowsId.isNotEmpty
      : Platform.isAndroid && androidId.isNotEmpty;
  if (!configured) {
    return DriveController(
      uploader: null,
      downloader: null,
      readLocal: () async => const DriveViewSnapshot(),
      prepare: (_) async => null,
      unavailableReason: 'Drive no está configurado. Falta el identificador público OAuth de esta plataforma.',
    );
  }
  final client = http.Client();
  final drive = Platform.isWindows
      ? createWindowsDriveInstallation(clientId: windowsId, client: client)
      : createAndroidDriveInstallation(
          serverClientId: androidId,
          client: client,
        );
  final state = createInstallationSyncState(store: store);
  return DriveController(
    uploader: createReconcilingDriveUploader(drive: drive, store: store),
    downloader: createDriveDownloadApplication(drive: drive, store: store),
    cancelAuthorization: drive.cancelAuthorization,
    onRecoveryRequired: onRecoveryRequired,
    readLocal: () async {
      await drive.access.restoreLocalSession();
      final account = drive.access.snapshot.account;
      if (account == null) return const DriveViewSnapshot();
      final file = await state.readFileId(accountId: account.permissionId);
      final saved = file == null
          ? null
          : await state.inspect(accountId: account.permissionId, fileId: file);
      return DriveViewSnapshot(
        account: account.emailAddress ?? account.permissionId,
        version: saved?.observedRemoteVersion ?? saved?.knownRemoteVersion,
        referenceVersion: saved?.knownRemoteVersion,
        date: saved?.remoteModifiedTime,
        localStatus: saved?.localStatus ?? SyncLocalStatus.unknown,
      );
    },
    prepare: (upload) async {
      var access = drive.access.snapshot;
      if (access.status == DriveAccessStatus.credentialExpired) {
        access = await drive.access.renewAccess();
      }
      if (access.status != DriveAccessStatus.authorized) {
        access = await drive.access.requestAccess();
      }
      if (access.status != DriveAccessStatus.authorized) {
        return 'No se pudo autorizar la cuenta de Drive. Revisa la cuenta y los permisos.';
      }
      final folder = upload
          ? await drive.folders.requestFolder()
          : await drive.folders.findFolder();
      if (folder.status == DriveFolderStatus.notFound && !upload) {
        return 'No se encontró la carpeta Autofinance. Pulsa Subir copia para crear la primera copia.';
      }
      if (folder.status != DriveFolderStatus.found &&
          folder.status != DriveFolderStatus.created) {
        return 'No se pudo seleccionar una carpeta única y accesible de Autofinance. Revisa su ubicación y posibles duplicados en Drive.';
      }
      return null;
    },
  );
}
