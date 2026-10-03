import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:myautofinance/app/local_backup_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/core/persistence/unit_of_work.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';
import 'package:myautofinance/features/synchronization/data/backup_json.dart';
import 'package:myautofinance/features/synchronization/data/backup_catalog.dart';
import 'package:myautofinance/features/synchronization/data/local_backup_service.dart';
import 'package:myautofinance/features/synchronization/data/native_backup_persistence.dart';

const restoreId = '22222222-2222-4222-8222-222222222222';

final class _Source implements LocalBackupSource {
  _Source(this.store);
  final LocalDatabaseStore store;
  int calls = 0;
  void Function()? onCalled;
  String? pathOverride;
  Future<void> Function(LocalBackup)? after;
  @override
  Future<LocalBackup> createConsistentBackup() async {
    calls++;
    onCalled?.call();
    final result = await store.createConsistentBackup();
    await after?.call(result);
    return pathOverride == null
        ? result
        : LocalBackup(path: pathOverride!, state: result.state);
  }
}

class _Persistence extends NativeBackupPersistence {
  String? fail;
  String? failFlush;
  final reached = <String>[];
  Future<void> Function(String)? before;
  @override
  Future<void> move(
    String source,
    String target, {
    bool replace = false,
  }) async {
    final point = target.endsWith('intent.json')
        ? 'intent'
        : target.endsWith('receipt.json')
        ? 'receipt'
        : target.endsWith('autofinance.sqlite.part')
        ? 'image'
        : target.endsWith('manifest.json.part')
        ? 'manifest'
        : p.basename(p.dirname(target)) == 'backups'
        ? 'publish'
        : replace && target.endsWith('.json')
        ? 'catalog'
        : 'other';
    reached.add(point);
    await before?.call(point);
    if (point == fail) {
      throw const FileSystemException('synthetic write failure');
    }
    await super.move(source, target, replace: replace);
  }

  @override
  Future<void> flushFile(String path) async {
    if (failFlush != null && path.contains(failFlush!)) {
      throw const FileSystemException('synthetic flush/close failure');
    }
    await super.flushFile(path);
  }
}

final class _Validator implements LocalBackupImageValidator {
  Future<void> Function(String)? before;
  @override
  Future<LocalBackupImage> validate(String path) async {
    await before?.call(path);
    return const SqliteLocalBackupValidator().validate(path);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late LocalDatabaseStore store;
  late LocalDatabase db;
  late _Source source;
  late _Persistence persistence;
  late _Validator validator;
  late LocalBackupService service;

  String getRoot() => p.join(support.path, 'sqlite');
  String getBase() => p.join(getRoot(), 'local-backups');
  Future<Map<String, dynamic>> catalog() async {
    final slots = <Map<String, dynamic>>[];
    for (final name in ['a', 'b']) {
      final f = File(p.join(getBase(), 'catalog-$name.json'));
      if (await f.exists()) {
        slots.add(decodeBackupEnvelope(await f.readAsBytes()));
      }
    }
    slots.sort(
      (a, b) =>
          backupCounter(b['generation'])
              .compareTo(backupCounter(a['generation'])),
    );
    return slots.first;
  }

  Future<void> assertActive(DatasetState before) async {
    final current = await db.readState();
    expect(current.datasetId, before.datasetId);
    expect(current.revision, before.revision);
    expect((await catalog())['entries'], isEmpty);
  }

  LocalBackupService newService() => LocalBackupService(
    source: source,
    validator: validator,
    supportDirectory: () async => support,
    persistence: persistence,
    clock: () => DateTime.utc(2026, 10, 2, 12),
  );

  setUp(() async {
    support = await Directory.systemTemp.createTemp('local-backup-synthetic-');
    store = LocalDatabaseStore(supportDirectory: () async => support);
    db = await store.open();
    source = _Source(store);
    persistence = _Persistence();
    validator = _Validator();
    service = newService();
  });
  tearDown(() async {
    await store.close();
    await support.delete(recursive: true);
  });

  test(
    'WAL, escritura posterior, identidad y manifiesto de la imagen capturada',
    () async {
      await db.customStatement('PRAGMA journal_mode=WAL');
      await db.customStatement('PRAGMA wal_autocheckpoint=0');
      await SqliteCategoryRepository(db).create(name: 'Antes');
      final before = await db.readState();
      source.after = (_) async {
        await SqliteCategoryRepository(db).create(name: 'Después');
      };
      final result = await service.createManual();
      expect(source.calls, 1);
      expect(result.state.revision, before.revision);
      expect((await db.readState()).revision, before.revision + 1);
      final dir = p.joinAll([
        getRoot(),
        ...result.relativeDirectory.split('/'),
      ]);
      expect(
        (await Directory(dir).list().toList()).map((e) => p.basename(e.path)),
        unorderedEquals(['autofinance.sqlite', 'manifest.json']),
      );
      final file = File(p.join(dir, 'autofinance.sqlite'));
      final manifest = decodeBackupEnvelope(
        await File(p.join(dir, 'manifest.json')).readAsBytes(),
      );
      expect(manifest['revision'], '${before.revision}');
      expect(manifest['datasetId'], before.datasetId);
      expect(manifest['schemaVersion'], localSchemaVersion);
      expect(
        manifest['databaseSha256'],
        sha256.convert(await file.readAsBytes()).toString(),
      );
      expect(manifest['sizeBytes'], '${await file.length()}');
      final read = sqlite3.open(file.path, mode: OpenMode.readOnly);
      try {
        expect(
          read.select('SELECT name FROM categories').map((r) => r['name']),
          ['Antes'],
        );
      } finally {
        read.close();
      }
      expect((await catalog())['entries'], hasLength(1));
      expect(result.cleanupPending, false);
    },
  );

  test(
    'snapshot espera una unidad concurrente y publica relaciones confirmadas',
    () async {
      final entered = Completer<void>();
      final finish = Completer<void>();
      final capturing = Completer<void>();
      source.onCalled = capturing.complete;
      final write = db.run(() async {
        await SqliteCategoryRepository(db).create(name: 'Concurrente');
        entered.complete();
        await finish.future;
        await SqliteCategoryRepository(db)
            .create(name: 'Confirmada en la misma unidad');
      });
      await entered.future;
      final creation = service.createManual();
      await capturing.future;
      finish.complete();
      await write;
      final result = await creation;
      expect(result.state.revision, (await db.readState()).revision);
      expect(source.calls, 1);
      final image = sqlite3.open(
        p.join(getRoot(), result.relativeDirectory, 'autofinance.sqlite'),
        mode: OpenMode.readOnly,
      );
      try {
        expect(
          image.select('SELECT count(*) AS n FROM categories').single['n'],
          2,
        );
      } finally {
        image.close();
      }
    },
  );

  test(
    'temporales no se catalogan mientras valida; segunda creación bloqueada',
    () async {
      final validating = Completer<void>();
      final proceed = Completer<void>();
      validator.before = (_) async {
        validating.complete();
        await proceed.future;
      };
      final pending = service.createManual();
      await validating.future;
      expect((await catalog())['entries'], isEmpty);
      expect(
        await Directory(p.join(getBase(), 'backups')).list().isEmpty,
        true,
      );
      await expectLater(
        newService().createManual(),
        throwsA(
          isA<LocalBackupFailure>().having(
            (e) => e.code,
            'code',
            LocalBackupFailureCode.operationInProgress,
          ),
        ),
      );
      proceed.complete();
      await pending;
    },
  );

  test(
    'dos manuales iguales y automática tienen IDs/órdenes independientes',
    () async {
      final a = await service.createManual();
      final b = await newService().createManual();
      final c = await service.createPreRestore(restoreId);
      expect({a.backupId, b.backupId, c.backupId}, hasLength(3));
      expect([a.creationOrder, b.creationOrder, c.creationOrder], [1, 2, 3]);
      final entries = (await catalog())['entries'] as List;
      expect(entries, hasLength(3));
      expect(entries[2]['descriptor']['origin'], 'preRestore');
      expect(entries[2]['descriptor']['restoreOperationId'], restoreId);
      expect(
        entries[0]['descriptor']['databaseSha256'],
        entries[1]['descriptor']['databaseSha256'],
      );
    },
  );

  for (final point in ['receipt', 'image', 'manifest', 'publish']) {
    test('fallo $point conserva activa, intent y no anuncia copia', () async {
      final before = await db.readState();
      persistence.fail = point;
      await expectLater(
        service.createManual(),
        throwsA(isA<LocalBackupFailure>()),
      );
      await assertActive(before);
      expect(source.calls, 1);
      final intents = await Directory(p.join(getBase(), 'staging'))
          .list()
          .toList();
      expect(intents, hasLength(1));
      expect(
        await File(p.join(intents.single.path, 'intent.json')).exists(),
        true,
      );
      persistence.fail = null;
      final retry = await newService().createManual();
      expect(retry.creationOrder, 2);
    });
  }

  for (final point in ['autofinance.sqlite.part', 'manifest.json.part']) {
    test('fallo de flush/cierre $point no publica ni cambia activa', () async {
      final before = await db.readState();
      persistence.failFlush = point;
      await expectLater(
        service.createManual(),
        throwsA(isA<LocalBackupFailure>()),
      );
      await assertActive(before);
    });
  }

  test(
    'registro final fallido conserva catálogo anterior y artefacto recuperable',
    () async {
      var catalogs = 0;
      persistence.before = (point) async {
        if (point == 'catalog' && ++catalogs == 3) persistence.fail = 'catalog';
      };
      final before = await db.readState();
      await expectLater(
        service.createManual(),
        throwsA(isA<LocalBackupFailure>()),
      );
      await assertActive(before);
      expect(
        (await Directory(p.join(getBase(), 'backups')).list().toList()),
        hasLength(1),
      );
      persistence.fail = null;
      persistence.before = null;
      await expectLater(
        newService().createManual(),
        throwsA(
          isA<LocalBackupFailure>().having(
            (e) => e.code,
            'code',
            LocalBackupFailureCode.recoveryRequired,
          ),
        ),
      );
      expect(source.calls, 1);
    },
  );

  test('fallo reservando intent o catálogo no invoca snapshot', () async {
    persistence.fail = 'intent';
    await expectLater(
      service.createManual(),
      throwsA(isA<LocalBackupFailure>()),
    );
    expect(source.calls, 0);
    expect((await catalog())['entries'], isEmpty);
  });

  test(
    'snapshot rechazado en UnitOfWork no publica ni cambia revisión',
    () async {
      final before = await db.readState();
      await db.run(() async {
        await expectLater(
          service.createManual(),
          throwsA(isA<LocalBackupFailure>()),
        );
      });
      await assertActive(before);
    },
  );

  for (final corruption in [
    'identity',
    'revision',
    'schema',
    'foreign',
    'financial',
    'foreignKey',
    'integrity',
  ]) {
    test('política integral rechaza $corruption y conserva activa', () async {
      final before = await db.readState();
      source.after = (snapshot) async {
        if (corruption == 'integrity') {
          await File(snapshot.path).writeAsBytes([1, 2, 3]);
          return;
        }
        final image = sqlite3.open(snapshot.path);
        try {
          switch (corruption) {
            case 'identity':
              image.execute(
                "UPDATE database_state SET dataset_id='11111111-1111-4111-8111-111111111111'",
              );
            case 'revision':
              image.execute('UPDATE database_state SET revision=revision+1');
            case 'schema':
              image.execute('PRAGMA user_version=99');
            case 'foreign':
              image.execute('PRAGMA application_id=123');
            case 'financial':
              image.execute('PRAGMA ignore_check_constraints=ON');
              image.execute(
                "INSERT INTO accounts (id,name,kind,active_from,active_through,created_at,updated_at) VALUES ('11111111-1111-4111-8111-111111111111','Sintética','account','2026-01-01',NULL,'x','x')",
              );
            case 'foreignKey':
              image.execute('PRAGMA foreign_keys=OFF');
              final guard =
                  image
                          .select(
                            "SELECT sql FROM sqlite_master WHERE name='categories_destination_insert'",
                          )
                          .single['sql']
                      as String;
              image.execute('DROP TRIGGER categories_destination_insert');
              image.execute(
                "INSERT INTO categories (id,parent_id,name,is_income,archived,created_at,updated_at) VALUES ('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Sintética',NULL,0,'x','x')",
              );
              image.execute(guard);
          }
        } finally {
          image.close();
        }
      };
      await expectLater(
        service.createManual(),
        throwsA(isA<LocalBackupFailure>()),
      );
      await assertActive(before);
    });
  }

  test('revisión superior a 2^53 no redondea', () async {
    await db.customStatement(
      'UPDATE database_state SET revision=9007199254740993',
    );
    final result = await service.createManual();
    expect(result.state.revision, 9007199254740993);
    expect(
      (await catalog())['entries'][0]['descriptor']['revision'],
      '9007199254740993',
    );
  });

  test(
    'reinicio tras intent con orden no confirmado no lo reutiliza',
    () async {
      var catalogs = 0;
      persistence.before = (point) async {
        if (point == 'catalog' && ++catalogs == 2) persistence.fail = 'catalog';
      };
      await expectLater(
        service.createManual(),
        throwsA(isA<LocalBackupFailure>()),
      );
      expect(source.calls, 0);
      persistence.fail = null;
      persistence.before = null;
      expect((await newService().createManual()).creationOrder, 2);
    },
  );

  test('slot futuro o dañado se conserva sin capturar', () async {
    await service.createManual();
    final a = File(p.join(getBase(), 'catalog-a.json'));
    final future = decodeBackupEnvelope(await a.readAsBytes());
    future['formatVersion'] = 2;
    final bytes = encodeBackupEnvelope(future);
    await a.writeAsBytes(bytes);
    await expectLater(
      newService().createManual(),
      throwsA(
        isA<LocalBackupFailure>().having(
          (e) => e.code,
          'code',
          LocalBackupFailureCode.incompatibleCatalog,
        ),
      ),
    );
    expect(await a.readAsBytes(), bytes);
    expect(source.calls, 1);
    await a.writeAsString('truncated');
    await expectLater(
      newService().createManual(),
      throwsA(
        isA<LocalBackupFailure>().having(
          (e) => e.code,
          'code',
          LocalBackupFailureCode.recoveryRequired,
        ),
      ),
    );
    expect(await a.readAsString(), 'truncated');
  });

  test('sobres rechazan hash, BOM, claves duplicadas y contadores inexactos', () {
    for (final bytes in [
      utf8.encode('{"payload":"{}","payloadSha256":"wrong"}'),
      [239, 187, 191, ...encodeBackupEnvelope({})],
      utf8.encode(
        jsonEncode({
          'payload': '\uFEFF{}',
          'payloadSha256': sha256.convert(utf8.encode('\uFEFF{}')).toString(),
        }),
      ),
      utf8.encode(
        '{"payload":"{}","payload":"{}","payloadSha256":"${backupPayloadHash({})}"}',
      ),
    ]) {
      expect(
        () => decodeBackupEnvelope(bytes),
        throwsA(isA<LocalBackupFailure>()),
      );
    }
    for (final counter in ['01', '-1', '1.0', '9223372036854775808']) {
      expect(() => backupCounter(counter), throwsA(isA<LocalBackupFailure>()));
    }
  });

  test(
    'versiones e identificadores numéricos requieren enteros JSON',
    () async {
      await service.createManual();
      final data = await catalog();
      final descriptor = Map<String, dynamic>.from(
        data['entries'][0]['descriptor'] as Map,
      );
      for (final field in ['formatVersion', 'applicationId']) {
        final malformed = Map<String, dynamic>.from(descriptor);
        malformed[field] = (malformed[field] as int).toDouble();
        expect(
          () => checkBackupDescriptor(malformed),
          throwsA(isA<LocalBackupFailure>()),
        );
      }
    },
  );

  test(
    'fallo de espacio mantiene bytes de copias manuales anteriores',
    () async {
      final previous = await service.createManual();
      final previousPath = p.join(getRoot(), previous.relativeDirectory);
      final previousDatabase = await File(
        p.join(previousPath, 'autofinance.sqlite'),
      ).readAsBytes();
      final previousManifest = await File(p.join(previousPath, 'manifest.json'))
          .readAsBytes();
      final active = await db.readState();
      persistence.failFlush = 'autofinance.sqlite.part';
      await expectLater(
        service.createManual(),
        throwsA(
          isA<LocalBackupFailure>().having(
            (e) => e.code,
            'code',
            LocalBackupFailureCode.storageFailure,
          ),
        ),
      );
      expect((await db.readState()).revision, active.revision);
      expect((await catalog())['entries'], hasLength(1));
      expect(
        await File(p.join(previousPath, 'autofinance.sqlite')).readAsBytes(),
        previousDatabase,
      );
      expect(
        await File(p.join(previousPath, 'manifest.json')).readAsBytes(),
        previousManifest,
      );
      persistence.failFlush = null;
      expect((await newService().createManual()).creationOrder, 3);
    },
  );

  test(
    'limpieza conserva archivos desconocidos y devuelve aviso tras publicar',
    () async {
      persistence.before = (point) async {
        if (point != 'publish') return;
        final stage = (await Directory(
          p.join(getBase(), 'staging'),
        ).list().toList()).single;
        await File(p.join(stage.path, 'unknown.bin')).writeAsBytes([4, 5, 6]);
      };
      final result = await service.createManual();
      expect(result.cleanupPending, true);
      expect((await catalog())['entries'], hasLength(1));
      final stage = (await Directory(
        p.join(getBase(), 'staging'),
      ).list().toList()).single;
      expect(await File(p.join(stage.path, 'unknown.bin')).readAsBytes(), [
        4,
        5,
        6,
      ]);
    },
  );

  test(
    'ruta externa no se adopta ni se mueve al almacenamiento privado',
    () async {
      final external = await Directory(
        p.join(support.path, 'external-synthetic'),
      ).create();
      final image = File(p.join(external.path, 'autofinance.sqlite'));
      source.after = (snapshot) async {
        await File(snapshot.path).rename(image.path);
        source.pathOverride = image.path;
      };
      await expectLater(
        service.createManual(),
        throwsA(isA<LocalBackupFailure>()),
      );
      expect(await image.exists(), true);
      expect((await catalog())['entries'], isEmpty);
    },
  );

  test(
    'imagen con WAL se rechaza sin trasladar solo su archivo principal',
    () async {
      source.after = (snapshot) async {
        await File('${snapshot.path}-wal').writeAsBytes([1, 2, 3]);
      };
      await expectLater(
        service.createManual(),
        throwsA(
          isA<LocalBackupFailure>().having(
            (e) => e.code,
            'code',
            LocalBackupFailureCode.invalidSnapshot,
          ),
        ),
      );
      expect((await catalog())['entries'], isEmpty);
    },
  );

  test('bloqueo de otro proceso y liberación tras terminarlo', () async {
    final configFile = File('.dart_tool/package_config.json');
    final config = jsonDecode(await configFile.readAsString()) as Map;
    final flutterPackage = (config['packages'] as List).singleWhere(
      (entry) => entry['name'] == 'flutter',
    );
    final flutterDirectory = p.fromUri(
      configFile.absolute.uri.resolve(flutterPackage['rootUri'] as String),
    );
    final dart = p.join(
      flutterDirectory,
      '..',
      '..',
      'bin',
      'cache',
      'dart-sdk',
      'bin',
      Platform.isWindows ? 'dart.exe' : 'dart',
    );
    final lock = p.join(getRoot(), '.local-backups.lock');
    final process = await Process.start(dart, [
      '--packages=.dart_tool/package_config.json',
      'test/support/backup_lock_process.dart',
      lock,
    ]);
    final errors = process.stderr.transform(utf8.decoder).join();
    try {
      expect(
        await process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 20)),
        'locked',
      );
      await expectLater(
        service.createManual(),
        throwsA(
          isA<LocalBackupFailure>().having(
            (e) => e.code,
            'code',
            LocalBackupFailureCode.operationInProgress,
          ),
        ),
      );
    } finally {
      process.kill();
      await process.exitCode;
    }
    expect(await errors, isEmpty);
    expect((await service.createManual()).creationOrder, 1);
  });
}
