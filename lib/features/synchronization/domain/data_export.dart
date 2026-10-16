import '../../../core/persistence/unit_of_work.dart';

/// Meses completos inclusivos. No hereda filtros de las pantallas.
final class DataExportFilter {
  const DataExportFilter.all() : fromMonth = null, throughMonth = null;

  DataExportFilter.months({required String from, required String through})
    : fromMonth = from,
      throughMonth = through {
    final month = RegExp(r'^(?!0000)[0-9]{4}-(0[1-9]|1[0-2])-01$');
    if (!month.hasMatch(from) ||
        !month.hasMatch(through) ||
        from.compareTo(through) > 0) {
      throw ArgumentError('Se requieren meses completos en orden inclusivo.');
    }
  }

  final String? fromMonth;
  final String? throughMonth;
  Map<String, Object?> toJson() => {
    'mode': fromMonth == null ? 'all' : 'months',
    'fromMonth': fromMonth,
    'throughMonth': throughMonth,
  };
}

final class DataExportCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
  void check() {
    if (_cancelled) {
      throw const DataExportFailure(DataExportFailureCode.cancelled);
    }
  }
}

enum DataExportFailureCode {
  cancelled,
  invalidSnapshot,
  storage,
  limitExceeded,
}

final class DataExportFailure implements Exception {
  const DataExportFailure(this.code);
  final DataExportFailureCode code;
  @override
  String toString() => 'No se completó la exportación (${code.name}).';
}

/// Lectura de UNA imagen terminada. Cada fila sigue el orden del diccionario v1.
abstract interface class DataExportCapture {
  DatasetState get state;
  int get applicationId;
  int get schemaVersion;
  DateTime get createdAtUtc;
  Stream<List<Object?>> rows(String csvPath, DataExportFilter filter);

  /// Cierra y elimina exclusivamente la imagen temporal de esta captura.
  Future<void> close();
}

abstract interface class DataExportSource {
  Future<DataExportCapture> capture();
}

/// Archivo ya verificado, todavía privado. T04 decide su destino nativo.
abstract interface class PreparedDataExport {
  String get zipPath;
  DatasetState get state;
  String get exportId;

  /// El consumidor debe liberarlo tras guardar o cancelar el destino nativo.
  Future<void> dispose();
}

abstract interface class DataExporter {
  Future<PreparedDataExport> prepare({
    required DataExportFilter filter,
    required DataExportCancellation cancellation,
    void Function(String file, int rowCount)? onProgress,
  });
}
