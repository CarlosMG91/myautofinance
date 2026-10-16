import 'data_export.dart';
import 'local_backup_creation.dart';

/// Metadatos leídos de una imagen cerrada, nunca de la base activa.
final class PortableBackupImage {
  PortableBackupImage({
    required this.database,
    required Map<String, int> tables,
  }) : tables = Map.unmodifiable(tables);

  final LocalBackupImage database;
  final Map<String, int> tables;
}

abstract interface class PortableBackupImageInspector {
  /// Valida integridad, claves, esquema y reglas con la política SQLite vigente.
  /// Solo lectura; no migra, restaura ni registra la imagen en el catálogo.
  Future<PortableBackupImage> inspect(String path);
}

abstract interface class PortableBackupExporter {
  /// Toda la base financiera, sin filtro CSV. T04 guarda y libera el preparado.
  Future<PreparedDataExport> prepare({
    required DataExportCancellation cancellation,
  });
}
