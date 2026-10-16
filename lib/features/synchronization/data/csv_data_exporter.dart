import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../../core/persistence/unit_of_work.dart';
import '../domain/data_export.dart';
import 'data_export_zip.dart';
import 'export_dictionary_v1.dart';

/// Produce únicamente un ZIP privado verificado. No decide dónde guardarlo.
final class CsvDataExporter implements DataExporter {
  CsvDataExporter({
    required this.source,
    Future<Directory> Function()? temporaryDirectory,
    this.maxBytes = 1024 * 1024 * 1024,
    this.maxRows = 10000000,
  }) : temporaryDirectory =
           temporaryDirectory ?? (() async => Directory.systemTemp) {
    if (maxBytes <= 0 || maxBytes > 0xffffffff || maxRows <= 0) {
      throw ArgumentError('Límites de exportación inválidos.');
    }
  }
  final DataExportSource source;
  final Future<Directory> Function() temporaryDirectory;
  final int maxBytes;
  final int maxRows;

  @override
  Future<PreparedDataExport> prepare({
    required DataExportFilter filter,
    required DataExportCancellation cancellation,
    void Function(String file, int rowCount)? onProgress,
  }) async {
    DataExportCapture? capture;
    Directory? stage;
    try {
      cancellation.check();
      stage = await (await temporaryDirectory()).createTemp(
        'autofinance-export-',
      );
      capture = await source.capture();
      cancellation.check();
      final state = capture.state;
      final exportId = const Uuid().v4();
      final dictionary = jsonDecode(exportDictionaryV1) as Map<String, dynamic>;
      final files = <ExportZipFile>[];
      var totalBytes = 0;
      var totalRows = 0;
      for (final definition in dictionary['files'] as List<dynamic>) {
        cancellation.check();
        final path = definition['path'] as String;
        final columns = definition['columns'] as List<dynamic>;
        final file = File('${stage.path}/$path');
        final output = await file.open(mode: FileMode.writeOnly);
        var rows = 0;
        try {
          final header = utf8.encode(
            '${columns.map((c) => c['name']).join(';')}\r\n',
          );
          totalBytes += header.length;
          _limit(totalBytes <= maxBytes);
          await output.writeFrom(header);
          await for (final row in capture.rows(path, filter)) {
            cancellation.check();
            _limit(++totalRows <= maxRows);
            if (row.length != columns.length) {
              throw const DataExportFailure(
                DataExportFailureCode.invalidSnapshot,
              );
            }
            final cells = <String>[];
            for (var i = 0; i < row.length; i++) {
              final value = row[i];
              if (value == null && columns[i]['nullable'] != true) {
                throw const DataExportFailure(
                  DataExportFailureCode.invalidSnapshot,
                );
              }
              final type = columns[i]['type'];
              final text = value == null
                  ? null
                  : type == 'eur' || type == 'eurNonNegative'
                  ? _euros(value as int)
                  : value.toString();
              cells.add(text == null ? '' : '"${text.replaceAll('"', '""')}"');
            }
            final bytes = utf8.encode('${cells.join(';')}\r\n');
            totalBytes += bytes.length;
            _limit(totalBytes <= maxBytes);
            await output.writeFrom(bytes);
            rows++;
            if (rows % 128 == 0) onProgress?.call(path, rows);
          }
          await output.flush();
        } finally {
          await output.close();
        }
        files.add(await describeExportFile(file, path, cancellation, rows));
        onProgress?.call(path, rows);
      }
      for (final entry in {
        'diccionario.json': exportDictionaryV1,
        'LEEME.md': _readme,
      }.entries) {
        cancellation.check();
        totalBytes += utf8.encode(entry.value).length;
        _limit(totalBytes <= maxBytes);
        final file = File('${stage.path}/${entry.key}');
        await file.writeAsString(entry.value, flush: true);
        files.add(
          await describeExportFile(file, entry.key, cancellation, null),
        );
      }
      files.sort((a, b) => a.path.compareTo(b.path));
      final instant = capture.createdAtUtc.toUtc();
      final utc =
          '${instant.toIso8601String().split('.').first}.${instant.millisecond.toString().padLeft(3, '0')}Z';
      final manifest = {
        'kind': 'autofinance.dataExport',
        'formatVersion': 1,
        'exportId': exportId,
        'createdAtUtc': utc,
        'datasetId': state.datasetId,
        'revision': '${state.revision}',
        'applicationId': capture.applicationId,
        'schemaVersion': capture.schemaVersion,
        'currency': 'EUR',
        'filter': filter.toJson(),
        'dictionary': 'diccionario.json',
        'files': files.map((f) => f.toJson()).toList(),
        'databaseTables': <Object>[],
      };
      final manifestFile = File('${stage.path}/manifest.json');
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
      files.sort((a, b) => a.path.compareTo(b.path));
      final zip = File('${stage.path}/datos.zip');
      await createAndVerifyExportZip(
        stage: stage,
        zip: zip,
        files: files,
        cancellation: cancellation,
        maxBytes: maxBytes,
      );
      // Si falla liberar la captura, tampoco se anuncia una exportación lista.
      await capture.close();
      capture = null;
      cancellation.check();
      final result = _Prepared(stage, zip.path, state, exportId);
      stage = null;
      return result;
    } on DataExportFailure {
      rethrow;
    } catch (_) {
      // No propaga rutas, SQL, conceptos, valores o excepciones con datos.
      throw const DataExportFailure(DataExportFailureCode.storage);
    } finally {
      try {
        try {
          await capture?.close();
        } finally {
          if (stage != null) await _removeStage(stage);
        }
      } catch (_) {
        throw const DataExportFailure(DataExportFailureCode.storage);
      }
    }
  }
}

void _limit(bool valid) {
  if (!valid) {
    throw const DataExportFailure(DataExportFailureCode.limitExceeded);
  }
}

/// BigInt evita abs(minInt64), sin double ni redondeo intermedio.
String _euros(int cents) {
  final n = BigInt.from(cents);
  final magnitude = n.abs();
  return '${n.isNegative ? '-' : ''}${magnitude ~/ BigInt.from(100)}.${(magnitude % BigInt.from(100)).toString().padLeft(2, '0')}';
}

Future<void> _removeStage(Directory directory) async {
  // Solo archivos inmediatos del directorio exclusivo creado con createTemp.
  // Un contenido inesperado no autoriza recorrer o borrar otro directorio.
  await for (final file in directory.list(followLinks: false)) {
    if (file is File) await file.delete();
  }
  await directory.delete();
}

final class _Prepared implements PreparedDataExport {
  _Prepared(this.directory, this.zipPath, this.state, this.exportId);
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

const _readme = '''# Exportación de datos Autofinance v1

Consulte manifest.json para el ámbito: todo el histórico o meses completos
inclusivos. Movimientos por fecha de valor; presupuestos y fotos por mes.
cuentas.csv, categorias.csv y liquidez_cuentas.csv contienen TODOS los catálogos,
incluidos archivados y bajas, y contexto anterior/posterior al rango.
Revise ese contexto antes de compartir. Todos los archivos son de la misma
revisión datasetId/revision. Verifique inventario, tamaño y SHA-256 de los bytes
descomprimidos contra manifest.json; sus hashes no autentican al autor.

Abra primero en editor de texto o importe desde la herramienta de texto/CSV:
UTF-8, separador ; y calificador ". Desactive fórmulas y detección de tipos y
fije TODAS las columnas como Texto ANTES de cargar. No abra con doble clic.
Las comillas CSV no impiden ejecutar fórmulas. Si la herramienta no garantiza
que no evalúa fórmulas, use un editor/lector CSV que no las evalúe.
UUID, fechas y números grandes también son Texto. Convierta importes después
solo con decimal exacto o céntimos enteros, nunca coma flotante.

Null es campo vacío SIN comillas; cadena vacía es "". Use un lector sensible a
comillas para analizar ausencia; una hoja que las colapsa solo permite consulta
visual. Se preservan texto, Unicode y CR/LF internos. Cada registro termina CRLF.
diccionario.json define columnas, claves, referencias y orden. Los identificadores
de procedencia son opacos; no hay extractos originales en estos CSV.

Los signos coinciden con la app: NO se invierte el presupuesto. Cero explícito
no equivale a ausencia. Sin cabecera no hay fila de foto; cabecera sin valores
es absent, con pendientes incomplete, en otro caso complete. Los saldos son
manuales del día 1, jamás calculados desde movimientos. No hay subtotales de
fotos incompletas, ni filas de relleno. Deudas conservan magnitud positiva.
Las cuentas tienen alta/baja inclusivas; liquidez tiene fin exclusivo.

Este formato difiere del CSV histórico EP-013. No permite reimportar,
reconstruir desde CSV ni restaurar una instalación. Para consulta SQLite
independiente use la acción separada «Exportar copia completa», sin rango.
''';
