// Only copied over lib/main.dart in an isolated checkout by the native runner.
// Never an entry point of the distributable application.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_wealth_repository.dart';
import 'package:myautofinance/app/import_factory.dart';
import 'package:myautofinance/app/local_backup_factory.dart';
import 'package:myautofinance/app/sync_state_factory.dart';
import 'package:myautofinance/features/importing/data/historical_csv_import_adapter.dart';
import 'package:myautofinance/features/importing/data/sha256_import_fingerprint.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/synchronization/data/android_drive_session_store.dart';
import 'package:myautofinance/features/synchronization/data/backup_storage.dart';
import 'package:myautofinance/features/synchronization/data/native_backup_persistence.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

const _probe = MethodChannel('autofinance/upgrade_probe');
const _port = 24300; // Replaced only inside the isolated fixture checkout.
const _token = 'UPGRADE_RUN_TOKEN';
const _session = KeystoreDriveSessionStore();

void require(bool condition, String message) {
  if (!condition) throw StateError(message); // Assertions run in release too.
}

Future<Map<String, dynamic>> exchange(String route, [Object? body]) async {
  return exchangeAt(
    Uri.parse('http://127.0.0.1:$_port/$route'),
    _token,
    body: body,
  );
}

Future<Map<String, dynamic>> exchangeAt(
  Uri uri,
  String token, {
  Object? body,
}) async {
  final client = HttpClient();
  try {
    final request = body == null
        ? await client.getUrl(uri)
        : await client.postUrl(uri);
    request.headers.set('X-Upgrade-Token', token);
    if (body != null) request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close();
    require(response.statusCode == 200, 'Controlled provider rejected request');
    return jsonDecode(await utf8.decoder.bind(response).join())
        as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(home: Scaffold(body: Text('Ensayo sintético EP-029'))),
  );
  try {
    require(
      kReleaseMode && const String.fromEnvironment('APP_ENV') == 'test',
      'Only a release test fixture is allowed',
    );
    final command = await exchange('command');
    final phase = command['phase'] as String;
    final support = await getApplicationSupportDirectory();
    final store = LocalDatabaseStore();
    // Verification must never create a missing financial database.
    final active = File(p.join(support.path, 'sqlite', 'autofinance.sqlite'));
    require(
      phase == 'seed' || await active.exists(),
      'Active database missing',
    );
    var db = await store.open();
    if (phase == 'seed') {
      require((await db.readState()).revision == 0, 'Not an empty fixture');
      await seed(db, command['csv'] as String);
      final backup = await createLocalBackupCreator(store: store)
          .createManual();
      await File(p.join(support.path, 'upgrade-backup-id'))
          .writeAsString(backup.backupId, flush: true);
      // Use the real restore service to leave genuine archived journals/epoch.
      final restored = await createLocalRestorer(store: store)
          .restore(backup.backupId, confirmed: true);
      require(restored.status == LocalRestoreStatus.restored, 'Restore failed');
      db = await store.open();
      final sync = createInstallationSyncState(store: store);
      final upload = await sync.beginUpload(
        accountId: 'synthetic-account',
        fileId: 'synthetic-file',
        capturedImage: await db.readState(),
      );
      await sync.completeUpload(
        operationId: upload.id,
        remote: DriveFileMetadata(
          id: 'synthetic-file',
          name: 'autofinance.sqlite',
          mimeType: 'application/vnd.sqlite3',
          parents: ['synthetic-folder'],
          trashed: false,
          version: '17',
        ),
      );
      await sync.beginUpload(
        accountId: 'synthetic-account',
        fileId: 'synthetic-file',
        capturedImage: await db.readState(),
      );
      require(await _session.read() == null, 'Session already exists');
      await _session.write(
        DriveSession(
          account: DriveAccount(permissionId: 'synthetic-account'),
          validUntil: DateTime.utc(2030),
          grantedScopes: const {driveFileScope},
          folder: DriveFolderBinding(
            accountId: 'synthetic-account',
            folderId: 'synthetic-folder',
          ),
        ),
      );
    } else if (phase == 'transaction-interrupt') {
      await db.run(() async {
        await SqliteCategoryRepository(db).create(name: 'UNCOMMITTED-243');
        await exchange('result', {'readyToKill': true, 'pid': pid});
        await Completer<void>().future; // Host kills process without finally.
      });
      throw StateError('Interrupted transaction unexpectedly returned');
    } else if (phase == 'restore-interrupt') {
      final id = await File(p.join(support.path, 'upgrade-backup-id'))
          .readAsString();
      await createLocalRestorer(
        store: store,
        persistence: _CrashDisk(),
      ).restore(id, confirmed: true);
      throw StateError('Interrupted restore unexpectedly returned');
    } else {
      require(phase == 'verify', 'Unknown phase');
    }
    final session = await _session.read();
    require(
      session?.account.permissionId == 'synthetic-account' &&
          session?.folder?.folderId == 'synthetic-folder',
      'Keystore session lost',
    );
    await store.close();
    final snapshot = await inspect(support);
    await exchange('result', {
      'ok': true,
      'snapshot': snapshot,
      'native': await _probe.invokeMapMethod<String, dynamic>('inspect'),
      'pid': pid,
      'realGoogleLogin': false,
    });
  } catch (error, stack) {
    await exchange('result', {
      'ok': false,
      'error': '$error',
      'stack': '$stack',
      'storageDiagnostic': await storageDiagnostic(),
    });
  }
}

// Read-only diagnosis; never bypass the production resolver or its path policy.
Future<Map<String, Object?>> storageDiagnostic() async {
  final support = await getApplicationSupportDirectory();
  final prefixes = <Map<String, String>>[];
  var path = p.rootPrefix(support.path);
  for (final segment in p.split(support.path).skip(1)) {
    path = p.join(path, segment);
    try {
      final type = await FileSystemEntity.type(path, followLinks: false);
      prefixes.add({
        'path': path,
        'type': '$type',
        'resolved': type == FileSystemEntityType.directory
            ? await Directory(path).resolveSymbolicLinks()
            : await File(path).resolveSymbolicLinks(),
      });
    } catch (error) {
      prefixes.add({'path': path, 'error': '$error'});
    }
  }
  Object? failure;
  try {
    final root = p.join(support.path, 'sqlite');
    await BackupStorage(
      NativeBackupPersistence(),
      DateTime.now,
    ).safe(root, p.join(root, 'local-backups', 'restore'));
  } catch (error, stack) {
    failure = {'error': '$error', 'stack': '$stack'};
  }
  return {'prefixes': prefixes, 'pathPolicyFailure': failure};
}

class _CrashDisk extends NativeBackupPersistence {
  @override
  Future<void> move(
    String source,
    String target, {
    bool replace = false,
  }) async {
    await super.move(source, target, replace: replace);
    if (p.basename(target) == 'autofinance.sqlite' &&
        p.basename(p.dirname(target)) == 'sqlite') {
      await exchange('result', {'readyToKill': true, 'pid': pid});
      await Completer<void>().future;
    }
  }
}

Future<void> seed(LocalDatabase db, String csv) async {
  final file = ImportFile.fromBytes(
    bytes: utf8.encode(csv),
    fingerprint: const Sha256ImportFingerprint(),
    source: ImportSource.historicalCsv,
    originalName: 'historico-sintetico.csv',
  );
  final interpretation = await const HistoricalCsvImportAdapter().interpret(
    file,
  );
  final session = ImportSession(file: file, interpretation: interpretation);
  require(session.isValid, 'Invalid reference CSV');
  final categories = <ImportCategoryReference, ImportNewCategory>{};
  for (final row in interpretation.rows) {
    final reference = switch (row) {
      InterpretedMovement() => row.category!,
      InterpretedBudget() => row.category,
    };
    for (var depth = 1; depth <= reference.path.length; depth++) {
      final prefix = ImportCategoryReference(
        reference.path.take(depth).toList(),
      );
      categories[prefix] = ImportNewCategory(
        name: prefix.path.last,
        isIncome: depth == 1 ? prefix.path.first == 'Ingresos' : null,
        parent: depth == 1
            ? null
            : ImportCategoryTarget.proposed(
                ImportCategoryReference(
                  reference.path.take(depth - 1).toList(),
                ),
              ),
      );
    }
  }
  final services = createImportServices(db);
  final review = await services.previewer.preview(
    session,
    bindings: ImportReferenceBindings(
      newCategories: categories,
      newAccounts: {
        ImportAccountReference.named('Cuenta principal'): ImportNewAccount(
          name: 'Cuenta principal',
          activeFrom: Month(2026, 1),
          liquidity: Liquidity.liquid,
        ),
      },
    ),
  );
  require(review.canRequestConfirmation, 'CSV review failed');
  final imported = await services.confirmer.confirm(
    ImportConfirmationRequest(review: review),
  );
  require(
    imported is ImportConfirmed &&
        imported.batch.movementCount == 10 &&
        imported.batch.budgetCount == 48,
    'CSV counts differ',
  );
  final repeat = await services.previewer.preview(session);
  require(
    await services.confirmer.confirm(ImportConfirmationRequest(review: repeat))
        is ImportAlreadyImported,
    'CSV idempotency failed',
  );
  final accounts = SqliteAccountRepository(db);
  final account = (await accounts.listForMonth(Month(2026, 1))).single;
  await accounts.changeLiquidity(account.id, Month(2026, 2), Liquidity.medium);
  final wealth = SqliteWealthRepository(db);
  await wealth.setValue(Month(2026, 1), account.id, 600000);
  await wealth.setValue(Month(2026, 2), account.id, 0);
  final movements = SqliteMovementRepository(db);
  final original = (await movements.readMonth(2026, 1)).first;
  await movements.edit(
    original.id,
    MovementInput(
      accountId: account.id,
      valueDate: original.data.valueDate,
      concept: 'Edición sintética 243',
      amountCents: original.data.amountCents,
      categoryId: original.data.categoryId,
      discretion: original.data.discretion,
    ),
  );
  await movements.create(
    MovementInput(
      accountId: account.id,
      valueDate: ValueDate(2026, 1, 19),
      concept: 'Sin clasificar sintético',
      amountCents: -243,
      discretion: 'Discrecional sintético',
    ),
  );
}

Future<Map<String, Object?>> inspect(Directory support) async {
  final db = sqlite3.open(
    p.join(support.path, 'sqlite', 'autofinance.sqlite'),
    mode: OpenMode.readOnly,
  );
  final tables = <String, Object?>{};
  try {
    require(
      db.select('PRAGMA integrity_check').single.values.single == 'ok',
      'SQLite integrity failed',
    );
    require(
      db.select('PRAGMA foreign_key_check').isEmpty,
      'Foreign keys failed',
    );
    for (final row in db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    )) {
      final name = row['name'] as String;
      final rows = db
          .select('SELECT * FROM "$name"')
          .map((r) => Map<String, Object?>.from(r))
          .toList();
      rows.sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
      tables[name] = rows;
    }
    require(
      db.select('SELECT count(*) AS n FROM movements').single['n'] == 11,
      'Movement count or database identity lost',
    );
    require(
      db.select('SELECT count(*) AS n FROM budgets').single['n'] == 48,
      'Budget count lost',
    );
    require(
      db
              .select(
                "SELECT count(*) AS n FROM categories WHERE name='UNCOMMITTED-243'",
              )
              .single['n'] ==
          0,
      'Interrupted transaction committed',
    );
    tables['schemaVersion'] = db
        .select('PRAGMA user_version')
        .single
        .values
        .single;
  } finally {
    db.close();
  }
  final files = <String, String>{};
  await for (final entity in support.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    final relative = p
        .relative(entity.path, from: support.path)
        .replaceAll('\\', '/');
    if (relative.startsWith('sqlite/local-backups/') ||
        relative.startsWith('drive-sync/') ||
        relative == 'upgrade-backup-id') {
      if (!relative.endsWith('.lock')) {
        files[relative] = sha256.convert(await entity.readAsBytes()).toString();
      }
    }
  }
  require(
    files.keys.any((f) => f.contains('journal-')),
    'No genuine restore journals',
  );
  require(files.containsKey('drive-sync/state.json'), 'No durable sync state');
  return {'tables': tables, 'files': files};
}
