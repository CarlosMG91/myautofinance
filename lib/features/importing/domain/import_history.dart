import '../../budget/budget.dart';
import '../../movements/movements.dart';
import 'import_batch.dart';
import 'interpreted_import.dart';

/// Continuación por identidad de inserción, nunca por desplazamiento.
final class ImportBatchCursor {
  const ImportBatchCursor(this.beforeBatchId);
  final String beforeBatchId;
}

final class ImportRowCursor {
  const ImportRowCursor(this.batchId, this.afterOrdinal);
  final String batchId;
  final int afterOrdinal;
}

final class ImportHistoryPage<T, C> {
  ImportHistoryPage(List<T> items, this.next)
    : items = List.unmodifiable(items);
  final List<T> items;
  final C? next;
}

enum ImportRecordKind { movement, budget }

/// La identidad de origen sobrevive al borrado del destino.
/// Los originales son null en lotes antiguos, nunca inferidos del dato actual.
final class ImportRowHistory {
  const ImportRowHistory({
    required this.id,
    required this.batchId,
    required this.sourceOrdinal,
    required this.kind,
    this.original,
    this.currentMovement,
    this.currentBudget,
  });
  final String id, batchId;
  final int sourceOrdinal;
  final ImportRecordKind kind;
  final InterpretedImportRow? original;
  final MovementRecord? currentMovement;
  final BudgetRecord? currentBudget;
  bool get isDeleted => currentMovement == null && currentBudget == null;
}

/// Lectura exclusiva de cargas confirmadas. No ofrece restaurar ni deshacer.
abstract interface class ImportHistoryRepository {
  /// Más recientes primero por orden de confirmación/inserción. Nuevos lotes
  /// no desplazan las páginas ya iniciadas. limit admite 1..500.
  Future<ImportHistoryPage<ImportBatch, ImportBatchCursor>> listBatches({
    int limit = 100,
    ImportBatchCursor? cursor,
  });
  Future<ImportBatch?> getBatch(String batchId);

  /// Ordinal ascendente; cursor ligado al lote. Un lote inexistente da vacío.
  Future<ImportHistoryPage<ImportRowHistory, ImportRowCursor>> listRows(
    String batchId, {
    int limit = 100,
    ImportRowCursor? cursor,
  });

  /// Permite consultar procedencia desde importRowId de un registro actual.
  Future<ImportRowHistory?> getRow(String importRowId);
}
