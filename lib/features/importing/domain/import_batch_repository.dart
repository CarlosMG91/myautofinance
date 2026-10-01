import '../../movements/movements.dart';

enum ImportSource { historicalCsv, bankXls }

final class ImportedMovement {
  const ImportedMovement(this.sourceOrdinal, this.data);
  final int sourceOrdinal;
  final MovementInput data;
}

final class ImportBatch {
  const ImportBatch({
    required this.id,
    required this.sha256,
    required this.source,
    required this.originalName,
    required this.contractVersion,
    required this.importedAt,
  });
  final String id, sha256, originalName, contractVersion, importedAt;
  final ImportSource source;
}

abstract interface class ImportBatchRepository {
  /// Recibe filas ya interpretadas. Confirma lote y movimientos atómicamente.
  Future<ImportBatch> create({
    required String sha256,
    required ImportSource source,
    required String originalName,
    required String contractVersion,
    required List<ImportedMovement> movements,
  });
  Future<ImportBatch?> getByFingerprint(String sha256);
}
