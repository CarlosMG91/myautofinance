import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_portable_backup_inspector.dart';
import 'package:myautofinance/app/local_backup_factory.dart';
import 'package:myautofinance/app/portable_backup_export_factory.dart';
import 'package:myautofinance/core/persistence/unit_of_work.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';
import 'package:myautofinance/features/synchronization/data/portable_backup_exporter.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory exports;
  late LocalDatabaseStore store;
  late String activePath;
  late Map<String, dynamic> tables;
  const inspector = SqlitePortableBackupInspector();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('portable-synthetic-');
    exports = await Directory('${root.path}/outputs').create();
    store = LocalDatabaseStore(supportDirectory: () async => root);
    await store.open();
    activePath = store.databasePath!;
    await store.close();
    tables =
        (jsonDecode(
              await File('docs/ep-027/ejemplos/origen-sintetico.json')
                  .readAsString(),
            ) as Map<String, dynamic>)['tables']
            as Map<String, dynamic>;
    final db = sqlite3.open(activePath);
    try {
      configureConnection(db);
      db.execute('DELETE FROM database_state');
      for (final name in [
        'database_state',
        'accounts',
        'categories',
        'account_liquidity_periods',
        'import_batches',
        'import_rows',
        'movements',
        'budgets',
        'wealth_snapshots',
        'wealth_values',
        'import_batch_metadata',
        'import_row_originals',
      ]) {
        final integers = db
            .select('PRAGMA table_info($name)')
            .where((c) => c['type'] == 'INTEGER')
            .map((c) => c['name'])
            .toSet();
        for (final row in tables[name] as List<dynamic>) {
          final data = row as Map<String, dynamic>;
          db.execute(
            'INSERT INTO $name (${data.keys.join(',')}) VALUES (${data.keys.map((_) => '?').join(',')})',
            data.entries
                .map(
                  (e) => e.value != null && integers.contains(e.key)
                      ? int.parse('${e.value}')
                      : e.value,
                )
                .toList(),
          );
        }
      }
    } finally {
      db.close();
    }
  });
  tearDown(() async {
    await store.close();
    await root.delete(recursive: true);
  });

  Future<PreparedDataExport> prepare({DataExportCancellation? token}) =>
      createPortableBackupExporter(
        store: store,
        temporaryDirectory: () async => exports,
      ).prepare(cancellation: token ?? DataExportCancellation());

  Future<void> expectClean() async {
    expect(await exports.list().toList(), isEmpty);
    final copies = Directory('${root.path}/sqlite/copies');
    if (await copies.exists()) expect(await copies.list().toList(), isEmpty);
  }

  test('ZIP completo v1 conserva todas las filas/objetos, abre aislado sin app ni sidecars', () async {
    // Archivos de instalación deliberadamente ajenos a la SQLite financiera.
    await File('${root.path}/session-synthetic.json')
        .writeAsString('TOKEN-FICTICIO');
    await File('${root.path}/drive-state-synthetic.json')
        .writeAsString('DRIVE-FICTICIO');
    final activeBytes = await File(activePath).readAsBytes();
    final result = await prepare();
    try {
      final zipBytes = await File(result.zipPath).readAsBytes();
      if (Platform.environment['AF_PORTABLE_SYNTHETIC_ZIP'] case final path?) {
        await File(path).writeAsBytes(zipBytes);
      }
      final files = _unzip(zipBytes);
      expect(files.keys.toList(), [
        'LEEME.md',
        'autofinance.sqlite',
        'manifest.json',
      ]);
      final manifest = jsonDecode(
        utf8.decode(files['manifest.json']!),
      ) as Map<String, dynamic>;
      expect(
        manifest.keys,
        unorderedEquals([
          'kind',
          'formatVersion',
          'exportId',
          'createdAtUtc',
          'datasetId',
          'revision',
          'applicationId',
          'schemaVersion',
          'currency',
          'filter',
          'dictionary',
          'files',
          'databaseTables',
        ]),
      );
      expect(manifest['kind'], 'autofinance.portableBackup');
      expect(
        DateTime.parse(manifest['createdAtUtc'] as String),
        result.createdAtUtc,
      );
      expect(manifest['formatVersion'], 1);
      expect(manifest['datasetId'], result.state.datasetId);
      expect(manifest['revision'], '9223372036854775807');
      expect(result.state.revision, 9223372036854775807);
      expect(manifest['applicationId'], localApplicationId);
      expect(manifest['schemaVersion'], localSchemaVersion);
      expect(manifest['currency'], 'EUR');
      expect(manifest['filter'], isNull);
      expect(manifest['dictionary'], isNull);
      expect(manifest['exportId'], result.exportId);
      expect(
        result.exportId,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(
        manifest['createdAtUtc'],
        matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$')),
      );
      final descriptions = manifest['files'] as List<dynamic>;
      expect(descriptions.map((e) => e['path']), [
        'LEEME.md',
        'autofinance.sqlite',
      ]);
      for (final entry in descriptions) {
        final bytes = files[entry['path']]!;
        expect(entry['sizeBytes'], '${bytes.length}');
        expect(entry['sha256'], sha256.convert(bytes).toString());
        expect(entry['rowCount'], isNull);
        expect(
          entry['mediaType'],
          entry['path'] == 'LEEME.md'
              ? 'text/markdown'
              : 'application/vnd.sqlite3',
        );
      }
      final isolated = await Directory('${root.path}/consulta-nueva').create();
      final sqlite = File('${isolated.path}/autofinance.sqlite');
      await sqlite.writeAsBytes(files['autofinance.sqlite']!);
      // SQLite estándar: ninguna función registrada por configureConnection.
      final db = sqlite3.open(sqlite.path, mode: OpenMode.readOnly);
      final original = sqlite3.open(activePath, mode: OpenMode.readOnly);
      try {
        expect(db.select('PRAGMA integrity_check').single.values.single, 'ok');
        expect(db.select('PRAGMA foreign_key_check'), isEmpty);
        expect(
          db.select('PRAGMA application_id').single.values.single,
          manifest['applicationId'],
        );
        expect(
          db.select('PRAGMA user_version').single.values.single,
          manifest['schemaVersion'],
        );
        final state = db
            .select('SELECT dataset_id,revision FROM database_state')
            .single;
        expect(state['dataset_id'], manifest['datasetId']);
        expect('${state['revision']}', manifest['revision']);
        expect(
          db.select("SELECT type,name,sql FROM sqlite_schema ORDER BY name"),
          original.select(
            "SELECT type,name,sql FROM sqlite_schema ORDER BY name",
          ),
        );
        final names = db
            .select(
              "SELECT name FROM sqlite_schema WHERE type='table' AND name NOT GLOB 'sqlite_*' ORDER BY name",
            )
            .map((r) => r['name'] as String)
            .toList();
        expect(
          (manifest['databaseTables'] as List).map((r) => r['name']),
          names,
        );
        for (final entry in manifest['databaseTables'] as List<dynamic>) {
          final name = entry['name'];
          expect(
            db.select('SELECT * FROM "$name" ORDER BY 1'),
            original.select('SELECT * FROM "$name" ORDER BY 1'),
            reason: name,
          );
          expect(
            entry['rowCount'],
            '${db.select('SELECT count(*) FROM "$name"').single.values.single}',
          );
        }
        // No pierde histórico exterior al rango de ejemplo de los CSV.
        expect(db.select('SELECT * FROM movements').length, 5);
        expect(db.select('SELECT * FROM import_row_originals'), isNotEmpty);
        expect(db.select('SELECT * FROM import_batch_metadata'), isNotEmpty);
      } finally {
        db.close();
        original.close();
      }
      expect((await isolated.list().toList()).length, 1);
      final readme = utf8.decode(files['LEEME.md']!);
      for (final text in [
        'carpeta NUEVA',
        'sqlite3 -readonly',
        'SHA-256',
        'NO autentica',
        'sqlite_schema',
        'sin filtro temporal',
        'no sustituye',
      ]) {
        expect(readme, contains(text));
      }
      expect(await File(activePath).readAsBytes(), activeBytes);
      expect(
        await Directory('${root.path}/sqlite/local-backups').exists(),
        isFalse,
      );
    } finally {
      await result.dispose();
      await result.dispose();
    }
    await expectClean();
  });

  test('escrituras concurrentes con captura no mezclan identidad/revisión/importes', () async {
    final live = await store.open();
    final source = _HookSource(store, (backup) async {
      // La activa cambia antes de que el consumidor reciba la imagen cerrada.
      await live.customStatement(
        "UPDATE database_state SET dataset_id='27000000-0000-4000-8000-000000000999',revision=42",
      );
      await live.customStatement(
        "UPDATE movements SET amount_cents=87654321,concept='Posterior'",
      );
    });
    final result = await PortableSqliteBackupExporter(
      source: source,
      inspector: inspector,
      temporaryDirectory: () async => exports,
    ).prepare(cancellation: DataExportCancellation());
    try {
      expect(source.calls, 1);
      final files = _unzip(await File(result.zipPath).readAsBytes());
      final path = '${root.path}/isolated.sqlite';
      await File(path).writeAsBytes(files['autofinance.sqlite']!);
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(result.state.revision, 9223372036854775807);
        expect(
          result.state.datasetId,
          tables['database_state'][0]['dataset_id'],
        );
        expect(
          db
              .select('SELECT amount_cents FROM movements')
              .map((r) => r['amount_cents']),
          isNot(contains(87654321)),
        );
        expect(
          db.select('SELECT revision FROM database_state').single.values.single,
          result.state.revision,
        );
      } finally {
        db.close();
      }
      expect((await live.readState()).revision, 42);
    } finally {
      await result.dispose();
    }
    await expectClean();
  });

  test(
    'catálogo y copias previas conservados en éxito, cancelación y fallo',
    () async {
      await createLocalBackupCreator(
        store: store,
        supportDirectory: () async => root,
      ).createManual();
      final private = Directory('${root.path}/sqlite/local-backups');
      final before = await _fingerprints(private);
      final activeBefore = await File(activePath).readAsBytes();
      final result = await prepare();
      await result.dispose();
      await expectLater(
        prepare(token: DataExportCancellation()..cancel()),
        throwsA(_failure(DataExportFailureCode.cancelled)),
      );
      final token = DataExportCancellation();
      await expectLater(
        PortableSqliteBackupExporter(
          source: _HookSource(store, (_) async => token.cancel()),
          inspector: inspector,
          temporaryDirectory: () async => exports,
        ).prepare(cancellation: token),
        throwsA(_failure(DataExportFailureCode.cancelled)),
      );
      await expectLater(
        PortableSqliteBackupExporter(
          source: store,
          inspector: inspector,
          temporaryDirectory: () async => exports,
          maxBytes: 32,
        ).prepare(cancellation: DataExportCancellation()),
        throwsA(_failure(DataExportFailureCode.limitExceeded)),
      );
      expect(await _fingerprints(private), before);
      expect(await File(activePath).readAsBytes(), activeBefore);
      await expectClean();
    },
  );

  test('captura durante escritura WAL conserva solo la transacción confirmada', () async {
    final writer = sqlite3.open(activePath);
    try {
      configureConnection(writer);
      writer.execute('PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0');
      writer.execute("UPDATE database_state SET revision=100");
      writer.execute(
        "UPDATE movements SET concept='Confirmado en WAL',amount_cents=100",
      );
      expect(await File('$activePath-wal').length(), greaterThan(0));
      // La captura se ejecuta mientras esta escritura sigue sin confirmar.
      writer.execute('BEGIN IMMEDIATE');
      writer.execute("UPDATE database_state SET revision=101");
      writer.execute(
        "UPDATE movements SET concept='Todavía sin confirmar',amount_cents=101",
      );
      final result = await prepare();
      try {
        final files = _unzip(await File(result.zipPath).readAsBytes());
        final isolated = File('${root.path}/wal-isolated.sqlite');
        await isolated.writeAsBytes(files['autofinance.sqlite']!);
        final db = sqlite3.open(isolated.path, mode: OpenMode.readOnly);
        try {
          expect(result.state.revision, 100);
          expect(
            db
                .select('SELECT DISTINCT concept,amount_cents FROM movements')
                .map((r) => r.values.toList())
                .toList(),
            [
              ['Confirmado en WAL', 100],
            ],
          );
        } finally {
          db.close();
        }
      } finally {
        await result.dispose();
      }
      writer.execute('COMMIT');
      expect((await (await store.open()).readState()).revision, 101);
    } finally {
      writer.close();
    }
    await expectClean();
  });

  test('metadatos declarados falsos, bytes, claves, reglas y esquema alterados se rechazan', () async {
    final before = await File(activePath).readAsBytes();
    final sources = <LocalBackupSource>[
      _HookSource(store, (_) async {}, lie: true),
      for (final sql in [
        'PRAGMA application_id=1',
        'PRAGMA user_version=${localSchemaVersion + 1}',
        "CREATE TABLE oauth_tokens(token TEXT)",
      ])
        _HookSource(store, (backup) async {
          final db = sqlite3.open(backup.path);
          try {
            db.execute(sql);
          } finally {
            db.close();
          }
        }),
      for (final invalidUpdate in [
        "UPDATE movements SET account_id='27000000-0000-4000-8000-000000000999'",
        "UPDATE movements SET value_date='1900-01-01'",
      ])
        _HookSource(store, (backup) async {
          final db = sqlite3.open(backup.path);
          try {
            final trigger =
                db
                        .select(
                          "SELECT sql FROM sqlite_schema WHERE name='movements_update'",
                        )
                        .single['sql']
                    as String;
            db.execute(
              'PRAGMA foreign_keys=OFF; DROP TRIGGER movements_update',
            );
            db.execute(invalidUpdate);
            db.execute(trigger);
          } finally {
            db.close();
          }
        }),
      _HookSource(store, (backup) async {
        final file = File(backup.path);
        final bytes = await file.readAsBytes();
        bytes[0] = 0;
        await file.writeAsBytes(bytes, flush: true);
      }),
      _HookSource(store, (backup) async {
        await File('${backup.path}-wal').writeAsString('sidecar');
      }),
    ];
    for (final (index, source) in sources.indexed) {
      await expectLater(
        PortableSqliteBackupExporter(
          source: source,
          inspector: inspector,
          temporaryDirectory: () async => exports,
        ).prepare(cancellation: DataExportCancellation()),
        throwsA(_failure(DataExportFailureCode.invalidSnapshot)),
        reason: 'Imagen alterada $index',
      );
      await expectClean();
    }
    expect(await File(activePath).readAsBytes(), before);
  });

  test(
    'mutación durante validación del archivo final nunca produce éxito',
    () async {
      for (final changeMetadata in [false, true]) {
        await expectLater(
          PortableSqliteBackupExporter(
            source: store,
            inspector: _TamperingInspector(inspector, changeMetadata),
            temporaryDirectory: () async => exports,
          ).prepare(cancellation: DataExportCancellation()),
          throwsA(isA<DataExportFailure>()),
        );
        await expectClean();
      }
    },
  );

  test('cancelación durante empaquetado y fallo de almacenamiento limpian solo lo propio', () async {
    final sentinel = File('${exports.path}/ajeno.txt');
    await sentinel.writeAsString('conservar');
    final token = DataExportCancellation();
    await expectLater(
      PortableSqliteBackupExporter(
        source: store,
        inspector: _CancelInspector(inspector, token),
        temporaryDirectory: () async => exports,
      ).prepare(cancellation: token),
      throwsA(_failure(DataExportFailureCode.cancelled)),
    );
    await expectLater(
      PortableSqliteBackupExporter(
        source: store,
        inspector: inspector,
        temporaryDirectory: () async =>
            throw const FileSystemException('sensible'),
      ).prepare(cancellation: DataExportCancellation()),
      throwsA(_failure(DataExportFailureCode.storage)),
    );
    expect(await sentinel.readAsString(), 'conservar');
    await sentinel.delete();
    await expectClean();
  });

  test(
    'activa no se adopta ni elimina, dos exportaciones no colisionan',
    () async {
      final state = await (await store.open()).readState();
      final before = await File(activePath).readAsBytes();
      await expectLater(
        PortableSqliteBackupExporter(
          source: _FixedSource(LocalBackup(path: activePath, state: state)),
          inspector: inspector,
          temporaryDirectory: () async => exports,
        ).prepare(cancellation: DataExportCancellation()),
        throwsA(_failure(DataExportFailureCode.invalidSnapshot)),
      );
      expect(await File(activePath).readAsBytes(), before);
      final results = await Future.wait([prepare(), prepare()]);
      expect(results[0].exportId, isNot(results[1].exportId));
      expect(results[0].zipPath, isNot(results[1].zipPath));
      await results[0].dispose();
      expect(await File(results[1].zipPath).exists(), isTrue);
      await results[1].dispose();
      await expectClean();
    },
  );

  test('base financiera nueva también es portable', () async {
    final empty = LocalDatabaseStore(
      supportDirectory: () async => Directory('${root.path}/empty'),
    );
    try {
      final result = await createPortableBackupExporter(
        store: empty,
        temporaryDirectory: () async => exports,
      ).prepare(cancellation: DataExportCancellation());
      final files = _unzip(await File(result.zipPath).readAsBytes());
      final manifest = jsonDecode(utf8.decode(files['manifest.json']!));
      expect(manifest['revision'], '0');
      for (final table in manifest['databaseTables'] as List) {
        expect(
          table['rowCount'],
          table['name'] == 'database_state' ? '1' : '0',
        );
      }
      await result.dispose();
    } finally {
      await empty.close();
    }
    await expectClean();
  });
}

Matcher _failure(DataExportFailureCode code) =>
    isA<DataExportFailure>().having((e) => e.code, 'code', code);

Future<Map<String, String>> _fingerprints(Directory root) async => {
  await for (final file in root.list(recursive: true, followLinks: false))
    if (file is File)
      file.path: sha256.convert(await file.readAsBytes()).toString(),
};

// Lector independiente del escritor: ZIP estándar STORE, sin librería de producto.
Map<String, Uint8List> _unzip(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final files = <String, Uint8List>{};
  var offset = 0;
  while (data.getUint32(offset, Endian.little) == 0x04034b50) {
    expect(data.getUint16(offset + 8, Endian.little), 0);
    final size = data.getUint32(offset + 18, Endian.little);
    final nameSize = data.getUint16(offset + 26, Endian.little);
    final extraSize = data.getUint16(offset + 28, Endian.little);
    final name = utf8.decode(
      bytes.sublist(offset + 30, offset + 30 + nameSize),
    );
    expect(files.containsKey(name), isFalse);
    final start = offset + 30 + nameSize + extraSize;
    files[name] = Uint8List.sublistView(bytes, start, start + size);
    offset = start + size;
  }
  expect(data.getUint32(offset, Endian.little), 0x02014b50);
  expect(data.getUint32(bytes.length - 22, Endian.little), 0x06054b50);
  expect(data.getUint16(bytes.length - 12, Endian.little), files.length);
  return files;
}

final class _FixedSource implements LocalBackupSource {
  _FixedSource(this.backup);
  final LocalBackup backup;
  @override
  Future<LocalBackup> createConsistentBackup() async => backup;
}

final class _HookSource implements LocalBackupSource {
  _HookSource(this.source, this.after, {this.lie = false});
  final LocalBackupSource source;
  final Future<void> Function(LocalBackup) after;
  final bool lie;
  int calls = 0;
  @override
  Future<LocalBackup> createConsistentBackup() async {
    calls++;
    final backup = await source.createConsistentBackup();
    await after(backup);
    return lie
        ? LocalBackup(
            path: backup.path,
            state: const DatasetState(
              datasetId: '27000000-0000-4000-8000-000000000999',
              revision: 1,
            ),
          )
        : backup;
  }
}

final class _TamperingInspector implements PortableBackupImageInspector {
  _TamperingInspector(this.inner, this.metadata);
  final PortableBackupImageInspector inner;
  final bool metadata;
  int calls = 0;
  @override
  Future<PortableBackupImage> inspect(String path) async {
    final image = await inner.inspect(path);
    if (++calls == 2) {
      if (metadata) {
        return PortableBackupImage(
          database: image.database,
          tables: {...image.tables, 'movements': 999},
        );
      }
      final db = sqlite3.open(path);
      try {
        db.execute("UPDATE movements SET concept='Alterado' ");
      } finally {
        db.close();
      }
    }
    return image;
  }
}

final class _CancelInspector implements PortableBackupImageInspector {
  _CancelInspector(this.inner, this.token);
  final PortableBackupImageInspector inner;
  final DataExportCancellation token;
  int calls = 0;
  @override
  Future<PortableBackupImage> inspect(String path) async {
    final image = await inner.inspect(path);
    if (++calls == 2) token.cancel();
    return image;
  }
}
