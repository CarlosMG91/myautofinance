import 'movement_repository.dart';

/// Pendientes importados. Fechas civiles [from, until); null deja abierto
/// ese extremo. Sin filtros se consultan todos los periodos y lotes.
final class PendingMovementQuery {
  PendingMovementQuery({
    this.from,
    this.until,
    this.batchId,
    this.accountId,
    this.concept = '',
  }) {
    if (from != null && until != null && from!.compareTo(until!) >= 0) {
      throw const MovementFailure('Periodo de pendientes inválido.');
    }
    for (final id in [batchId, accountId]) {
      if (id != null) MovementSelection([id]);
    }
  }

  final ValueDate? from, until;
  final String? batchId, accountId;
  final String concept;
}

/// La identidad es local a la conexión, no se serializa ni se sincroniza.
/// La revisión puede cambiar: al escribir se revalida cada UUID, sin bloquear
/// por ediciones ajenas a los pendientes seleccionados.
final class PendingMovementSelection {
  PendingMovementSelection({
    required List<String> ids,
    required this.databaseIdentity,
    required this.datasetId,
  }) : movements = MovementSelection(ids);

  final MovementSelection movements;
  final Object databaseIdentity;
  final String datasetId;
}

/// Página limitada y número de TODOS los pendientes filtrados, obtenidos
/// en el mismo snapshot de lectura. Reiniciar el cursor tras cambiar filtros,
/// escribir o reemplazar la base, como en EP-010.
final class PendingMovementPage {
  PendingMovementPage({
    required List<MovementRecord> records,
    required this.totalCount,
    required this.nextCursor,
    required this.databaseIdentity,
    required this.datasetId,
  }) : records = List.unmodifiable(records);

  final List<MovementRecord> records;
  final int totalCount;
  final MovementCursor? nextCursor;
  final Object databaseIdentity;
  final String datasetId;

  /// Captura UUID visibles explícitos; nunca amplía a resultados ocultos.
  PendingMovementSelection select(List<String> ids) {
    final selection = MovementSelection(ids);
    final visible = records.map((record) => record.id).toSet();
    if (!selection.ids.every(visible.contains)) {
      throw const MovementFailure(
        'Selecciona movimientos de la página visible.',
      );
    }
    return PendingMovementSelection(
      ids: selection.ids,
      databaseIdentity: databaseIdentity,
      datasetId: datasetId,
    );
  }

  PendingMovementSelection selectPage() =>
      select(records.map((record) => record.id).toList());
}

/// Extensión específica de Movimientos; las operaciones generales EP-010
/// mantienen su semántica de reemplazo/retirada de categorías.
abstract interface class PendingMovementRepository {
  /// Solo REAL importados con categoría NULL, recientes primero y UUID ASC.
  /// Búsqueda literal por concepto con normalización Unicode EP-010.
  Future<PendingMovementPage> readPendingPage({
    PendingMovementQuery? query,
    MovementCursor? after,
    int limit = 100,
  });

  /// Tras confirmar cantidad y categoría activa en la interfaz. Revalida base,
  /// destino y todos los UUID dentro de la transacción; si alguno desaparece,
  /// es manual o ya tiene categoría, rechaza TODO sin sobrescribir cambios.
  /// Solo modifica categoría y timestamp; revisión una vez por éxito.
  Future<void> assignPendingCategory(
    PendingMovementSelection selection,
    String categoryId,
  );
}
