import '../features/synchronization/data/manual_drive_reconciliation.dart';
import '../features/synchronization/drive_reconciliation.dart';
import '../features/synchronization/synchronization.dart';
import 'data/sqlite/local_database_store.dart';
import 'drive_access_factory.dart';
import 'drive_download_factory.dart';
import 'drive_upload_factory.dart';
import 'sync_state_factory.dart';

DriveConflictFlow createDriveConflictFlow({
  required DriveAccessInstallation drive,
  required LocalDatabaseStore store,
  SupportDirectory? supportDirectory,
}) => DriveConflictFlow(
  reconciliation: createDriveReconciliation(
    drive: drive,
    store: store,
    supportDirectory: supportDirectory,
  ),
  downloader: createDriveDownloader(
    drive: drive,
    store: store,
    supportDirectory: supportDirectory,
  ),
);

DriveReconciliation createDriveReconciliation({
  required DriveAccessInstallation drive,
  required LocalDatabaseStore store,
  SupportDirectory? supportDirectory,
}) => ManualDriveReconciliation(
  access: drive.access,
  copies: drive.copies,
  state: createInstallationSyncState(
    store: store,
    supportDirectory: supportDirectory,
  ),
);

/// Usar este coordinador desde «Subir copia» para resolver antes de repetir.
DriveUploader createReconcilingDriveUploader({
  required DriveAccessInstallation drive,
  required LocalDatabaseStore store,
  SupportDirectory? supportDirectory,
}) => ReconcilingDriveUploader(
  access: drive.access,
  state: createInstallationSyncState(
    store: store,
    supportDirectory: supportDirectory,
  ),
  uploader: createDriveUploader(
    drive: drive,
    store: store,
    supportDirectory: supportDirectory,
  ),
  reconciliation: createDriveReconciliation(
    drive: drive,
    store: store,
    supportDirectory: supportDirectory,
  ),
);
