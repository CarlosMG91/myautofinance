import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/local_backup_factory.dart';
import 'package:myautofinance/features/synchronization/data/backup_json.dart';
import 'package:myautofinance/features/synchronization/data/native_backup_persistence.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class _FailingPersistence extends NativeBackupPersistence {
  @override
  Future<void> flushFile(String path) async {
    if (path.endsWith('autofinance.sqlite.part')) {
      throw const FileSystemException('Fallo sintético de persistencia');
    }
    await super.flushFile(path);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Copia privada nativa, reinicio, exclusión y fallo sin pérdida', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    final fixtures = await Directory(p.join(support.path, 'local-backup-tests'))
        .create(recursive: true);
    final fixture = await fixtures.createTemp('synthetic-');
    final store = LocalDatabaseStore(supportDirectory: () async => fixture);
    LocalBackupCreator creator({NativeBackupPersistence? persistence}) =>
        createLocalBackupCreator(
          store: store,
          supportDirectory: () async => fixture,
          persistence: persistence,
        );
    try {
      final db = await store.open();
      await db.customStatement('PRAGMA journal_mode=WAL');
      await db.customStatement('PRAGMA wal_autocheckpoint=0');
      await SqliteCategoryRepository(db).create(name: 'Categoría sintética');
      final state = await db.readState();
      final first = await creator().createManual();
      final directory = p.join(fixture.path, 'sqlite', first.relativeDirectory);
      final databaseFile = File(p.join(directory, 'autofinance.sqlite'));
      final original = await databaseFile.readAsBytes();
      final image = await const SqliteLocalBackupValidator().validate(
        databaseFile.path,
      );
      expect(image.state.datasetId, state.datasetId);
      expect(image.state.revision, state.revision);
      expect(image.schemaVersion, 6);
      expect((await Directory(directory).list().toList()), hasLength(2));
      final manifest = decodeBackupEnvelope(
        await File(p.join(directory, 'manifest.json')).readAsBytes(),
      );
      expect(manifest['origin'], 'manual');

      final lock = p.join(fixture.path, 'sqlite', '.local-backups.lock');
      await NativeBackupPersistence().exclusively(lock, () async {
        await expectLater(
          creator().createManual(),
          throwsA(
            isA<LocalBackupFailure>().having(
              (e) => e.code,
              'code',
              LocalBackupFailureCode.operationInProgress,
            ),
          ),
        );
      });
      await expectLater(
        creator(persistence: _FailingPersistence()).createManual(),
        throwsA(
          isA<LocalBackupFailure>().having(
            (e) => e.code,
            'code',
            LocalBackupFailureCode.storageFailure,
          ),
        ),
      );
      expect(await databaseFile.readAsBytes(), original);
      expect((await db.readState()).revision, state.revision);

      await store.close();
      final afterRestart = await creator().createPreRestore(
        '22222222-2222-4222-8222-222222222222',
      );
      expect(afterRestart.creationOrder, 3);
      expect(afterRestart.origin, LocalBackupOrigin.preRestore);
      expect(afterRestart.state.datasetId, state.datasetId);
      final base = p.join(fixture.path, 'sqlite', 'local-backups');
      final catalogs = <Map<String, dynamic>>[];
      for (final slot in ['a', 'b']) {
        catalogs.add(
          decodeBackupEnvelope(
            await File(p.join(base, 'catalog-$slot.json')).readAsBytes(),
          ),
        );
      }
      catalogs.sort(
        (a, b) =>
            backupCounter(b['generation'])
                .compareTo(backupCounter(a['generation'])),
      );
      expect(catalogs.first['entries'], hasLength(2));
      expect(await databaseFile.readAsBytes(), original);
    } finally {
      await store.close();
      expect(p.isWithin(fixtures.path, fixture.path), true);
      await fixture.delete(recursive: true);
    }
  });
}
