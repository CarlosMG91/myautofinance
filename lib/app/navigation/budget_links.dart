import '../../features/budget/budget.dart';
import '../../features/movements/movements.dart';
import 'app_routes.dart';
import 'monthly_status_origin.dart';

abstract final class BudgetLinks {
  static const path = '${AppRoutes.budget}/partidas';
  static String list(BudgetListQuery query, {String? origin}) => Uri(
    path: path,
    queryParameters: {
      'a': query.month.value.substring(0, 4),
      'm': query.month.value.substring(5, 7),
      if (query.categoryId != null) 'rama': query.categoryId!,
      if (query.unclassified) 'rama': 'sin-clasificar',
      'alcance': query.scope == MovementCategoryScope.direct
          ? 'directo'
          : 'rama',
      if (origin != null) 'origen': MonthlyStatusOrigin.parse(origin).route,
    },
  ).toString();
  static String create(BudgetListQuery query, {String? origin}) =>
      Uri.parse(list(query, origin: origin))
          .replace(path: '$path/nueva')
          .toString();
  static String detail(String id, BudgetListQuery query, {String? origin}) {
    MovementSelection([id]);
    return Uri.parse(list(query, origin: origin))
        .replace(path: '$path/$id')
        .toString();
  }

  static BudgetListQuery parse(String route) {
    final uri = Uri.parse(route);
    final p = uri.queryParameters;
    if (uri.path != path ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasFragment ||
        uri.queryParametersAll.values.any((v) => v.length != 1) ||
        p.keys.any(
          (k) => !const {'a', 'm', 'rama', 'alcance', 'origen'}.contains(k),
        ) ||
        !RegExp(r'^[0-9]{4}$').hasMatch(p['a'] ?? '') ||
        !RegExp(r'^(0[1-9]|1[0-2])$').hasMatch(p['m'] ?? '')) {
      throw const BudgetFailure('Ruta de partidas inválida.');
    }
    final scope = switch (p['alcance']) {
      null || 'rama' => MovementCategoryScope.branch,
      'directo' => MovementCategoryScope.direct,
      _ => throw const BudgetFailure('Alcance de partidas inválido.'),
    };
    if (p['origen'] != null) MonthlyStatusOrigin.parse(p['origen']!);
    return BudgetListQuery(
      month: BudgetMonth(int.parse(p['a']!), int.parse(p['m']!)),
      categoryId: p['rama'] == 'sin-clasificar' ? null : p['rama'],
      unclassified: p['rama'] == 'sin-clasificar',
      scope: scope,
    );
  }

  static MonthlyStatusOrigin? origin(String route) {
    final value = Uri.parse(route).queryParameters['origen'];
    return value == null ? null : MonthlyStatusOrigin.parse(value);
  }
}
