import 'navigation_context.dart';
import 'navigation_period.dart';
import 'navigation_session.dart';
import '../../features/movements/movements.dart' show MovementCategoryScope;

/// Resolución sin efectos: un error nunca cambia la sesión ni consulta datos.
sealed class SessionLocationResult {
  const SessionLocationResult();
}

final class ValidSessionLocation extends SessionLocationResult {
  const ValidSessionLocation(this.context);
  final NavigationContext context;
}

final class InvalidSessionLocation extends SessionLocationResult {
  const InvalidSessionLocation(this.origin);
  final NavigationContext origin;
  String get message => 'Periodo o destino de navegación inválido.';
}

abstract final class SessionLocation {
  static String encode(NavigationContext context) => Uri(
    path: context.destination.path,
    queryParameters: {
      for (final entry in context.filters.entries)
        if (!const {'a', 'm', 'rama', 'c', 'alcance'}.contains(entry.key))
          entry.key: entry.value,
      'a': context.period.year.toString().padLeft(4, '0'),
      'm': context.period.month.toString().padLeft(2, '0'),
      if (context.branchId != null) 'rama': context.branchId!,
      if (context.branchId != null ||
          context.scope == MovementCategoryScope.direct)
        'alcance': context.scope == MovementCategoryScope.direct
            ? 'directo'
            : 'rama',
    },
  ).toString();

  static SessionLocationResult resolve(
    String location,
    NavigationSession session, {
    PeriodView? view,
  }) {
    try {
      final uri = Uri.parse(location);
      final destination = SessionDestination.fromPath(uri.path);
      if (destination == null ||
          uri.hasScheme ||
          uri.hasAuthority ||
          uri.hasFragment ||
          uri.queryParametersAll.values.any((values) => values.length != 1)) {
        throw const FormatException();
      }
      final p = uri.queryParameters;
      final a = p['a'], m = p['m'];
      if ((a != null && !RegExp(r'^[0-9]{4}$').hasMatch(a)) ||
          (m != null && !RegExp(r'^(0?[1-9]|1[0-2])$').hasMatch(m)) ||
          (m != null && a == null)) {
        throw const FormatException();
      }
      final effectiveView = view ?? destination.defaultView;
      if (p.containsKey('rama') && p.containsKey('c')) {
        throw const FormatException();
      }
      final scope = switch (p['alcance']) {
        null || 'rama' || 'branch' => MovementCategoryScope.branch,
        'directo' || 'direct' => MovementCategoryScope.direct,
        _ => throw const FormatException(),
      };
      final period = a == null
          ? session.period
          : m == null
          ? session.periodForYear(int.parse(a), effectiveView)
          : NavigationPeriod(int.parse(a), int.parse(m));
      return ValidSessionLocation(
        NavigationContext(
          destination: destination,
          period: period,
          view: effectiveView,
          branchId: p['rama'] ?? p['c'],
          scope: scope,
          filters: {
            for (final entry in p.entries)
              if (!const {'a', 'm', 'rama', 'c', 'alcance'}.contains(entry.key))
                entry.key: entry.value,
          },
        ),
      );
    } catch (_) {
      return InvalidSessionLocation(session.context);
    }
  }
}
