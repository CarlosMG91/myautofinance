import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/local_backup_factory.dart';
import 'package:myautofinance/features/synchronization/data/native_backup_persistence.dart';
import 'package:path/path.dart' as p;

class _CrashDisk extends NativeBackupPersistence {
  @override
  Future<void> move(
    String source,
    String target, {
    bool replace = false,
  }) async {
    await super.move(source, target, replace: replace);
    if (p.basename(target) == const String.fromEnvironment('CRASH_PHASE')) {
      // Exit termina el proceso del runner sin catch, rollback ni finally.
      stdout.writeln('durable-crash-point');
      await stdout.flush();
      exit(73);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('worker de interrupción real', () async {
    final support = Directory(const String.fromEnvironment('CRASH_SUPPORT'));
    final store = LocalDatabaseStore(supportDirectory: () async => support);
    await store.open();
    await createLocalRestorer(
      store: store,
      supportDirectory: () async => support,
      persistence: _CrashDisk(),
    ).restore(const String.fromEnvironment('CRASH_BACKUP'), confirmed: true);
    fail('El punto de interrupción debe terminar el proceso');
  });
}
