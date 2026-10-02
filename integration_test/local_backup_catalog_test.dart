import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/local_backup_factory.dart';
import 'package:myautofinance/features/synchronization/data/native_backup_persistence.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class _DeletionFailure extends NativeBackupPersistence {
  @override
  Future<void> deleteFile(String path) async =>
      throw const FileSystemException('Borrado sintético bloqueado');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Catálogo privado, retención, baja pendiente y activa ilegible', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    final fixtures = await Directory(
      p.join(support.path, 'backup-catalog-tests'),
    ).create(recursive: true);
    final fixture = await fixtures.createTemp('synthetic-');
    final store = LocalDatabaseStore(supportDirectory: () async => fixture);
    final creator = createLocalBackupCreator(
      store: store,
      supportDirectory: () async => fixture,
    );
    LocalBackupCatalog catalog({NativeBackupPersistence? persistence}) =>
        createLocalBackupCatalog(
          supportDirectory: () async => fixture,
          persistence: persistence,
        );
    const operation = '22222222-2222-4222-8222-222222222222';
    try {
      final manual = await creator.createManual();
      final automatics = [
        for (var i = 0; i < 4; i++) await creator.createPreRestore(operation),
      ];
      expect((await catalog().read()).entries, hasLength(5));
      expect(
        (await catalog().maintainAfterRestore(
          restoreOperationId: operation,
          outcome: LocalRestoreRetentionOutcome.failed,
        )).deletedBackupIds,
        isEmpty,
      );
      // Exercises the retention handoff only: no database swap is performed here.
      final interrupted = await catalog(persistence: _DeletionFailure())
          .maintainAfterRestore(
            restoreOperationId: operation,
            outcome: LocalRestoreRetentionOutcome.confirmed,
          );
      expect(interrupted.deletedBackupIds, isEmpty);
      expect(
        interrupted.incidents.any(
          (i) => i.issue == LocalBackupCatalogIssue.deletionPending,
        ),
        true,
      );
      await store.close();
      final active = File(p.join(fixture.path, 'sqlite', 'autofinance.sqlite'));
      await active.writeAsString('Activa sintética ilegible', flush: true);
      final original = await active.readAsBytes();
      final restarted = catalog();
      expect((await restarted.retryPendingDeletions()).deletedBackupIds, [
        automatics.first.backupId,
      ]);
      final listing = await restarted.read();
      expect(
        listing.entries.map((e) => e.backupId),
        unorderedEquals([
          manual.backupId,
          ...automatics.skip(1).map((e) => e.backupId),
        ]),
      );
      for (final e in listing.entries) {
        await const SqliteLocalBackupValidator().validate(
          p.join(
            fixture.path,
            'sqlite',
            'local-backups',
            'backups',
            e.backupId,
            'autofinance.sqlite',
          ),
        );
      }
      expect(await active.readAsBytes(), original);
    } finally {
      await store.close();
      expect(p.isWithin(fixtures.path, fixture.path), true);
      await fixture.delete(recursive: true);
    }
  });
}
