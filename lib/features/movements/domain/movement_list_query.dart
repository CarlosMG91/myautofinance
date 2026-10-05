import 'movement_repository.dart';

/// Entrada pública para abrir reales desde Gestión o una cifra de un informe.
/// Periodo civil [from, until), categoría directa por UUID o rama actual.
final class MovementListQuery {
  MovementListQuery({
    required this.from,
    required this.until,
    this.accountId,
    this.categoryId,
    this.scope = MovementCategoryScope.branch,
    this.unclassified = false,
    this.concept = '',
  }) {
    if (until != null && from.compareTo(until!) >= 0 ||
        until == null && !from.value.startsWith('9999-') ||
        unclassified && categoryId != null) {
      throw const MovementFailure('Periodo o categoría ambiguos.');
    }
    for (final id in [accountId, categoryId]) {
      if (id != null) MovementSelection([id]);
    }
  }

  final ValueDate from;
  final ValueDate? until;
  final String? accountId, categoryId;
  final MovementCategoryScope scope;
  final bool unclassified;
  final String concept;
}
