import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as p;

import '../../../core/persistence/unit_of_work.dart';
import '../../../features/synchronization/synchronization.dart';
import 'schema_policy.dart';

/// Reutiliza la captura EP-004; no lee la activa ni crea un segundo snapshot.
final class SqliteDataExportSource implements DataExportSource {
  const SqliteDataExportSource(this.source);
  final LocalBackupSource source;

  @override
  Future<DataExportCapture> capture() async {
    final backup = await source.createConsistentBackup();
    // Solo adoptamos el temporal nuevo del proveedor EP-004. Una ruta activa,
    // privada o enlazada nunca autoriza lectura ni eliminación.
    final file = File(backup.path);
    if (p.basename(file.path) != 'autofinance.sqlite' ||
        !RegExp(r'^snapshot-[A-Za-z0-9_-]+$')
            .hasMatch(p.basename(file.parent.path)) ||
        p.basename(file.parent.parent.path) != 'copies' ||
        await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        !p.equals(
          p.normalize(await file.resolveSymbolicLinks()),
          p.normalize(file.absolute.path),
        )) {
      throw const DataExportFailure(DataExportFailureCode.invalidSnapshot);
    }
    Database? image;
    try {
      for (final suffix in ['-wal', '-shm', '-journal']) {
        if (await FileSystemEntity.type(
              '${backup.path}$suffix',
              followLinks: false,
            ) !=
            FileSystemEntityType.notFound) {
          throw const DataExportFailure(DataExportFailureCode.invalidSnapshot);
        }
      }
      image = sqlite3.open(backup.path, mode: OpenMode.readOnly);
      validateExistingDatabase(image);
      final version = readSchemaVersion(image);
      final row = image
          .select(
            'SELECT dataset_id,revision FROM database_state WHERE singleton=1',
          )
          .single;
      if (version != localSchemaVersion ||
          row['dataset_id'] != backup.state.datasetId ||
          row['revision'] != backup.state.revision) {
        throw const DataExportFailure(DataExportFailureCode.invalidSnapshot);
      }
      // SQLite puede ordenar en disco; la caché no crece con el histórico.
      image.execute(
        'PRAGMA cache_size=-2048; PRAGMA temp_store=FILE; PRAGMA query_only=ON',
      );
      return _Capture(image, backup, version, DateTime.now().toUtc());
    } catch (_) {
      image?.close();
      await _removeImage(backup.path);
      throw const DataExportFailure(DataExportFailureCode.invalidSnapshot);
    }
  }
}

Future<void> _removeImage(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
  // Nunca borra recursivamente el catálogo ni otros archivos del proveedor.
  if (await file.parent.exists() &&
      await file.parent.list(followLinks: false).isEmpty) {
    await file.parent.delete();
  }
}

final class _Capture implements DataExportCapture {
  _Capture(this.db, this.backup, this.schemaVersion, this.createdAtUtc);
  final Database db;
  final LocalBackup backup;
  bool _closed = false;
  @override
  DatasetState get state => backup.state;
  @override
  int get applicationId => localApplicationId;
  @override
  final int schemaVersion;
  @override
  final DateTime createdAtUtc;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    db.close();
    await _removeImage(backup.path);
  }

  @override
  Stream<List<Object?>> rows(String csvPath, DataExportFilter filter) async* {
    final (sql, date) = switch (csvPath) {
      'movimientos.csv' => (_movements, 'm.value_date'),
      'presupuestos.csv' => (_budgets, 'm.month'),
      'fotos.csv' => (_photos, 's.month'),
      'valores_fotos.csv' => (_values, 's.month'),
      'cuentas.csv' => (_accounts, null),
      'categorias.csv' => (_categories, null),
      'liquidez_cuentas.csv' => (_liquidity, null),
      _ => throw ArgumentError.value(csvPath),
    };
    // Límite superior textual: incluye diciembre 9999 sin calcular año 10000.
    final bounded = date != null && filter.fromMonth != null;
    final where = bounded ? 'WHERE $date >= ? AND $date <= ?' : '';
    final parameters = bounded
        ? <Object?>[
            filter.fromMonth,
            '${filter.throughMonth!.substring(0, 7)}-31',
          ]
        : <Object?>[];
    final stmt = db.prepare(sql.replaceFirst('/*filter*/', where));
    try {
      var processed = 0;
      final cursor = stmt.iterateWith(StatementParameters(parameters));
      while (cursor.moveNext()) {
        final row = cursor.current;
        if (csvPath == 'categorias.csv') {
          final nodes = [
            row,
            if (row['p_id'] != null) {'id': row['p_id'], 'name': row['p_name']},
            if (row['g_id'] != null) {'id': row['g_id'], 'name': row['g_name']},
          ].reversed.toList();
          yield [
            row['id'],
            row['parent_id'],
            row['name'],
            row['is_income'],
            row['archived'],
            nodes.first['id'],
            nodes.length,
            row['root_income'],
            jsonEncode(nodes.map((n) => n['id']).toList()),
            jsonEncode(nodes.map((n) => n['name']).toList()),
            row['created_at'],
            row['updated_at'],
          ];
        } else if (csvPath == 'fotos.csv') {
          final values = row['registered'] as int;
          final missing = row['missing'] as int;
          yield [
            row['id'],
            row['month'],
            values == 0
                ? 'absent'
                : missing > 0
                ? 'incomplete'
                : 'complete',
            row['expected'],
            values,
            missing,
            row['created_at'],
            row['updated_at'],
          ];
        } else {
          yield row.values.toList();
        }
        // Permite cancelar incluso con miles de registros en una sola consulta.
        if (++processed % 128 == 0) await Future<void>.delayed(Duration.zero);
      }
    } finally {
      stmt.close();
    }
  }
}

const _movements = '''
SELECT m.id,m.account_id,m.value_date,m.concept,m.amount_cents,m.category_id,
 CASE WHEN m.category_id IS NULL THEN 'sin_categoria' ELSE 'categorizado' END,
 m.discretion,m.import_row_id,r.batch_id,r.source_ordinal,b.source_kind,m.created_at,m.updated_at
FROM movements m LEFT JOIN import_rows r ON r.id=m.import_row_id
 LEFT JOIN import_batches b ON b.id=r.batch_id
/*filter*/ ORDER BY m.value_date COLLATE BINARY,m.id COLLATE BINARY
''';
const _budgets = '''
SELECT m.id,m.month,m.category_id,m.amount_cents,m.concept,m.discretion,
 m.import_row_id,r.batch_id,r.source_ordinal,b.source_kind,m.created_at,m.updated_at
FROM budgets m LEFT JOIN import_rows r ON r.id=m.import_row_id
 LEFT JOIN import_batches b ON b.id=r.batch_id
/*filter*/ ORDER BY m.month COLLATE BINARY,m.id COLLATE BINARY
''';
const _photos = '''
SELECT s.id,s.month,
 (SELECT count(*) FROM accounts a WHERE a.active_from<=s.month AND (a.active_through IS NULL OR a.active_through>=s.month)) expected,
 (SELECT count(*) FROM wealth_values v WHERE v.snapshot_id=s.id) registered,
 (SELECT count(*) FROM accounts a WHERE a.active_from<=s.month AND (a.active_through IS NULL OR a.active_through>=s.month)
 AND NOT EXISTS(SELECT 1 FROM wealth_values v WHERE v.snapshot_id=s.id AND v.account_id=a.id)) missing,
 s.created_at,s.updated_at
FROM wealth_snapshots s /*filter*/ ORDER BY s.month COLLATE BINARY,s.id COLLATE BINARY
''';
const _values = '''
SELECT v.id,v.snapshot_id,v.account_id,v.amount_cents,v.created_at,v.updated_at
FROM wealth_values v JOIN wealth_snapshots s ON s.id=v.snapshot_id
/*filter*/ ORDER BY v.snapshot_id COLLATE BINARY,v.account_id COLLATE BINARY,v.id COLLATE BINARY
''';
const _accounts = '''
SELECT id,name,kind,active_from,active_through,created_at,updated_at
FROM accounts ORDER BY id COLLATE BINARY
''';
const _categories = '''
SELECT c.*,p.id p_id,p.name p_name,g.id g_id,g.name g_name,
 coalesce(g.is_income,p.is_income,c.is_income) root_income
FROM categories c LEFT JOIN categories p ON p.id=c.parent_id
 LEFT JOIN categories g ON g.id=p.parent_id ORDER BY c.id COLLATE BINARY
''';
const _liquidity = '''
SELECT id,account_id,from_month,until_month,liquidity,created_at,updated_at
FROM account_liquidity_periods ORDER BY account_id COLLATE BINARY,from_month COLLATE BINARY,id COLLATE BINARY
''';
