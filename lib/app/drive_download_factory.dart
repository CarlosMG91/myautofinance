import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../features/synchronization/data/validated_drive_downloader.dart';
import '../features/synchronization/data/stored_installation_sync_state.dart';
import '../features/synchronization/data/local_restore_service.dart';
import '../features/synchronization/data/safe_drive_download_application.dart';
import '../features/synchronization/drive_download.dart';
import 'data/sqlite/local_database_store.dart';
import 'data/sqlite/sqlite_restore_image_policy.dart';
import 'drive_access_factory.dart';
import 'local_backup_factory.dart';

/// Composición pasiva común a Windows/Android; no instala ni modifica sesión.
DriveDownloader createDriveDownloader({
  required DriveAccessInstallation drive,
  required LocalDatabaseStore store,
  SupportDirectory? supportDirectory,
}) {
  final directory = supportDirectory ?? getApplicationSupportDirectory;
  final contrast = createLocalSyncContrastReader(supportDirectory: directory);
  final state = StoredInstallationSyncState(
    supportDirectory: directory,
    contrastReader: contrast,
    readDataset: () async => (await store.open()).readState(),
  );
  return ValidatedDriveDownloader(
    access: drive.access,
    copies: drive.copies,
    transfers: drive.transfers,
    readSyncState: (account, file) =>
        state.inspectForDownload(accountId: account, fileId: file),
    readDataset: () async => (await store.open()).readState(),
    readContrast: contrast.read,
    policy: const SqliteRestoreImagePolicy(),
    temporaryDirectory: () async => Directory(
      p.join((await directory()).path, 'sqlite', 'drive-downloads'),
    ),
  );
}

/// Crear servicios no consulta Drive; el consumidor invoca el botón explícito.
DriveDownloadApplication createDriveDownloadApplication({
  required DriveAccessInstallation drive,
  required LocalDatabaseStore store,
  SupportDirectory? supportDirectory,
}) {
  final directory = supportDirectory ?? getApplicationSupportDirectory;
  final contrast = createLocalSyncContrastReader(supportDirectory: directory);
  final state = StoredInstallationSyncState(
    supportDirectory: directory,
    contrastReader: contrast,
    readDataset: () async => (await store.open()).readState(),
  );
  return SafeDriveDownloadApplication(
    downloader: createDriveDownloader(
      drive: drive,
      store: store,
      supportDirectory: directory,
    ),
    restorer: createLocalRestorer(
      store: store,
      supportDirectory: directory,
    ) as LocalRestoreService,
    syncState: state,
    access: drive.access,
    copies: drive.copies,
    readDataset: () async => (await store.open()).readState(),
  );
}
