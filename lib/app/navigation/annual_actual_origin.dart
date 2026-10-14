import '../../features/movements/movements.dart';
import 'app_routes.dart';
import 'navigation_context.dart';
import 'navigation_period.dart';

/// Instantánea local verificable del resumen o detalle de Real anual.
final class AnnualActualOrigin {
  AnnualActualOrigin(this.context, {this.detail = false}) {
    if (context.destination != SessionDestination.actual ||
        context.view != PeriodView.annual ||
        context.filters.keys.any(
          (key) => !const {'abiertas', 'meses'}.contains(key),
        )) {
      throw const MovementFailure('Origen de Real anual inválido.');
    }
    _category(context.branchId);
    for (final key in const ['abiertas', 'meses']) {
      for (final id in (context.filters[key] ?? '').split(',')) {
        if (key == 'meses' && id == 'total-general') continue;
        if (id.isNotEmpty) _category(id);
      }
    }
    if (context.focus != null &&
        (context.focus!.length > 256 ||
            RegExp(r'[\x00-\x1f]').hasMatch(context.focus!))) {
      throw const MovementFailure('Foco de Real anual inválido.');
    }
  }
  final NavigationContext context;
  final bool detail;
  String get route => Uri(
    path: detail ? AppRoutes.actualDetail : AppRoutes.actualSpending,
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

  static AnnualActualOrigin parse(String route) {
    final uri = Uri.parse(route);
    final p = uri.queryParameters;
    if (!const {
          AppRoutes.actualSpending,
          AppRoutes.actualDetail,
        }.contains(uri.path) ||
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
      throw const MovementFailure('Origen de Real anual inválido.');
    }
    final offset = p['posicion'] == null
        ? 0.0
        : double.tryParse(p['posicion']!);
    if (offset == null || !offset.isFinite || offset < 0) {
      throw const MovementFailure('Posición de Real anual inválida.');
    }
    return AnnualActualOrigin(
      NavigationContext(
        destination: SessionDestination.actual,
        period: NavigationPeriod(int.parse(p['a']!), int.parse(p['m']!)),
        branchId: p['rama'],
        scope: switch (p['alcance']) {
          null || 'rama' => MovementCategoryScope.branch,
          'directo' => MovementCategoryScope.direct,
          _ => throw const MovementFailure('Alcance de Real anual inválido.'),
        },
        filters: {
          if (p['abiertas'] != null) 'abiertas': p['abiertas']!,
          if (p['meses'] != null) 'meses': p['meses']!,
        },
        scrollOffset: offset,
        focus: p['foco'],
      ),
      detail: uri.path == AppRoutes.actualDetail,
    );
  }

  static void _category(String? id) {
    if (id != null && id != 'sin-clasificar') MovementSelection([id]);
  }
}
