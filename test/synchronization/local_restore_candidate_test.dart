import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_restore_image_policy.dart';
import 'package:myautofinance/app/local_backup_factory.dart';
import 'package:myautofinance/features/synchronization/data/backup_json.dart';
import 'package:myautofinance/features/synchronization/data/local_restore_candidate_service.dart';
import 'package:myautofinance/features/synchronization/data/native_backup_persistence.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

const _id = '22222222-2222-4222-8222-222222222222';
const _dataset = '11111111-1111-4111-8111-111111111111';
const _category = '33333333-3333-4333-8333-333333333333';
const _revision = 9007199254740993;
const _date = '2026-10-02T12:00:00.000Z';

class _Policy implements LocalRestoreImagePolicy {
  Future<void> Function(String)? beforeMigration;
  @override
  Future<LocalBackupImage> inspect(String path) =>
      const SqliteRestoreImagePolicy().inspect(path);
  @override
  Future<void> migrate(String stagingPath) async {
    await beforeMigration?.call(stagingPath);
    await const SqliteRestoreImagePolicy().migrate(stagingPath);
  }
}

class _FailPersistence extends NativeBackupPersistence {
  bool failMove = false;
  bool failFlush = false;
  @override
  Future<void> flushFile(String path) async {
    if (failFlush) throw const FileSystemException('synthetic');
    await super.flushFile(path);
  }

  @override
  Future<void> move(
    String source,
    String target, {
    bool replace = false,
  }) async {
    if (failMove && target.endsWith('autofinance.sqlite')) {
      throw const FileSystemException('synthetic');
    }
    await super.move(source, target, replace: replace);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late File active;
  late List<int> activeBytes;
  late File image;
  late File manifest;
  late File catalog;
  late Map<String, dynamic> descriptor;
  late Map<String, dynamic> catalogPayload;
  late LocalRestoreCandidatePreparer service;
  String root() => p.join(support.path, 'sqlite');
  String base() => p.join(root(), 'local-backups');

  void createImage(int version) {
    if (image.existsSync()) image.deleteSync();
    final db = sqlite3.open(image.path);
    try {
      for (final sql in [
        initialStateSchema,
        if (version >= 2) ...categorySchemaObjects,
        if (version >= 3) ...accountSchemaObjects,
        if (version >= 4) ...movementSchemaObjects,
        if (version >= 5) ...budgetSchemaObjects,
        if (version >= 6) ...wealthSchemaObjects,
      ]) {
        db.execute(sql);
      }
      if (version >= 7) {
        db.execute('DROP TRIGGER categories_budget_history');
        for (final sql in categoryReorganizationObjects) {
          db.execute(sql);
        }
      }
      db.execute('PRAGMA application_id=$localApplicationId');
      db.execute('PRAGMA user_version=$version');
      db.execute('INSERT INTO database_state VALUES(1,?,?)', [
        _dataset,
        _revision,
      ]);
      if (version >= 2) {
        db.execute(
          'INSERT INTO categories(id,name,is_income,created_at,updated_at) VALUES(?,?,0,?,?)',
          [_category, 'Comida sintética', _date, _date],
        );
      }
      if (version >= 5) {
        db.execute(
          'INSERT INTO budgets(id,month,category_id,amount_cents,created_at,updated_at) VALUES(?,?,?,?,?,?)',
          [
            '44444444-4444-4444-8444-444444444444',
            '2026-10-01',
            _category,
            -12345,
            _date,
            _date,
          ],
        );
      }
      validateExistingDatabase(db);
    } finally {
      db.close();
    }
  }

  void modify(void Function(Database) action) {
    final db = sqlite3.open(image.path);
    try {
      action(db);
    } finally {
      db.close();
    }
  }

  Future<void> writeMetadata({
    int version = localSchemaVersion,
    bool withCatalog = true,
  }) async {
    descriptor = {
      'kind': 'autofinance.localBackup',
      'formatVersion': 1,
      'backupId': _id,
      'datasetId': _dataset,
      'applicationId': localApplicationId,
      'schemaVersion': version,
      'revision': '$_revision',
      'createdAtUtc': _date,
      'creationOrder': '1',
      'origin': 'manual',
      'restoreOperationId': null,
      'databaseFile': 'autofinance.sqlite',
      'sizeBytes': '${await image.length()}',
      'databaseSha256': sha256.convert(await image.readAsBytes()).toString(),
      'initialValidation': {
        'state': 'valid',
        'checkedAtUtc': _date,
        'policySchemaVersion': version,
        'issue': null,
      },
    };
    await manifest.writeAsBytes(encodeBackupEnvelope(descriptor), flush: true);
    catalogPayload = {
      'kind': 'autofinance.localBackupCatalog',
      'formatVersion': 1,
      'generation': '1',
      'writtenAtUtc': _date,
      'nextCreationOrder': '2',
      'localRestoreEpoch': '55555555-5555-4555-8555-555555555555',
      'syncContrastRequired': true,
      'entries': [
        {
          'descriptor': descriptor,
          'manifestPayloadSha256': backupPayloadHash(descriptor),
          'relativeDirectory': 'local-backups/backups/$_id',
          'availability': 'present',
          'validation': descriptor['initialValidation'],
        },
      ],
    };
    if (withCatalog) {
      await catalog.writeAsBytes(
        encodeBackupEnvelope(catalogPayload),
        flush: true,
      );
    }
  }

  Future<LocalRestoreCandidateResult> preparePreservingOriginals() async {
    final bytes = await image.readAsBytes();
    final manifestBytes = await manifest.readAsBytes();
    final catalogBytes = await catalog.exists()
        ? await catalog.readAsBytes()
        : null;
    final result = await service.prepare(_id);
    expect(await image.readAsBytes(), bytes);
    expect(await manifest.readAsBytes(), manifestBytes);
    if (catalogBytes != null) expect(await catalog.readAsBytes(), catalogBytes);
    return result;
  }

  Future<void> reject(LocalRestoreCandidateIssue issue) async {
    final result = await preparePreservingOriginals();
    expect(result, isA<RejectedLocalRestoreCandidate>());
    final rejection = result as RejectedLocalRestoreCandidate;
    expect(rejection.issue, issue);
    expect(rejection.message, isNotEmpty);
    expect(rejection.message, isNot(contains(support.path)));
    expect(rejection.message, isNot(contains('SELECT')));
    if (await Directory(p.join(base(), 'restore')).exists()) {
      final files = await Directory(p.join(base(), 'restore'))
          .list(recursive: true)
          .toList();
      expect(
        files.whereType<File>().where(
          (f) => p.basename(f.path) == 'autofinance.sqlite',
        ),
        isEmpty,
      );
    }
  }

  setUp(() async {
    support = await Directory.systemTemp.createTemp(
      'restore-candidate-synthetic-',
    );
    final store = LocalDatabaseStore(supportDirectory: () async => support);
    await store.open();
    await store.close();
    active = File(p.join(root(), 'autofinance.sqlite'));
    activeBytes = await active.readAsBytes();
    image = File(p.join(base(), 'backups', _id, 'autofinance.sqlite'));
    await image.parent.create(recursive: true);
    manifest = File(p.join(image.parent.path, 'manifest.json'));
    catalog = File(p.join(base(), 'catalog-a.json'));
    createImage(localSchemaVersion);
    await writeMetadata();
    service = createLocalRestoreCandidatePreparer(
      supportDirectory: () async => support,
    );
  });
  tearDown(() async {
    expect(await active.readAsBytes(), activeBytes);
    expect(await File('${active.path}-wal').exists(), isFalse);
    expect(await File('${active.path}-shm').exists(), isFalse);
    await support.delete(recursive: true);
  });

  test(
    'válida: staging cerrado, hash y revisión exacta; originales intactos',
    () async {
      final result =
          await preparePreservingOriginals() as ReadyLocalRestoreCandidate;
      expect(result.migrated, isFalse);
      expect(result.image.state.revision, _revision);
      expect(result.image.state.datasetId, _dataset);
      expect(result.relativePath, startsWith('local-backups/restore/'));
      final staged = File(p.join(root(), result.relativePath));
      expect(await staged.readAsBytes(), await image.readAsBytes());
      expect(
        sha256.convert(await staged.readAsBytes()).toString(),
        result.sha256,
      );
      expect(await staged.length(), result.sizeBytes);
      final second = await service.prepare(_id) as ReadyLocalRestoreCandidate;
      expect(second.operationId, isNot(result.operationId));
      expect(await staged.exists(), isTrue);
    },
  );

  for (final version in [1, 2, 3, 4, 5, 6]) {
    test(
      'migración publicada v$version → vigente solo en staging, conserva datos y revisión',
      () async {
        createImage(version);
        await writeMetadata(version: version);
        final result =
            await preparePreservingOriginals() as ReadyLocalRestoreCandidate;
        expect(result.migrated, isTrue);
        expect(result.originalSchemaVersion, version);
        expect(result.image.schemaVersion, localSchemaVersion);
        expect(result.image.state.revision, _revision);
        final db = sqlite3.open(
          p.join(root(), result.relativePath),
          mode: OpenMode.readOnly,
        );
        try {
          validateExistingDatabase(db);
          if (version >= 2) {
            expect(
              db.select('SELECT name FROM categories').single['name'],
              'Comida sintética',
            );
          }
          if (version >= 5) {
            expect(
              db
                  .select('SELECT amount_cents FROM budgets')
                  .single['amount_cents'],
              -12345,
            );
          }
        } finally {
          db.close();
        }
      },
    );
  }

  test('activa corrupta: no se abre ni sustituye', () async {
    await active.writeAsBytes([1, 2, 3], flush: true);
    activeBytes = [1, 2, 3];
    expect(
      await preparePreservingOriginals(),
      isA<ReadyLocalRestoreCandidate>(),
    );
  });
  test('sin catálogo: manifiesto e imagen verificables', () async {
    await catalog.delete();
    expect(
      await preparePreservingOriginals(),
      isA<ReadyLocalRestoreCandidate>(),
    );
    expect(await catalog.exists(), isFalse);
  });
  test('truncada: tamaño distinto', () async {
    final bytes = await image.readAsBytes();
    await image.writeAsBytes(bytes.sublist(0, bytes.length ~/ 2));
    await reject(LocalRestoreCandidateIssue.sizeMismatch);
  });
  test('alterada con el mismo tamaño: hash distinto', () async {
    final bytes = await image.readAsBytes();
    bytes[100] ^= 1;
    await image.writeAsBytes(bytes);
    await reject(LocalRestoreCandidateIssue.hashMismatch);
  });
  test('hash actualizado en manifiesto pero distinto del catálogo', () async {
    final bytes = await image.readAsBytes();
    bytes[100] ^= 1;
    await image.writeAsBytes(bytes);
    descriptor['databaseSha256'] = sha256.convert(bytes).toString();
    await manifest.writeAsBytes(encodeBackupEnvelope(descriptor));
    await reject(LocalRestoreCandidateIssue.hashMismatch);
  });
  test('SQLite corrupta con hash actualizado', () async {
    await image.writeAsBytes(List.filled(4096, 42));
    await writeMetadata();
    await reject(LocalRestoreCandidateIssue.integrityFailure);
  });
  test('metadatos SQLite inválidos con hash correcto', () async {
    modify((db) {
      db.execute('PRAGMA ignore_check_constraints=ON');
      db.execute('UPDATE database_state SET revision=-1');
    });
    await writeMetadata();
    await reject(LocalRestoreCandidateIssue.invalidMetadata);
  });
  test('página B-tree dañada con cabecera y hash correctos', () async {
    late int offset;
    modify((db) {
      final pageSize =
          db.select('PRAGMA page_size').single.values.single as int;
      final page =
          db
                  .select(
                    "SELECT rootpage FROM sqlite_master WHERE name='database_state'",
                  )
                  .single['rootpage']
              as int;
      offset = (page - 1) * pageSize;
    });
    final bytes = await image.readAsBytes();
    bytes[offset] = 0;
    await image.writeAsBytes(bytes);
    await writeMetadata();
    await reject(LocalRestoreCandidateIssue.integrityFailure);
  });
  test('FK rota con hash correcto', () async {
    modify((db) {
      db.execute('PRAGMA foreign_keys=OFF');
      db.execute(
        'INSERT INTO import_rows(id,batch_id,source_ordinal,record_kind,created_at,updated_at) VALUES(?,?,2,?,?,?)',
        [_category, _dataset, 'movement', _date, _date],
      );
    });
    await writeMetadata();
    await reject(LocalRestoreCandidateIssue.foreignKeyFailure);
  });
  test('regla financiera rota con integridad y FK correctas', () async {
    modify((db) {
      db.execute(
        'INSERT INTO accounts(id,name,kind,active_from,created_at,updated_at) VALUES(?,?,?,?,?,?)',
        [
          _category,
          'Cuenta sin liquidez',
          'account',
          '2026-10-01',
          _date,
          _date,
        ],
      );
    });
    await writeMetadata();
    await reject(LocalRestoreCandidateIssue.financialRuleFailure);
  });
  test('producto ajeno', () async {
    modify((db) => db.execute('PRAGMA application_id=123'));
    await writeMetadata();
    await reject(LocalRestoreCandidateIssue.foreignFormat);
  });
  test('estructura ajena con AFNC', () async {
    modify((db) => db.execute('CREATE TABLE unexpected(value TEXT)'));
    await writeMetadata();
    await reject(LocalRestoreCandidateIssue.schemaMismatch);
  });
  test('esquema futuro', () async {
    modify((db) => db.execute('PRAGMA user_version=99'));
    await writeMetadata(version: 99);
    await reject(LocalRestoreCandidateIssue.futureSchema);
  });
  test('v0 sintética no publicada', () async {
    modify((db) => db.execute('PRAGMA user_version=0'));
    await writeMetadata(version: 1);
    await reject(LocalRestoreCandidateIssue.unsupportedSchema);
  });
  test('identidad/revisión del manifiesto no corresponde a SQLite', () async {
    modify((db) => db.execute('UPDATE database_state SET revision=12'));
    await writeMetadata();
    await reject(LocalRestoreCandidateIssue.invalidMetadata);
  });
  test('versión del manifiesto no corresponde a SQLite', () async {
    await writeMetadata(version: 5);
    await reject(LocalRestoreCandidateIssue.invalidMetadata);
  });
  test('manifiesto futuro', () async {
    descriptor['formatVersion'] = 2;
    await manifest.writeAsBytes(encodeBackupEnvelope(descriptor));
    await reject(LocalRestoreCandidateIssue.futureFormat);
  });
  test('catálogo futuro incluso con otro slot válido', () async {
    final future = Map<String, dynamic>.from(catalogPayload)
      ..['formatVersion'] = 2;
    await File(p.join(base(), 'catalog-b.json'))
        .writeAsBytes(encodeBackupEnvelope(future));
    await reject(LocalRestoreCandidateIssue.futureFormat);
  });
  test('catálogo ilegible no se interpreta como ausencia', () async {
    await catalog.writeAsBytes([1, 2, 3]);
    await reject(LocalRestoreCandidateIssue.invalidMetadata);
  });
  test('manifiesto dañado', () async {
    await manifest.writeAsBytes([1, 2, 3]);
    await reject(LocalRestoreCandidateIssue.invalidMetadata);
  });
  test('sidecars impiden usar copia incompleta', () async {
    await File('${image.path}-wal').writeAsBytes([1, 2, 3]);
    await reject(LocalRestoreCandidateIssue.incompleteFile);
  });
  test('baja duradera impide usar original conservado', () async {
    final tombstone = File(p.join(base(), 'tombstones', '$_id.json'));
    await tombstone.parent.create();
    await tombstone.writeAsBytes([1, 2, 3]);
    await reject(LocalRestoreCandidateIssue.invalidMetadata);
  });
  test('archivo ausente', () async {
    await image.delete();
    final result = await service.prepare(_id) as RejectedLocalRestoreCandidate;
    expect(result.issue, LocalRestoreCandidateIssue.missingFile);
    expect(await image.exists(), isFalse);
  });
  test('ID/ruta externa rechazada', () async {
    for (final id in ['../$_id', image.path, 'file://${image.path}', 'otro']) {
      expect(
        (await service.prepare(id) as RejectedLocalRestoreCandidate).issue,
        LocalRestoreCandidateIssue.invalidMetadata,
      );
    }
  });
  test('enlace/junction en la ruta privada se rechaza sin seguirlo', () async {
    final original = await image.parent.rename('${image.parent.path}-original');
    final alias = image.parent.path;
    if (Platform.isWindows) {
      final linkPath = alias.replaceAll("'", "''");
      final targetPath = original.path.replaceAll("'", "''");
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "New-Item -ItemType Junction -Path '$linkPath' -Target '$targetPath' -ErrorAction Stop | Out-Null",
      ]);
      expect(result.exitCode, 0);
    } else {
      await Link(alias).create(original.path);
    }
    try {
      await reject(LocalRestoreCandidateIssue.invalidMetadata);
    } finally {
      if (Platform.isWindows) {
        await Directory(alias).delete();
      } else {
        await Link(alias).delete();
      }
      await original.rename(alias);
    }
  });
  test('I/O inaccesible se distingue de corrupción', () async {
    service = createLocalRestoreCandidatePreparer(
      supportDirectory: () async {
        throw const FileSystemException('synthetic inaccessible support');
      },
    );
    await reject(LocalRestoreCandidateIssue.storageFailure);
  });
  for (final failure in ['flush', 'move']) {
    test(
      'fallo de $failure no anuncia staging listo ni toca originales',
      () async {
        final persistence = _FailPersistence()
          ..failFlush = failure == 'flush'
          ..failMove = failure == 'move';
        service = createLocalRestoreCandidatePreparer(
          supportDirectory: () async => support,
          persistence: persistence,
        );
        await reject(LocalRestoreCandidateIssue.storageFailure);
      },
    );
  }
  test('migración interrumpida: original antiguo intacto', () async {
    createImage(5);
    await writeMetadata(version: 5);
    final policy = _Policy()
      ..beforeMigration = (path) async {
        expect(p.isWithin(p.join(base(), 'restore'), path), isTrue);
        final db = sqlite3.open(path);
        try {
          db.execute('CREATE TABLE unexpected(value TEXT)');
        } finally {
          db.close();
        }
      };
    service = LocalRestoreCandidateService(
      policy: policy,
      supportDirectory: () async => support,
    );
    await reject(LocalRestoreCandidateIssue.schemaMismatch);
  });
  test('fallo tipado durante migración se conserva como motivo', () async {
    createImage(5);
    await writeMetadata(version: 5);
    final policy = _Policy()
      ..beforeMigration = (_) async {
        throw const LocalRestoreCandidateFailure(
          LocalRestoreCandidateIssue.migrationFailure,
        );
      };
    service = LocalRestoreCandidateService(
      policy: policy,
      supportDirectory: () async => support,
    );
    await reject(LocalRestoreCandidateIssue.migrationFailure);
  });
  test(
    'cambio de origen durante preparación se detecta antes de publicar',
    () async {
      final policy = _Policy()
        ..beforeMigration = (_) async {
          final bytes = await image.readAsBytes();
          bytes[100] ^= 1;
          await image.writeAsBytes(bytes);
        };
      service = LocalRestoreCandidateService(
        policy: policy,
        supportDirectory: () async => support,
      );
      expect(
        (await service.prepare(_id) as RejectedLocalRestoreCandidate).issue,
        LocalRestoreCandidateIssue.hashMismatch,
      );
    },
  );
  test('exclusión comparte bloqueo con catálogo/creación', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final held = NativeBackupPersistence().exclusively(
      p.join(root(), '.local-backups.lock'),
      () async {
        entered.complete();
        await release.future;
      },
    );
    await entered.future;
    try {
      await reject(LocalRestoreCandidateIssue.operationInProgress);
    } finally {
      release.complete();
      await held;
    }
  });
}
