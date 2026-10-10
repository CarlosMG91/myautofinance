import '../../features/movements/movements.dart';
import 'navigation_context.dart';
import 'navigation_period.dart';
import 'app_routes.dart';

/// Contexto interno verificable; no admite URLs, destinos ni parámetros libres.
/// Las ramas abiertas se transportan como UUID separados por coma en abiertas.
final class MonthlyStatusOrigin {
  MonthlyStatusOrigin(this.context) {
    if (context.destination != SessionDestination.status ||
        context.view != PeriodView.monthly ||
        context.filters.keys.any(
          (key) => !const {'abiertas', 'concepto'}.contains(key),
        )) {
      throw const MovementFailure('Origen de Estado inválido.');
    }
    _category(context.branchId);
    for (final id in (context.filters['abiertas'] ?? '').split(',')) {
      if (id.isNotEmpty) MovementSelection([id]);
    }
    if (context.focus != null &&
        (context.focus!.length > 256 ||
            RegExp(r'[\x00-\x1f]').hasMatch(context.focus!))) {
      throw const MovementFailure('Foco de Estado inválido.');
    }
  }
  final NavigationContext context;
  String get route => Uri(
    path: AppRoutes.monthlyStatus,
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

  static MonthlyStatusOrigin parse(String route) {
    final uri = Uri.parse(route);
    final p = uri.queryParameters;
    if (uri.path != AppRoutes.monthlyStatus ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasFragment ||
        uri.queryParametersAll.values.any((v) => v.length != 1) ||
        p.keys.any(
          (k) => !const {
            'a',
            'm',
            'rama',
            'alcance',
            'abiertas',
            'posicion',
            'foco',
            'concepto',
          }.contains(k),
        ) ||
        !RegExp(r'^[0-9]{4}$').hasMatch(p['a'] ?? '') ||
        !RegExp(r'^(0[1-9]|1[0-2])$').hasMatch(p['m'] ?? '')) {
      throw const MovementFailure('Origen de Estado inválido.');
    }
    final scope = switch (p['alcance']) {
      null || 'rama' => MovementCategoryScope.branch,
      'directo' => MovementCategoryScope.direct,
      _ => throw const MovementFailure('Alcance de Estado inválido.'),
    };
    final offset = p['posicion'] == null
        ? 0.0
        : double.tryParse(p['posicion']!);
    if (offset == null || !offset.isFinite || offset < 0) {
      throw const MovementFailure('Posición de Estado inválida.');
    }
    return MonthlyStatusOrigin(
      NavigationContext(
        destination: SessionDestination.status,
        period: NavigationPeriod(int.parse(p['a']!), int.parse(p['m']!)),
        branchId: p['rama'],
        scope: scope,
        filters: {
          if (p['abiertas'] != null) 'abiertas': p['abiertas']!,
          if (p['concepto'] != null) 'concepto': p['concepto']!,
        },
        scrollOffset: offset,
        focus: p['foco'],
      ),
    );
  }

  static void _category(String? id) {
    if (id != null && id != 'sin-clasificar') MovementSelection([id]);
  }
}
