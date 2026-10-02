import '../features/synchronization/synchronization.dart';
import '../features/synchronization/data/stored_installation_sync_state.dart';
import 'data/sqlite/local_database_store.dart';
import 'local_backup_factory.dart';

import 'package:path_provider/path_provider.dart';

/// Composición pasiva. El futuro flujo manual aporta cuenta y archivo de EP-005.
InstallationSyncState createInstallationSyncState({
  required LocalDatabaseStore store,
  SupportDirectory? supportDirectory,
}) => StoredInstallationSyncState(
  supportDirectory: supportDirectory ?? getApplicationSupportDirectory,
  readDataset: () async => (await store.open()).readState(),
  contrastReader: createLocalSyncContrastReader(
    supportDirectory: supportDirectory,
  ),
);
