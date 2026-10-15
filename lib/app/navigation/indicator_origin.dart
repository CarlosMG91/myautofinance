import 'app_routes.dart';
import 'navigation_context.dart';
import 'navigation_period.dart';
import '../../features/movements/movements.dart'
    show MovementSelection, MovementCategoryScope;

/// Origen local validado, transportable a fotos y presupuesto sin pila.
final class IndicatorOrigin {
  IndicatorOrigin(this.context) {
    if (context.destination != SessionDestination.indicators ||
        context.view != PeriodView.monthly ||
        context.filters.keys.any(
          (key) => !const {'detalle', 'concepto'}.contains(key),
        ) ||
        (context.filters['detalle'] != null &&
            context.filters['detalle'] != '1') ||
        (context.focus != null &&
            (context.focus!.length > 256 ||
                RegExp(r'[\x00-\x1f]').hasMatch(context.focus!)))) {
      throw const FormatException('Origen de Indicadores inválido.');
    }
    // EP-016 conserva estos metadatos de retorno. No filtran la consulta global
    // del colchón ni se convierten en controles de configuración.
    if (context.branchId != null) MovementSelection([context.branchId!]);
  }
  final NavigationContext context;
  bool get detail => context.filters['detalle'] == '1';
  String get route => Uri(
    path: detail ? AppRoutes.indicatorDetail : AppRoutes.indicators,
    queryParameters: {
      'a': context.period.year.toString().padLeft(4, '0'),
      'm': context.period.month.toString().padLeft(2, '0'),
      if (context.branchId != null) 'rama': context.branchId!,
      if (context.branchId != null ||
          context.scope == MovementCategoryScope.direct)
        'alcance': context.scope == MovementCategoryScope.direct
            ? 'directo'
            : 'rama',
      if (context.filters['concepto'] != null)
        'concepto': context.filters['concepto']!,
      'posicion': context.scrollOffset.toString(),
      if (context.focus != null) 'foco': context.focus!,
    },
  ).toString();

  static IndicatorOrigin parse(String route) {
    final uri = Uri.parse(route), p = Uri.parse(route).queryParameters;
    final offset = p['posicion'] == null
        ? 0.0
        : double.tryParse(p['posicion']!);
    if (!const {
          AppRoutes.indicators,
          AppRoutes.indicatorDetail,
        }.contains(uri.path) ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasFragment ||
        uri.queryParametersAll.values.any((v) => v.length != 1) ||
        p.keys.any(
          (key) => !const {
            'a',
            'm',
            'posicion',
            'foco',
            'detalle',
            'rama',
            'c',
            'alcance',
            'concepto',
          }.contains(key),
        ) ||
        !RegExp(r'^[0-9]{4}$').hasMatch(p['a'] ?? '') ||
        !RegExp(r'^(0[1-9]|1[0-2])$').hasMatch(p['m'] ?? '') ||
        (p['detalle'] != null && p['detalle'] != '1') ||
        (p.containsKey('rama') && p.containsKey('c')) ||
        offset == null ||
        !offset.isFinite ||
        offset < 0) {
      throw const FormatException('Origen de Indicadores inválido.');
    }
    return IndicatorOrigin(
      NavigationContext(
        destination: SessionDestination.indicators,
        period: NavigationPeriod(int.parse(p['a']!), int.parse(p['m']!)),
        branchId: p['rama'] ?? p['c'],
        scope: switch (p['alcance']) {
          null || 'rama' || 'branch' => MovementCategoryScope.branch,
          'directo' || 'direct' => MovementCategoryScope.direct,
          _ => throw const FormatException('Alcance de Indicadores inválido.'),
        },
        filters: {
          if (p['concepto'] != null) 'concepto': p['concepto']!,
          if (uri.path == AppRoutes.indicatorDetail || p['detalle'] == '1')
            'detalle': '1',
        },
        scrollOffset: offset,
        focus: p['foco'],
      ),
    );
  }
}
