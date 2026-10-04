import '../../features/wealth/wealth.dart';
import 'app_routes.dart';

enum WealthRouteKind { month, photo, catalog, createAccount, account }

/// Mes de trabajo Europe/Madrid, independiente de la zona del dispositivo.
Month madridMonth(DateTime instant) {
  final utc = instant.toUtc();
  DateTime transition(int month) {
    final last = DateTime.utc(utc.year, month + 1, 0);
    return DateTime.utc(utc.year, month, last.day - last.weekday % 7, 1);
  }

  final summer = !utc.isBefore(transition(3)) && utc.isBefore(transition(10));
  final local = utc.add(Duration(hours: summer ? 2 : 1));
  return Month(local.year, local.month);
}

/// Rutas de EP-002. La identidad nunca depende del nombre visible de la ficha.
final class WealthRoute {
  WealthRoute._(this.kind, this.month, this.accountId);
  final WealthRouteKind kind;
  final Month? month;
  final String? accountId;

  static WealthRoute parse(String location, {required Month defaultMonth}) {
    final uri = Uri.parse(location);
    final path = uri.path;
    if (path == AppRoutes.wealth || path == AppRoutes.wealthPhoto) {
      final a = uri.queryParameters['a'];
      final m = uri.queryParameters['m'];
      if ((a != null && !RegExp(r'^[0-9]{4}$').hasMatch(a)) ||
          (m != null && !RegExp(r'^[0-9]{2}$').hasMatch(m))) {
        throw const AccountFailure('Periodo inválido.');
      }
      final month = Month(
        a == null
            ? int.parse(defaultMonth.value.substring(0, 4))
            : int.parse(a),
        m == null
            ? int.parse(defaultMonth.value.substring(5, 7))
            : int.parse(m),
      );
      return WealthRoute._(
        path == AppRoutes.wealth
            ? WealthRouteKind.month
            : WealthRouteKind.photo,
        month,
        null,
      );
    }
    if (path == AppRoutes.accounts) {
      return WealthRoute._(WealthRouteKind.catalog, null, null);
    }
    if (path == AppRoutes.newAccount) {
      return WealthRoute._(WealthRouteKind.createAccount, null, null);
    }
    final parts = uri.pathSegments;
    if (parts.length == 3 &&
        parts[0] == 'patrimonio' &&
        parts[1] == 'fichas' &&
        parts.last.isNotEmpty) {
      return WealthRoute._(WealthRouteKind.account, null, parts.last);
    }
    throw const AccountFailure('Ruta patrimonial inválida.');
  }

  Future<Object?> load(WealthController controller) => switch (kind) {
    WealthRouteKind.month || WealthRouteKind.photo => controller.month(month!),
    WealthRouteKind.catalog => controller.catalog(),
    WealthRouteKind.account => controller.details(accountId!),
    WealthRouteKind.createAccount => Future<Object?>.value(),
  };
}
