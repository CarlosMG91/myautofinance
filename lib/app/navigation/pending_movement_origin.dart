import 'app_routes.dart';

/// Origen de la bandeja sin dependencia del widget de la ruta.
class PendingMovementOrigin {
  const PendingMovementOrigin({
    this.route = AppRoutes.home,
    this.label = 'Volver al origen',
  });
  final String route, label;
}
