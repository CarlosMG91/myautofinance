import 'import_batch.dart';
import 'import_session.dart';

export 'import_batch.dart';

abstract interface class ImportBatchRepository implements ImportConfirmer {
  /// Frontera anterior para filas ya resueltas, sin originales disponibles.
  /// Los lectores nuevos deben utilizar confirm para revalidar la revisión.
  Future<ImportBatch> create({
    required String sha256,
    required ImportSource source,
    required String originalName,
    required String contractVersion,
    List<ImportedMovement> movements = const [],
    List<ImportedBudget> budgets = const [],
  });
  Future<ImportBatch?> getByFingerprint(String sha256);
}
