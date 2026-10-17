import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/persistence/local_database_format.dart';
import '../../../core/persistence/unit_of_work.dart';
import '../domain/data_export.dart';
import '../domain/local_backup.dart';
import '../domain/portable_backup_export.dart';
import 'data_export_zip.dart';

/// Exportación explícita. EP-004 es el único propietario del snapshot;
/// no usa LocalBackupCreator, catálogo privado, restaurador ni retención.
final class PortableSqliteBackupExporter implements PortableBackupExporter {
  PortableSqliteBackupExporter({
    required this.source,
    required this.inspector,
    Future<Directory> Function()? temporaryDirectory,
    this.maxBytes = 1024 * 1024 * 1024,
  }) : temporaryDirectory =
           temporaryDirectory ?? (() async => Directory.systemTemp) {
    if (maxBytes <= 0 || maxBytes > 0xffffffff) {
      throw ArgumentError('Límite de exportación inválido.');
    }
  }

  final LocalBackupSource source;
  final PortableBackupImageInspector inspector;
  final Future<Directory> Function() temporaryDirectory;

  /// Límite del ZIP estándar completo; no se genera ZIP64 ni se trunca.
  final int maxBytes;

  @override
  Future<PreparedDataExport> prepare({
    required DataExportCancellation cancellation,
  }) async {
    Directory? stage;
    File? snapshot;
    try {
      cancellation.check();
      stage = await (await temporaryDirectory()).createTemp(
        'autofinance-portable-',
      );
      final backup = await source.createConsistentBackup();
      final capturedAt = DateTime.now().toUtc();
      // Adoptar solo el temporal nuevo de EP-004, nunca una activa/copia privada.
      final candidate = File(backup.path).absolute;
      if (p.basename(candidate.path) != 'autofinance.sqlite' ||
          !RegExp(r'^snapshot-[A-Za-z0-9_-]+$')
              .hasMatch(p.basename(candidate.parent.path)) ||
          p.basename(candidate.parent.parent.path) != 'copies' ||
          await FileSystemEntity.type(candidate.path, followLinks: false) !=
              FileSystemEntityType.file ||
          !p.equals(
            p.normalize(await candidate.resolveSymbolicLinks()),
            p.normalize(candidate.path),
          )) {
        _invalid();
      }
      snapshot = candidate;
      cancellation.check();
      final size = await snapshot.length();
      if (size <= 0) _invalid();
      if (size > maxBytes) _limit();
      final original = await describeExportFile(
        snapshot,
        'autofinance.sqlite',
        cancellation,
        null,
      );
      final image = await inspector.inspect(snapshot.path);
      _checkState(image, backup.state);
      cancellation.check();

      // Copia por bloques de la imagen cerrada, jamás del archivo principal vivo.
      final sqlite = File(p.join(stage.path, 'autofinance.sqlite'));
      final output = await sqlite.open(mode: FileMode.writeOnly);
      try {
        var copied = 0;
        await for (final bytes in snapshot.openRead()) {
          cancellation.check();
          copied += bytes.length;
          if (copied > maxBytes) _limit();
          await output.writeFrom(bytes);
        }
        await output.flush();
      } finally {
        await output.close();
      }
      final descriptor = await describeExportFile(
        sqlite,
        'autofinance.sqlite',
        cancellation,
        null,
      );
      if (descriptor.size != original.size || descriptor.sha != original.sha) {
        _invalid();
      }
      final stagedImage = await inspector.inspect(sqlite.path);
      _checkState(stagedImage, image.database.state);
      if (stagedImage.database.applicationId != image.database.applicationId ||
          stagedImage.database.schemaVersion != image.database.schemaVersion ||
          stagedImage.tables.length != image.tables.length ||
          image.tables.entries.any(
            (e) => stagedImage.tables[e.key] != e.value,
          )) {
        _invalid();
      }

      final readme = File(p.join(stage.path, 'LEEME.md'));
      await readme.writeAsString(portableBackupReadmeV1, flush: true);
      final files = [
        await describeExportFile(readme, 'LEEME.md', cancellation, null),
        descriptor,
      ];
      final exportId = const Uuid().v4();
      final names = image.tables.keys.toList()..sort();
      final manifest = {
        'kind': 'autofinance.portableBackup',
        'formatVersion': 1,
        'exportId': exportId,
        'createdAtUtc':
            '${capturedAt.toIso8601String().split('.').first}.${capturedAt.millisecond.toString().padLeft(3, '0')}Z',
        'datasetId': image.database.state.datasetId,
        'revision': '${image.database.state.revision}',
        'applicationId': image.database.applicationId,
        'schemaVersion': image.database.schemaVersion,
        'currency': 'EUR',
        'filter': null,
        'dictionary': null,
        'files': files.map((f) => f.toJson()).toList(),
        'databaseTables': [
          for (final name in names)
            {'name': name, 'rowCount': '${image.tables[name]}'},
        ],
      };
      final manifestFile = File(p.join(stage.path, 'manifest.json'));
      await manifestFile.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
        flush: true,
      );
      files.add(
        await describeExportFile(
          manifestFile,
          'manifest.json',
          cancellation,
          null,
        ),
      );
      // También detecta cambios de bytes durante/después de la validación SQLite.
      final zip = File(p.join(stage.path, 'copia-completa.zip'));
      await createAndVerifyExportZip(
        stage: stage,
        zip: zip,
        files: files,
        cancellation: cancellation,
        maxBytes: maxBytes,
      );
      await _removeSnapshot(snapshot);
      snapshot = null;
      cancellation.check();
      final result = _Prepared(
        stage,
        zip.path,
        image.database.state,
        exportId,
        DateTime.fromMillisecondsSinceEpoch(
          capturedAt.millisecondsSinceEpoch,
          isUtc: true,
        ),
      );
      stage = null;
      return result;
    } on DataExportFailure {
      rethrow;
    } catch (_) {
      // No filtra rutas privadas, SQL, conceptos ni errores con datos personales.
      throw const DataExportFailure(DataExportFailureCode.storage);
    } finally {
      try {
        try {
          if (snapshot != null) await _removeSnapshot(snapshot);
        } finally {
          if (stage != null) await _removeStage(stage);
        }
      } catch (_) {
        throw const DataExportFailure(DataExportFailureCode.storage);
      }
    }
  }
}

void _checkState(PortableBackupImage image, DatasetState expected) {
  if (image.database.state.datasetId != expected.datasetId ||
      image.database.state.revision != expected.revision ||
      image.database.schemaVersion != localSchemaVersion ||
      image.database.applicationId != localApplicationId ||
      image.tables.isEmpty ||
      image.tables.entries.any(
        (e) => !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(e.key) || e.value < 0,
      )) {
    _invalid();
  }
}

Never _invalid() =>
    throw const DataExportFailure(DataExportFailureCode.invalidSnapshot);
Never _limit() =>
    throw const DataExportFailure(DataExportFailureCode.limitExceeded);

Future<void> _removeSnapshot(File snapshot) async {
  // Solo el archivo adoptado y sidecars conocidos de SU temporal, sin recursión.
  for (final suffix in ['', '-wal', '-shm', '-journal']) {
    final file = File('${snapshot.path}$suffix');
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.file) {
      await file.delete();
    }
  }
  if (await snapshot.parent.exists() &&
      await snapshot.parent.list(followLinks: false).isEmpty) {
    await snapshot.parent.delete();
  }
}

Future<void> _removeStage(Directory directory) async {
  // Exclusivamente el directorio creado con createTemp; no sigue enlaces.
  await for (final file in directory.list(followLinks: false)) {
    if (file is File) await file.delete();
  }
  await directory.delete();
}

final class _Prepared implements PreparedDataExport {
  _Prepared(
    this.directory,
    this.zipPath,
    this.state,
    this.exportId,
    this.createdAtUtc,
  );
  @override
  final DateTime createdAtUtc;
  final Directory directory;
  bool _disposed = false;
  @override
  final String zipPath;
  @override
  final DatasetState state;
  @override
  final String exportId;
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    try {
      await _removeStage(directory);
      _disposed = true;
    } catch (_) {
      throw const DataExportFailure(DataExportFailureCode.storage);
    }
  }
}

const portableBackupReadmeV1 = '''# Copia financiera portable Autofinance v1

Esta copia contiene TODA la base financiera sin filtro temporal, incluso datos
fuera de cualquier rango CSV: catálogos, liquidez histórica, movimientos,
presupuestos, fotos manuales y trazabilidad de importaciones persistida
(incluidos originales por fila). Revise su contenido antes de compartir.
No contiene sesión, OAuth/tokens, credenciales, configuración de instalación,
estado Drive ni extractos originales completos no almacenados en la base.

Contenido exacto del ZIP: autofinance.sqlite, manifest.json y este LEEME.md.
El manifiesto público v1 es JSON UTF-8 directo, sin el sobre de copias privadas.
Describe datasetId/revision, applicationId/schemaVersion, tablas y conteos.
revision, rowCount y sizeBytes son cadenas decimales exactas, no coma flotante.
filter y dictionary son null: la copia SQLite es completa e independiente de CSV.
El diccionario de esquema está en sqlite_schema: tablas/columnas, restricciones,
índices y triggers se conservan íntegros dentro de la imagen.

Recuperación para CONSULTA en Windows, también de una copia creada en Android:
1. Conserve el ZIP original. Cree una carpeta NUEVA y vacía, fuera de la
   instalación Autofinance. No extraiga sobre una base ni sobre copias previas.
2. Antes de extraer valide el inventario: exactamente los tres nombres literales
   anteriores, archivos regulares, sin enlaces, duplicados (también por
   mayúsculas), directorios, rutas absolutas, unidades, barras inversas o '..'.
   Rechace ZIP incompletos y versiones/kinds desconocidos. Aplique límites de
   tamaño y no acepte tamaños descomprimidos distintos de los declarados.
3. Compruebe manifest.json: kind=autofinance.portableBackup, formatVersion=1,
   EUR, filter=null, dictionary=null. files lista exactamente LEEME.md y
   autofinance.sqlite. Compare tamaño y SHA-256 de TODOS los bytes descomprimidos
   con sizeBytes/sha256 de cada archivo, sin reserializar. El manifiesto no se
   auto-hashea. SHA-256 detecta corrupción; NO autentica autoría ni impide que
   alguien cambie conjuntamente datos y manifiesto. No hay cifrado adicional.
4. Extraiga solo a esa carpeta nueva. Abra con SQLite estándar en solo lectura,
   por ejemplo desde sqlite3 CLI: sqlite3 -readonly autofinance.sqlite
   No necesita Autofinance, root Android, WAL/SHM/journal, migraciones ni
   funciones de búsqueda de la app para SELECT directos.
5. Ejecute PRAGMA integrity_check; (debe devolver ok), PRAGMA foreign_key_check;
   (sin filas), PRAGMA application_id; y PRAGMA user_version;. Compare los dos
   últimos con applicationId/schemaVersion. Ejecute:
   SELECT dataset_id, revision FROM database_state WHERE singleton=1;
   Compare identidad/revisión y todos los conteos con databaseTables; por
   ejemplo SELECT count(*) FROM movements;. No continúe si hay discrepancias.

Consulta del esquema sin Autofinance:
SELECT type,name,sql FROM sqlite_schema WHERE name NOT GLOB 'sqlite_*';
PRAGMA table_info(movements);
PRAGMA foreign_key_list(movements);
SELECT id,value_date,amount_cents,concept FROM movements ORDER BY value_date,id;

Los importes INTEGER son céntimos EUR exactos, con los signos de la aplicación.
No use coma flotante para convertirlos. Presupuestos son distintos de reales y
no invierten signo como el CSV histórico EP-013. Los saldos/fotos son manuales
del día 1; no se calculan desde movimientos. Sin foto completa hay «sin dato»;
ausencia no es cero. Las deudas conservan magnitud positiva en las fotos.

Consultas portables de referencia (SQLite estándar; todos los importes son
céntimos enteros). El esquema real y las relaciones están en sqlite_schema,
table_info y foreign_key_list de ESTA base; user_version del manifiesto es la
versión que debe contrastarse. No se convierta amount_cents a REAL.

Movimientos reales y presupuestos son tablas distintas. El presupuesto conserva
su signo interno y puede ser cero; no se invierte como CSV histórico EP-013.
Categoría real NULL significa sin clasificar. Ingreso se lee de la raíz, no del
signo:

SELECT m.id,m.value_date,m.concept,m.amount_cents,m.category_id,c.name,a.name
FROM movements m JOIN accounts a ON a.id=m.account_id
LEFT JOIN categories c ON c.id=m.category_id ORDER BY m.value_date,m.id;

WITH RECURSIVE roots(id,root_id,is_income) AS (
 SELECT id,id,is_income FROM categories WHERE parent_id IS NULL
 UNION ALL SELECT c.id,r.root_id,r.is_income FROM categories c JOIN roots r ON c.parent_id=r.id
) SELECT b.month,b.amount_cents,c.name,root.name,r.is_income
FROM budgets b JOIN categories c ON c.id=b.category_id JOIN roots r ON r.id=c.id
JOIN categories root ON root.id=r.root_id ORDER BY b.month,b.id;

Categorías y antecesores, sin sumar una misma partida varias veces:

WITH RECURSIVE tree(id,parent_id,name,is_income,depth,path) AS (
 SELECT id,parent_id,name,is_income,1,name FROM categories WHERE parent_id IS NULL
 UNION ALL SELECT c.id,c.parent_id,c.name,t.is_income,t.depth+1,t.path||' / '||c.name
 FROM categories c JOIN tree t ON c.parent_id=t.id
) SELECT id,parent_id,path,depth,is_income FROM tree ORDER BY path,id;

Foto del día 1: no se deriva de movimientos ni se arrastra al mes siguiente.
Una cabecera sin valores es absent; valores faltantes para cuentas vigentes es
incomplete; todos los valores esperados, incluso cero, es complete. Un mes sin
cabecera no es cero. La consulta incluye cuentas esperadas, conteo y estado:

WITH expected AS (
 SELECT s.id snapshot_id,s.month,a.id account_id
 FROM wealth_snapshots s JOIN accounts a ON a.active_from<=s.month
 AND (a.active_through IS NULL OR a.active_through>=s.month)
), status AS (
 SELECT s.id,s.month,count(e.account_id) expected,count(v.id) registered,
 CASE WHEN count(v.id)=0 THEN 'absent'
 WHEN count(v.id)<count(e.account_id) THEN 'incomplete' ELSE 'complete' END state
 FROM wealth_snapshots s LEFT JOIN expected e ON e.snapshot_id=s.id
 LEFT JOIN wealth_values v ON v.snapshot_id=s.id AND v.account_id=e.account_id
 GROUP BY s.id,s.month
) SELECT * FROM status ORDER BY month;

Valores y liquidez histórica; desde inclusivo, hasta exclusivo y NULL abierto:

SELECT s.month,a.name,a.kind,p.liquidity,v.amount_cents
FROM wealth_snapshots s JOIN wealth_values v ON v.snapshot_id=s.id
JOIN accounts a ON a.id=v.account_id
LEFT JOIN account_liquidity_periods p ON p.account_id=a.id
AND p.from_month<=s.month AND (p.until_month IS NULL OR s.month<p.until_month)
ORDER BY s.month,a.id;

-- Cuentas vigentes pendientes en una foto: una fila ausente no es importe cero.
SELECT s.month,a.id,a.name,a.kind FROM wealth_snapshots s
JOIN accounts a ON a.active_from<=s.month
AND (a.active_through IS NULL OR a.active_through>=s.month)
LEFT JOIN wealth_values v ON v.snapshot_id=s.id AND v.account_id=a.id
WHERE v.id IS NULL ORDER BY s.month,a.id;

-- Periodo histórico de liquidez: from_month inclusivo, until_month exclusivo.
SELECT a.name,p.from_month,p.until_month,p.liquidity
FROM account_liquidity_periods p JOIN accounts a ON a.id=p.account_id
ORDER BY a.id,p.from_month,p.id;

Para reproducir EP-001 sobre la base creada con esos casos, esta consulta debe
devolver dos filas «Café» distintas (identificadas por id), que suman -2000
céntimos. Los resultados esperados del caso base son real enero 122975,
real anual 232965, presupuesto anual 1320000, activos líquidos enero 900000 y
patrimonio neto enero 1400000 céntimos. Febrero sin foto y una foto parcial son
«sin dato»; con la foto completa de la variante, activos líquidos 620000,
activos totales 1670000, deuda 480000 y patrimonio neto 1190000 céntimos.
Son resultados de la fixture EP-001, no una afirmación sobre cualquier copia.

SELECT m.id,m.value_date,m.amount_cents,m.concept,c.name
FROM movements m LEFT JOIN categories c ON c.id=m.category_id
WHERE m.value_date>='2026-01-01' AND m.value_date<'2026-02-01'
AND m.concept='Café' ORDER BY m.value_date,m.id;

-- En los casos base EP-001 hay dos filas Café, con id distinto, suma -2000.
SELECT sum(amount_cents) real_enero_cents FROM movements
WHERE value_date>='2026-01-01' AND value_date<'2026-02-01';
SELECT sum(amount_cents) real_2026_cents FROM movements
WHERE value_date>='2026-01-01' AND value_date<'2027-01-01';
SELECT sum(amount_cents) presupuesto_2026_cents FROM budgets
WHERE month>='2026-01-01' AND month<'2027-01-01';

SELECT sum(CASE WHEN a.kind<>'debt' AND p.liquidity='liquid'
                THEN v.amount_cents ELSE 0 END) activos_liquidos_cents,
       sum(CASE WHEN a.kind<>'debt' THEN v.amount_cents ELSE 0 END)
        -sum(CASE WHEN a.kind='debt' THEN v.amount_cents ELSE 0 END)
        patrimonio_neto_cents
FROM wealth_snapshots s JOIN wealth_values v ON v.snapshot_id=s.id
JOIN accounts a ON a.id=v.account_id
LEFT JOIN account_liquidity_periods p ON p.account_id=a.id
AND p.from_month<=s.month AND (p.until_month IS NULL OR s.month<p.until_month)
WHERE s.month='2026-01-01';

Esta recuperación no sustituye una instalación ni restaura su estado o Drive.
No copie la imagen sobre la base activa, no la registre como copia privada,
no la fusione ni reconstruya desde CSV. El guardado es manual, sin envío Drive.
''';
