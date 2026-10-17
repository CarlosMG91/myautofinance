import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/core/persistence/unit_of_work.dart';
import 'package:myautofinance/app/data_export_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_data_export_source.dart';
import 'package:myautofinance/features/synchronization/synchronization.dart';
import 'package:myautofinance/features/synchronization/data/csv_data_exporter.dart';
import 'package:myautofinance/features/synchronization/data/data_export_zip.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory exports;
  late LocalDatabaseStore store;
  late String activePath;
  late Map<String, dynamic> tables;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('export-synthetic-');
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

  Future<PreparedDataExport> prepare({
    DataExportFilter? filter,
    DataExportCancellation? cancellation,
    void Function(String, int)? onProgress,
  }) =>
      createDataExporter(
        store: store,
        temporaryDirectory: () async => exports,
      ).prepare(
        filter: filter ?? const DataExportFilter.all(),
        cancellation: cancellation ?? DataExportCancellation(),
        onProgress: onProgress,
      );

  test('ZIP coincide byte a byte con siete CSV normativos; manifiesto y contexto exactos', () async {
    final result = await prepare(
      filter: DataExportFilter.months(
        from: '2026-01-01',
        through: '2026-03-01',
      ),
    );
    try {
      final files = _unzip(await File(result.zipPath).readAsBytes());
      if (Platform.environment['AF_EXPORT_SYNTHETIC_ZIP'] case final path?) {
        await File(path).writeAsBytes(await File(result.zipPath).readAsBytes());
      }
      expect(files.length, 10);
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
      expect(manifest['kind'], 'autofinance.dataExport');
      expect(
        DateTime.parse(manifest['createdAtUtc'] as String),
        result.createdAtUtc,
      );
      expect(manifest['revision'], '9223372036854775807');
      expect(manifest['datasetId'], tables['database_state'][0]['dataset_id']);
      expect(manifest['schemaVersion'], localSchemaVersion);
      expect(manifest['applicationId'], localApplicationId);
      expect(
        manifest['exportId'],
        matches(
          RegExp(r'^[0-9a-f-]{14}4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'),
        ),
      );
      expect(
        manifest['createdAtUtc'],
        matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$')),
      );
      expect(manifest['databaseTables'], isEmpty);
      expect(manifest['dictionary'], 'diccionario.json');
      expect(
        files['diccionario.json'],
        await File('docs/ep-027/diccionario-v1.json').readAsBytes(),
      );
      final paths = <String>[];
      for (final entry in manifest['files'] as List<dynamic>) {
        final path = entry['path'] as String;
        paths.add(path);
        final bytes = files[path]!;
        expect(entry['sha256'], sha256.convert(bytes).toString());
        expect(entry['sizeBytes'], '${bytes.length}');
        if (path.endsWith('.csv')) {
          expect(
            bytes,
            await File('docs/ep-027/ejemplos/datos/$path').readAsBytes(),
            reason: path,
          );
          final expectedManifest = jsonDecode(
            await File('docs/ep-027/ejemplos/datos/manifest.json')
                .readAsString(),
          );
          expect(
            entry['rowCount'],
            (expectedManifest['files'] as List<dynamic>).singleWhere(
              (e) => e['path'] == path,
            )['rowCount'],
          );
        } else {
          expect(entry['rowCount'], isNull);
        }
      }
      expect(paths, [...paths]..sort());
      expect(paths, isNot(contains('manifest.json')));
      expect(
        await Directory('${root.path}/sqlite/copies').list().toList(),
        isEmpty,
      );
      expect(
        await Directory('${root.path}/sqlite/local-backups').exists(),
        isFalse,
      );
    } finally {
      await result.dispose();
      await result.dispose();
    }
    expect(await exports.list().toList(), isEmpty);
  });

  test('todo histórico sin límite UI, meses vacíos con contexto y cabeceras, diciembre 9999', () async {
    final all = await prepare();
    final allFiles = _unzip(await File(all.zipPath).readAsBytes());
    expect(_counts(allFiles)['movimientos.csv'], '5');
    await all.dispose();
    for (final range in [
      ('2027-04-01', '2027-05-01'),
      ('9999-12-01', '9999-12-01'),
    ]) {
      final empty = await prepare(
        filter: DataExportFilter.months(from: range.$1, through: range.$2),
      );
      final files = _unzip(await File(empty.zipPath).readAsBytes());
      final counts = _counts(files);
      for (final path in [
        'movimientos.csv',
        'presupuestos.csv',
        'fotos.csv',
        'valores_fotos.csv',
      ]) {
        expect(counts[path], '0');
        expect(utf8.decode(files[path]!).split('\r\n').length, 2);
      }
      expect(counts['cuentas.csv'], '4');
      expect(counts['categorias.csv'], '5');
      expect(files['liquidez_cuentas.csv'], allFiles['liquidez_cuentas.csv']);
      await empty.dispose();
    }
    expect(
      () => DataExportFilter.months(from: '2026-02-01', through: '2026-01-01'),
      throwsArgumentError,
    );
    expect(
      () => DataExportFilter.months(from: '2026-02-02', through: '2026-03-01'),
      throwsArgumentError,
    );
    expect(
      () => DataExportFilter.months(from: '0000-01-01', through: '2026-03-01'),
      throwsArgumentError,
    );
  });

  test(
    'cambio de generación tras captura no mezcla revisión ni archivos',
    () async {
      final source = _HookSource(
        store,
        after: (backup) async {
          // Simula instalar otra generación después de terminar VACUUM INTO.
          await store.close();
          final db = sqlite3.open(activePath);
          try {
            db.execute(
              "UPDATE database_state SET dataset_id='27000000-0000-4000-8000-000000000999', revision=15",
            );
            db.execute(
              "UPDATE movements SET concept='Generación posterior',amount_cents=7654321",
            );
            db.execute("UPDATE accounts SET name='Nombre posterior'");
          } finally {
            db.close();
          }
        },
      );
      final result =
          await CsvDataExporter(
            source: SqliteDataExportSource(source),
            temporaryDirectory: () async => exports,
          ).prepare(
            filter: DataExportFilter.months(
              from: '2026-01-01',
              through: '2026-03-01',
            ),
            cancellation: DataExportCancellation(),
          );
      final files = _unzip(await File(result.zipPath).readAsBytes());
      expect(source.calls, 1);
      expect(result.state.revision, 9223372036854775807);
      expect(result.state.datasetId, tables['database_state'][0]['dataset_id']);
      for (final path in [
        'movimientos.csv',
        'cuentas.csv',
        'presupuestos.csv',
        'fotos.csv',
      ]) {
        expect(
          files[path],
          await File('docs/ep-027/ejemplos/datos/$path').readAsBytes(),
        );
      }
      final current = await (await store.open()).readState();
      expect(current.revision, 15);
      expect(current.datasetId, isNot(result.state.datasetId));
      await result.dispose();
    },
  );

  test('volumen supera paginación, duplicados legítimos y cancelación no alteran base', () async {
    final seed = sqlite3.open(activePath);
    try {
      seed.execute('BEGIN');
      final statement = seed.prepare(
        'INSERT INTO movements(id,account_id,value_date,concept,amount_cents,created_at,updated_at) VALUES (?,?,?,?,?,?,?)',
      );
      for (var i = 0; i < 4097; i++) {
        statement.execute([
          '28000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
          tables['accounts'][0]['id'],
          '2026-01-31',
          'Duplicado legítimo',
          -101,
          '2026-10-16T12:00:00.000Z',
          '2026-10-16T12:00:00.000Z',
        ]);
      }
      statement.close();
      seed.execute('COMMIT');
    } finally {
      seed.close();
    }
    final result = await prepare();
    final files = _unzip(await File(result.zipPath).readAsBytes());
    expect(_counts(files)['movimientos.csv'], '4102');
    expect(
      'Duplicado legítimo'
          .allMatches(utf8.decode(files['movimientos.csv']!))
          .length,
      4097,
    );
    await result.dispose();
    final before = await File(activePath).readAsBytes();
    final token = DataExportCancellation();
    await expectLater(
      prepare(
        cancellation: token,
        onProgress: (file, rows) {
          if (file == 'movimientos.csv' && rows >= 256) token.cancel();
        },
      ),
      throwsA(
        isA<DataExportFailure>().having(
          (e) => e.code,
          'cancelled',
          DataExportFailureCode.cancelled,
        ),
      ),
    );
    expect(await File(activePath).readAsBytes(), before);
    expect(await exports.list().toList(), isEmpty);
    expect(
      await Directory('${root.path}/sqlite/copies').list().toList(),
      isEmpty,
    );
  });

  test('cancelación previa, límites y errores de almacenamiento conservan temporales ajenos', () async {
    final sentinel = File('${exports.path}/ajeno.txt');
    await sentinel.writeAsString('conservar');
    final before = await File(activePath).readAsBytes();
    await expectLater(
      prepare(cancellation: DataExportCancellation()..cancel()),
      throwsA(isA<DataExportFailure>()),
    );
    for (final exporter in [
      CsvDataExporter(
        source: SqliteDataExportSource(store),
        temporaryDirectory: () async => exports,
        maxRows: 2,
      ),
      CsvDataExporter(
        source: SqliteDataExportSource(store),
        temporaryDirectory: () async => exports,
        maxBytes: 32,
      ),
      CsvDataExporter(
        source: SqliteDataExportSource(store),
        temporaryDirectory: () async =>
            throw const FileSystemException('sensible'),
      ),
    ]) {
      await expectLater(
        exporter.prepare(
          filter: const DataExportFilter.all(),
          cancellation: DataExportCancellation(),
        ),
        throwsA(isA<DataExportFailure>()),
      );
    }
    await expectLater(
      prepare(onProgress: (_, _) => throw StateError('concepto privado')),
      throwsA(
        isA<DataExportFailure>().having(
          (e) => e.toString(),
          'sin valores',
          isNot(contains('privado')),
        ),
      ),
    );
    expect(await File(activePath).readAsBytes(), before);
    expect(await sentinel.readAsString(), 'conservar');
    expect((await exports.list().toList()).length, 1);
  });

  test(
    'dos exportaciones simultáneas: cancelar una conserva el ZIP de la otra',
    () async {
      final token = DataExportCancellation();
      final results = await Future.wait<Object?>([
        expectLater(
          prepare(cancellation: token, onProgress: (_, _) => token.cancel()),
          throwsA(
            isA<DataExportFailure>().having(
              (e) => e.code,
              'cancelled',
              DataExportFailureCode.cancelled,
            ),
          ),
        ),
        prepare(),
      ]);
      final result = results[1]! as PreparedDataExport;
      final files = _unzip(await File(result.zipPath).readAsBytes());
      expect(_counts(files)['movimientos.csv'], '5');
      expect((await exports.list().toList()).length, 1);
      await result.dispose();
      expect(await exports.list().toList(), isEmpty);
      expect(
        await Directory('${root.path}/sqlite/copies').list().toList(),
        isEmpty,
      );
    },
  );

  test('ruta activa no se adopta ni se elimina como temporal', () async {
    final state = await (await store.open()).readState();
    final before = await File(activePath).readAsBytes();
    final exporter = CsvDataExporter(
      source: SqliteDataExportSource(
        _FixedSource(LocalBackup(path: activePath, state: state)),
      ),
      temporaryDirectory: () async => exports,
    );
    await expectLater(
      exporter.prepare(
        filter: const DataExportFilter.all(),
        cancellation: DataExportCancellation(),
      ),
      throwsA(isA<DataExportFailure>()),
    );
    expect(await File(activePath).readAsBytes(), before);
    expect(await exports.list().toList(), isEmpty);
  });

  test(
    'mes final diciembre 9999 incluye el último día sin desbordar',
    () async {
      final db = sqlite3.open(activePath);
      try {
        db.execute(
          'INSERT INTO movements(id,account_id,value_date,concept,amount_cents,created_at,updated_at) VALUES (?,?,?,?,?,?,?)',
          [
            '29000000-0000-4000-8000-000000000001',
            tables['accounts'][0]['id'],
            '9999-12-31',
            'Último día sintético',
            1,
            '2026-10-16T12:00:00.000Z',
            '2026-10-16T12:00:00.000Z',
          ],
        );
      } finally {
        db.close();
      }
      final result = await prepare(
        filter: DataExportFilter.months(
          from: '9999-12-01',
          through: '9999-12-01',
        ),
      );
      final files = _unzip(await File(result.zipPath).readAsBytes());
      expect(_counts(files)['movimientos.csv'], '1');
      expect(
        utf8.decode(files['movimientos.csv']!),
        contains('"9999-12-31";"Último día sintético";"0.01"'),
      );
      await result.dispose();
    },
  );

  test(
    'base nueva sin datos produce los siete CSV solo con cabeceras',
    () async {
      final empty = LocalDatabaseStore(
        supportDirectory: () async => Directory('${root.path}/empty'),
      );
      try {
        await Directory('${root.path}/empty').create();
        final result =
            await createDataExporter(
              store: empty,
              temporaryDirectory: () async => exports,
            ).prepare(
              filter: const DataExportFilter.all(),
              cancellation: DataExportCancellation(),
            );
        final files = _unzip(await File(result.zipPath).readAsBytes());
        final counts = _counts(files);
        expect(counts.values.whereType<String>(), everyElement('0'));
        expect(counts.values.whereType<String>().length, 7);
        for (final entry in files.entries.where(
          (e) => e.key.endsWith('.csv'),
        )) {
          expect(utf8.decode(entry.value).split('\r\n').length, 2);
        }
        await result.dispose();
      } finally {
        await empty.close();
      }
    },
  );

  test('imagen con revisión declarada falsa se rechaza y limpia', () async {
    final source = _HookSource(store, lie: true);
    final exporter = CsvDataExporter(
      source: SqliteDataExportSource(source),
      temporaryDirectory: () async => exports,
    );
    await expectLater(
      exporter.prepare(
        filter: const DataExportFilter.all(),
        cancellation: DataExportCancellation(),
      ),
      throwsA(
        isA<DataExportFailure>().having(
          (e) => e.code,
          'invalidSnapshot',
          DataExportFailureCode.invalidSnapshot,
        ),
      ),
    );
    expect(await exports.list().toList(), isEmpty);
    expect(
      await Directory('${root.path}/sqlite/copies').list().toList(),
      isEmpty,
    );
  });

  test(
    'verificación ZIP rechaza bytes cambiados entre descripción y empaquetado',
    () async {
      final file = File('${exports.path}/fotos.csv');
      await file.writeAsString('id\r\n"a"\r\n');
      final token = DataExportCancellation();
      final descriptor = await describeExportFile(file, 'fotos.csv', token, 1);
      await file.writeAsString('id\r\n"b"\r\n');
      await expectLater(
        createAndVerifyExportZip(
          stage: exports,
          zip: File('${exports.path}/fallo.zip'),
          files: [descriptor],
          cancellation: token,
          maxBytes: 10000,
        ),
        throwsA(isA<DataExportFailure>()),
      );
    },
  );
}

Map<String, Object?> _counts(Map<String, Uint8List> files) {
  final manifest = jsonDecode(utf8.decode(files['manifest.json']!));
  return {
    for (final entry in manifest['files'] as List<dynamic>)
      entry['path'] as String: entry['rowCount'],
  };
}

// Lector de pruebas independiente del escritor: cabeceras ZIP locales y EOCD.
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
  _HookSource(this.source, {this.after, this.lie = false});
  final LocalBackupSource source;
  final Future<void> Function(LocalBackup)? after;
  final bool lie;
  int calls = 0;
  @override
  Future<LocalBackup> createConsistentBackup() async {
    calls++;
    final backup = await source.createConsistentBackup();
    await after?.call(backup);
    return lie
        ? LocalBackup(
            path: backup.path,
            state: const DatasetState(
              datasetId: '27000000-0000-4000-8000-000000000900',
              revision: 1,
            ),
          )
        : backup;
  }
}
