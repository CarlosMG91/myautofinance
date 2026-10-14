import '../../movements/movements.dart';

/// Alcance de una cifra anual, independiente de consulta y presentación.
/// month null abre los doce meses; UUID null abre el total salvo unclassified.
final class AnnualActualDetail {
  AnnualActualDetail({
    required this.year,
    this.month,
    this.categoryId,
    this.unclassified = false,
    this.scope = MovementCategoryScope.branch,
  }) {
    // Delega la validación del calendario civil al contrato de EP-010.
    ValueDate(year, month ?? 1, 1);
    if (unclassified && categoryId != null) {
      throw const MovementFailure('Categoría ambigua.');
    }
    if (categoryId != null) MovementSelection([categoryId!]);
  }

  final int year;
  final int? month;
  final String? categoryId;
  final bool unclassified;
  final MovementCategoryScope scope;

  MovementListQuery get movements => MovementListQuery(
    from: ValueDate(year, month ?? 1, 1),
    until: month == null || month == 12
        ? (year == 9999 ? null : ValueDate(year + 1, 1, 1))
        : ValueDate(year, month! + 1, 1),
    categoryId: categoryId,
    unclassified: unclassified,
    scope: scope,
  );
}
