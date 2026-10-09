import '../../features/movements/movements.dart' show MovementCategoryScope;
import 'app_routes.dart';
import 'navigation_period.dart';

enum PeriodView { monthly, annual }

enum SessionDestination {
  status(AppRoutes.monthlyStatus, PeriodView.monthly),
  wealth(AppRoutes.wealth, PeriodView.monthly),
  budget(AppRoutes.budget, PeriodView.annual),
  actual(AppRoutes.actualSpending, PeriodView.annual),
  indicators(AppRoutes.indicators, PeriodView.monthly);

  const SessionDestination(this.path, this.defaultView);
  final String path;
  final PeriodView defaultView;

  static SessionDestination? fromPath(String path) {
    for (final destination in values) {
      if (destination.path == path) return destination;
    }
    return null;
  }
}

/// Instantánea del origen. Los filtros y el foco pertenecen al consumidor;
/// no se guardan en SQLite, Drive ni preferencias del dispositivo.
final class NavigationContext {
  NavigationContext({
    required this.destination,
    required this.period,
    PeriodView? view,
    this.branchId,
    this.scope = MovementCategoryScope.branch,
    Map<String, String> filters = const {},
    this.scrollOffset = 0,
    this.focus,
  }) : view = view ?? destination.defaultView,
       filters = Map.unmodifiable(filters) {
    if (!scrollOffset.isFinite || scrollOffset < 0) {
      throw ArgumentError.value(scrollOffset, 'scrollOffset');
    }
  }

  final SessionDestination destination;
  final NavigationPeriod period;
  final PeriodView view;
  final String? branchId;
  final MovementCategoryScope scope;
  final Map<String, String> filters;
  final double scrollOffset;
  final String? focus;
  AnnualNavigationPeriod get annualPeriod => AnnualNavigationPeriod(period);

  NavigationContext withPeriod(NavigationPeriod value) => NavigationContext(
    destination: destination,
    period: value,
    view: view,
    branchId: branchId,
    scope: scope,
    filters: filters,
    // Un periodo nuevo invalida posición y foco de la consulta anterior.
    scrollOffset: value == period ? scrollOffset : 0,
    focus: value == period ? focus : null,
  );
}

/// Una ruta de detalle guarda el origen completo sin elegir otro periodo.
final class SecondaryNavigationContext {
  const SecondaryNavigationContext(this.origin);
  final NavigationContext origin;
}
