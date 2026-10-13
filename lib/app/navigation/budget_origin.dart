import '../../features/budget/budget.dart';
import '../../features/movements/movements.dart';
import 'app_routes.dart';
import 'monthly_status_origin.dart';
import 'navigation_context.dart';
import 'navigation_period.dart';

/// Orígenes locales permitidos para partidas. No acepta destinos arbitrarios.
final class BudgetOrigin {
  BudgetOrigin(this.context) {
    if (const {
      SessionDestination.status,
      SessionDestination.home,
    }.contains(context.destination)) {
      MonthlyStatusOrigin(context);
      return;
    }
    if (context.destination != SessionDestination.budget ||
        context.filters.keys.any(
          (key) => !const {'abiertas', 'meses'}.contains(key),
        )) {
      throw const BudgetFailure('Origen de presupuesto inválido.');
    }
    if (context.branchId != null) MovementSelection([context.branchId!]);
    for (final key in const ['abiertas', 'meses']) {
      for (final id in (context.filters[key] ?? '').split(',')) {
        if (id.isNotEmpty) MovementSelection([id]);
      }
    }
    if (context.focus != null &&
        (context.focus!.length > 256 ||
            RegExp(r'[\x00-\x1f]').hasMatch(context.focus!))) {
      throw const BudgetFailure('Foco de presupuesto inválido.');
    }
  }

  final NavigationContext context;
  String get route =>
      const {
        SessionDestination.status,
        SessionDestination.home,
      }.contains(context.destination)
      ? MonthlyStatusOrigin(context).route
      : Uri(
          path: context.view == PeriodView.annual
              ? AppRoutes.budget
              : AppRoutes.monthlyBudget,
          queryParameters: {
            'a': context.period.year.toString().padLeft(4, '0'),
            'm': context.period.month.toString().padLeft(2, '0'),
            if (context.branchId != null) 'rama': context.branchId!,
            'alcance': context.scope == MovementCategoryScope.direct
                ? 'directo'
                : 'rama',
            ...context.filters,
            'posicion': context.scrollOffset.toString(),
            if (context.focus != null) 'foco': context.focus!,
          },
        ).toString();

  static BudgetOrigin parse(String route) {
    final uri = Uri.parse(route);
    if (const {AppRoutes.monthlyStatus, AppRoutes.start}.contains(uri.path)) {
      return BudgetOrigin(MonthlyStatusOrigin.parse(route).context);
    }
    final p = uri.queryParameters;
    if (!const {AppRoutes.budget, AppRoutes.monthlyBudget}.contains(uri.path) ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasFragment ||
        uri.queryParametersAll.values.any((values) => values.length != 1) ||
        p.keys.any(
          (key) => !const {
            'a',
            'm',
            'rama',
            'alcance',
            'abiertas',
            'meses',
            'posicion',
            'foco',
          }.contains(key),
        ) ||
        !RegExp(r'^[0-9]{4}$').hasMatch(p['a'] ?? '') ||
        !RegExp(r'^(0[1-9]|1[0-2])$').hasMatch(p['m'] ?? '')) {
      throw const BudgetFailure('Origen de presupuesto inválido.');
    }
    final offset = p['posicion'] == null
        ? 0.0
        : double.tryParse(p['posicion']!);
    if (offset == null || !offset.isFinite || offset < 0) {
      throw const BudgetFailure('Posición de presupuesto inválida.');
    }
    return BudgetOrigin(
      NavigationContext(
        destination: SessionDestination.budget,
        period: NavigationPeriod(int.parse(p['a']!), int.parse(p['m']!)),
        view: uri.path == AppRoutes.budget
            ? PeriodView.annual
            : PeriodView.monthly,
        branchId: p['rama'],
        scope: switch (p['alcance']) {
          null || 'rama' => MovementCategoryScope.branch,
          'directo' => MovementCategoryScope.direct,
          _ => throw const BudgetFailure('Alcance de presupuesto inválido.'),
        },
        filters: {
          if (p['abiertas'] != null) 'abiertas': p['abiertas']!,
          if (p['meses'] != null) 'meses': p['meses']!,
        },
        scrollOffset: offset,
        focus: p['foco'],
      ),
    );
  }
}
