import 'package:flutter/widgets.dart';

import 'navigation_context.dart';
import 'navigation_session.dart';
import 'session_location.dart';
import 'budget_origin.dart';
import 'app_routes.dart';
import 'movement_list_route.dart' show MovementListOrigin;

/// Solo app importa este acceso. Los módulos reciben periodo/callbacks por
/// constructor para conservar el grafo de arquitectura existente.
class NavigationSessionScope extends InheritedNotifier<NavigationSession> {
  const NavigationSessionScope({
    super.key,
    required NavigationSession session,
    required super.child,
  }) : super(notifier: session);

  static NavigationSession of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<NavigationSessionScope>()!
      .notifier!;

  static NavigationSession? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<NavigationSessionScope>()
      ?.notifier;
}

/// Publicar una ruta de detalle no cambia el periodo común. Al hacer pop de
/// una ruta principal se recupera su contexto, no el default del reloj.
class NavigationSessionObserver extends NavigatorObserver {
  NavigationSessionObserver(this.session);
  final NavigationSession session;
  final Map<Route<dynamic>, NavigationContext> _origins = {};

  void _activate(Route<dynamic>? route) {
    if (route == null) return;
    final saved = _origins[route];
    if (saved != null) {
      session.setContext(saved, deferNotification: true);
      return;
    }
    final uri = Uri.tryParse(route.settings.name ?? '');
    // «Ver mes» es una elección explícita; la captura normal sigue secundaria.
    final explicit = route.settings.arguments;
    if (uri?.path == AppRoutes.monthlyBudget && explicit is NavigationContext) {
      try {
        final p = uri!.queryParameters;
        if (p.keys.any((key) => !const {'a', 'm'}.contains(key)) ||
            uri.queryParametersAll.values.any((values) => values.length != 1)) {
          return;
        }
        final selected = BudgetOrigin.parse(
          uri.replace(queryParameters: {'a': p['a']!, 'm': p['m']!}).toString(),
        );
        if (explicit.destination != SessionDestination.budget ||
            explicit.period != selected.context.period ||
            explicit.view != PeriodView.annual) {
          return;
        }
        _origins[route] = explicit;
        session.setContext(explicit, deferNotification: true);
      } catch (_) {
        // La ruta inválida no puede alterar el origen de sesión.
      }
      return;
    }
    final destination = uri == null
        ? null
        : SessionDestination.fromPath(uri.path);
    if (destination == null) return;
    if (destination == SessionDestination.movements &&
        (route.settings.arguments is MovementListOrigin ||
            uri!.queryParameters.containsKey('origen'))) {
      return;
    }
    final result = SessionLocation.resolve(route.settings.name!, session);
    if (result is ValidSessionLocation) {
      final argument = route.settings.arguments;
      final context =
          argument is NavigationContext &&
              argument.destination == result.context.destination &&
              argument.period == result.context.period &&
              argument.view == result.context.view
          ? argument
          : result.context;
      _origins[route] = context;
      // didPush puede ocurrir dentro de la construcción inicial de Navigator.
      // El estado cambia ahora; la notificación espera a que termine esa pila.
      session.setContext(context, deferNotification: true);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) {
      _origins[previousRoute] = session.context;
    }
    _activate(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _origins.remove(route);
    _activate(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _origins.remove(oldRoute);
    _activate(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _origins.remove(route);
  }
}
