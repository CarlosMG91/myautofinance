import '../../features/movements/movements.dart';
import '../../features/wealth/wealth.dart' show Month;
import 'app_routes.dart';

/// Serialización de app; los informes solo necesitan MovementListQuery y un
/// callback inyectado. No acceden a controladores ni adaptadores de movimientos.
abstract final class MovementLinks {
  static String create(MovementListQuery query, {String? origin}) =>
      Uri.parse(list(query, origin: origin))
          .replace(path: '${AppRoutes.movements}/nuevo')
          .toString();

  static String detail(String id, MovementListQuery query, {String? origin}) {
    MovementSelection([id]);
    return Uri.parse(list(query, origin: origin))
        .replace(path: '${AppRoutes.movements}/$id')
        .toString();
  }

  static String list(MovementListQuery query, {String? origin}) => Uri(
    path: AppRoutes.movements,
    queryParameters: {
      'desde': query.from.value,
      if (query.until != null) 'hasta': query.until!.value,
      if (query.accountId != null) 'cuenta': query.accountId!,
      if (query.categoryId != null) 'rama': query.categoryId!,
      if (query.unclassified) 'rama': 'sin-clasificar',
      'alcance': query.scope == MovementCategoryScope.direct
          ? 'directo'
          : 'rama',
      if (query.concept.isNotEmpty) 'concepto': query.concept,
      if (origin != null) 'origen': _origin(origin),
    },
  ).toString();

  static MovementListQuery parse(String route, {required Month defaultMonth}) {
    final uri = Uri.parse(route);
    final p = uri.queryParameters;
    if (uri.path != AppRoutes.movements ||
        uri.hasAuthority ||
        uri.hasScheme ||
        uri.hasFragment ||
        uri.queryParametersAll.values.any((v) => v.length != 1) ||
        p.containsKey('a') != p.containsKey('m') ||
        p.containsKey('a') &&
            (!RegExp(r'^[0-9]{4}$').hasMatch(p['a']!) ||
                !RegExp(r'^(0[1-9]|1[0-2])$').hasMatch(p['m']!)) ||
        p.containsKey('hasta') && !p.containsKey('desde')) {
      throw const MovementFailure('Ruta de movimientos inválida.');
    }
    final month = p.containsKey('a')
        ? Month(int.parse(p['a']!), int.parse(p['m']!))
        : defaultMonth;
    final from = ValueDate.parse(p['desde'] ?? month.value);
    final until = p.containsKey('desde')
        ? (p['hasta'] == null ? null : ValueDate.parse(p['hasta']!))
        : (month.next == null ? null : ValueDate.parse(month.next!.value));
    final scope = switch (p['alcance']) {
      null || 'rama' || 'branch' => MovementCategoryScope.branch,
      'directo' || 'direct' => MovementCategoryScope.direct,
      _ => throw const MovementFailure('Alcance de categoría inválido.'),
    };
    if (p.containsKey('rama') && p.containsKey('c') ||
        p['sinClasificar'] != null && p['sinClasificar'] != '1') {
      throw const MovementFailure('Categoría ambigua.');
    }
    final category = p['rama'] ?? p['c'];
    if (p['origen'] != null) _origin(p['origen']!);
    return MovementListQuery(
      from: from,
      until: until,
      accountId: p['cuenta'],
      categoryId: category == 'sin-clasificar' ? null : category,
      unclassified: category == 'sin-clasificar' || p['sinClasificar'] == '1',
      scope: scope,
      concept: p['concepto'] ?? '',
    );
  }

  /// Gestión solo transmite el mes de trabajo, sin heredar filtros del informe.
  static String management(String origin, {required Month defaultMonth}) {
    final p = Uri.parse(origin).queryParameters;
    final year = p['a'] ?? defaultMonth.value.substring(0, 4);
    final monthNumber = p['m'] ?? defaultMonth.value.substring(5, 7);
    final month = Month(int.parse(year), int.parse(monthNumber));
    return list(
      MovementListQuery(
        from: ValueDate.parse(month.value),
        until: month.next == null ? null : ValueDate.parse(month.next!.value),
      ),
      origin: origin,
    );
  }

  static String? origin(String route) {
    final value = Uri.parse(route).queryParameters['origen'];
    return value == null ? null : _origin(value);
  }

  static String _origin(String route) {
    final uri = Uri.tryParse(route);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasFragment ||
        ![
          AppRoutes.home,
          ...AppRoutes.destinations.map((d) => d.path),
        ].contains(uri.path)) {
      throw const MovementFailure('Origen de navegación inválido.');
    }
    return route;
  }
}
