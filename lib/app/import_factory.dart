import '../features/importing/importing.dart';
import '../features/importing/presentation/import_controller.dart';
import 'data/sqlite/local_database.dart';
import 'data/sqlite/sqlite_import_batch_repository.dart';
import 'data/sqlite/sqlite_import_history_repository.dart';
import 'data/sqlite/sqlite_import_preview_source.dart';

ImportServices createImportServices(
  LocalDatabase database, {
  void Function()? onConfirmed,
}) {
  final source = SqliteImportPreviewSource(database);
  return ImportServices(
    source: source,
    previewer: ValidatingImportPreviewer(source),
    confirmer: _NotifyingConfirmer(
      SqliteImportBatchRepository(database),
      onConfirmed,
    ),
    history: SqliteImportHistoryRepository(database),
  );
}

class _NotifyingConfirmer implements ImportConfirmer {
  const _NotifyingConfirmer(this.inner, this.onConfirmed);
  final ImportConfirmer inner;
  final void Function()? onConfirmed;
  @override
  Future<ImportConfirmationResult> confirm(
    ImportConfirmationRequest request,
  ) async {
    final result = await inner.confirm(request);
    if (result is ImportConfirmed) {
      // La invalidación ocurre después del commit. Un fallo del observador no
      // puede convertir una carga confirmada en un error de persistencia.
      try {
        onConfirmed?.call();
      } catch (_) {
        /* El resultado SQLite prevalece. */
      }
    }
    return result;
  }
}
