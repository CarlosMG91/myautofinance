import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/local_sync_contrast.dart';
import 'backup_storage.dart';
import 'native_backup_persistence.dart';

final class StoredLocalSyncContrastReader implements LocalSyncContrastReader {
  StoredLocalSyncContrastReader({required this.supportDirectory});
  final Future<Directory> Function() supportDirectory;

  @override
  Future<LocalSyncContrast> read() async {
    final storage = BackupStorage(NativeBackupPersistence(), DateTime.now);
    final support = (await supportDirectory()).absolute.path;
    final root = p.join(support, 'sqlite');
    await storage.safe(support, root);
    final slots = await storage.loadSlots(root);
    final value = slots.latest;
    final restore = Directory(p.join(root, 'local-backups', 'restore'));
    await storage.safe(root, restore.path);
    var pending = false;
    if (await restore.exists()) {
      await for (final item in restore.list(
        recursive: true,
        followLinks: false,
      )) {
        await storage.safe(root, item.path);
        if (p.basename(item.path).startsWith('journal-')) pending = true;
      }
    }
    return LocalSyncContrast(
      restoreEpoch: value?['localRestoreEpoch'] as String?,
      required:
          pending ||
          slots.damaged.isNotEmpty ||
          value == null ||
          value['syncContrastRequired'] == true,
    );
  }
}
