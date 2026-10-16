import 'package:drift/drift.dart';

import '../../../features/diagnostics/diagnostics.dart';
import 'local_database_store.dart';

/// Comprobación de existencia al abrir, sin reutilizar la conexión del informe.
final class DiagnosticReferenceReader {
  const DiagnosticReferenceReader(this.store);
  final LocalDatabaseStore store;

  Future<bool> exists(DiagnosticEntity entity, String id) async {
    final table = switch (entity) {
      DiagnosticEntity.movement => 'movements',
      DiagnosticEntity.budget => 'budgets',
      DiagnosticEntity.account => 'accounts',
      DiagnosticEntity.category => 'categories',
      DiagnosticEntity.importBatch => 'import_batches',
      DiagnosticEntity.importRow => 'import_rows',
      _ => null,
    };
    if (table == null) return false;
    final db = await store.open();
    return (await db
            .customSelect(
              'SELECT id FROM $table WHERE id = ?',
              variables: [Variable(id)],
            )
            .get())
        .isNotEmpty;
  }
}
