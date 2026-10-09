import '../../features/budget/budget.dart' show BudgetMonth;
import '../../features/movements/movements.dart' show ValueDate;
import '../../features/wealth/wealth.dart' show Month;

/// Periodo de navegación civil. No representa cifras ni existencia de datos.
final class NavigationPeriod {
  NavigationPeriod(int year, int month) : civilMonth = Month(year, month);

  factory NavigationPeriod.fromMonth(Month month) => NavigationPeriod(
    int.parse(month.value.substring(0, 4)),
    int.parse(month.value.substring(5, 7)),
  );

  final Month civilMonth;
  int get year => int.parse(civilMonth.value.substring(0, 4));
  int get month => int.parse(civilMonth.value.substring(5, 7));
  BudgetMonth get budgetMonth => BudgetMonth(year, month);
  ValueDate get firstDay => ValueDate(year, month, 1);
  NavigationPeriod? get previous => year == 1 && month == 1
      ? null
      : NavigationPeriod(
          month == 1 ? year - 1 : year,
          month == 1 ? 12 : month - 1,
        );
  NavigationPeriod? get next => civilMonth.next == null
      ? null
      : NavigationPeriod.fromMonth(civilMonth.next!);

  NavigationPeriod inYear(int year) => NavigationPeriod(year, month);

  @override
  bool operator ==(Object other) =>
      other is NavigationPeriod && other.civilMonth.value == civilMonth.value;
  @override
  int get hashCode => civilMonth.value.hashCode;
  @override
  String toString() => civilMonth.value.substring(0, 7);
}

/// El año de consulta y el mes enfocado son conceptos diferentes. El foco no
/// limita una consulta anual al mes ni convierte fotos en un total anual.
final class AnnualNavigationPeriod {
  const AnnualNavigationPeriod(this.focusedPeriod);
  final NavigationPeriod focusedPeriod;
  int get year => focusedPeriod.year;
  int get focusedMonth => focusedPeriod.month;
  ValueDate get firstDay => ValueDate(year, 1, 1);
  ValueDate? get until => year == 9999 ? null : ValueDate(year + 1, 1, 1);
}
