import '../../budget/budget.dart';
import '../../movements/movements.dart';

/// Alcance de una cifra, independiente de la consulta y de los widgets de Estado.
/// UUID null significa mes completo; unclassified distingue explícitamente NULL.
final class MonthlyFigureDetail {
  MonthlyFigureDetail({
    required this.month,
    this.categoryId,
    this.unclassified = false,
    this.scope = MovementCategoryScope.branch,
  }) {
    if (unclassified && categoryId != null) {
      throw const MovementFailure('Categoría ambigua.');
    }
    if (categoryId != null) MovementSelection([categoryId!]);
  }

  final BudgetMonth month;
  final String? categoryId;
  final bool unclassified;
  final MovementCategoryScope scope;

  MovementListQuery get movements {
    final year = int.parse(month.value.substring(0, 4));
    final number = int.parse(month.value.substring(5, 7));
    final next = year == 9999 && number == 12
        ? null
        : BudgetMonth(
            number == 12 ? year + 1 : year,
            number == 12 ? 1 : number + 1,
          );
    return MovementListQuery(
      from: ValueDate.parse(month.value),
      until: next == null ? null : ValueDate.parse(next.value),
      categoryId: categoryId,
      unclassified: unclassified,
      scope: scope,
    );
  }

  BudgetListQuery get budgets => BudgetListQuery(
    month: month,
    categoryId: categoryId,
    unclassified: unclassified,
    scope: scope,
  );
}

typedef OpenMonthlyFigureDetail = Future<void> Function(
  MonthlyFigureDetail detail,
);

/// Diferencia conserva dos acciones explícitas, sin elegir una fuente por signo.
final class MonthlyStatusDetailCallbacks {
  const MonthlyStatusDetailCallbacks({
    required this.onMovements,
    required this.onBudgets,
    required this.onDifference,
  });
  final OpenMonthlyFigureDetail onMovements, onBudgets, onDifference;
}
