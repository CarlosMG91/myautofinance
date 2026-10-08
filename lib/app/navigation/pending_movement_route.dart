import 'package:flutter/material.dart';

import '../../features/movements/movements.dart';
import '../../features/movements/presentation/category_tree_screen.dart';
import '../../features/movements/presentation/pending_movement_controller.dart';
import '../../features/movements/presentation/pending_movement_screen.dart';
import '../category_selector_navigation.dart';
import 'app_routes.dart';

/// Argumento de retorno para Gestión/lotes (sus enlaces pertenecen a T136).
class PendingMovementOrigin {
  const PendingMovementOrigin({
    this.route = AppRoutes.home,
    this.label = 'Volver al origen',
  });
  final String route, label;
}

/// Ruta serializable por UUID de lote, sin imponer el mes del origen.
class PendingMovementRoute extends StatefulWidget {
  const PendingMovementRoute({
    super.key,
    required this.settings,
    required this.load,
    required this.categories,
    this.onBatch,
  });
  final RouteSettings settings;
  final PendingMovementLoader load;
  final CategoryManagementLoader categories;
  final Future<void> Function(BuildContext context, String batchId)? onBatch;

  @override
  State<PendingMovementRoute> createState() => _PendingMovementRouteState();
}

class _PendingMovementRouteState extends State<PendingMovementRoute> {
  PendingMovementController? _controller;

  @override
  Widget build(BuildContext context) {
    final origin = widget.settings.arguments is PendingMovementOrigin
        ? widget.settings.arguments as PendingMovementOrigin
        : const PendingMovementOrigin();
    void back() => Navigator.of(context).canPop()
        ? Navigator.of(context).pop()
        : Navigator.of(context).pushReplacementNamed(origin.route);
    try {
      final uri = Uri.parse(widget.settings.name!);
      if (uri.hasScheme ||
          uri.hasAuthority ||
          uri.hasFragment ||
          uri.path != AppRoutes.pendingMovements ||
          uri.queryParameters.keys.any((k) => k != 'lote') ||
          uri.queryParametersAll.values.any((v) => v.length != 1)) {
        throw const MovementFailure('Ruta de pendientes inválida.');
      }
      final query = PendingMovementQuery(batchId: uri.queryParameters['lote']);
      final c = _controller ??= PendingMovementController(
        load: widget.load,
        query: query,
      );
      final width = MediaQuery.sizeOf(context).width;
      Widget navigation(bool vertical) => Wrap(
        direction: vertical ? Axis.vertical : Axis.horizontal,
        children: [
          for (final destination in AppRoutes.destinations)
            SizedBox(
              width: vertical
                  ? 168
                  : (width - 24) /
                        (MediaQuery.textScalerOf(context).scale(14) >= 21
                            ? 2
                            : 3),
              child: TextButton(
                onPressed: c.operationActive
                    ? null
                    : () => Navigator.of(
                        context,
                      ).pushNamedAndRemoveUntil(destination.path, (_) => false),
                child: Text(switch (destination.path) {
                  AppRoutes.monthlyStatus => 'Estado',
                  AppRoutes.wealth => 'Patrimonio',
                  AppRoutes.budget => 'Presupuesto',
                  AppRoutes.actualSpending => 'Real',
                  _ => 'Indicadores',
                }),
              ),
            ),
        ],
      );
      return PendingMovementScreen(
        controller: c,
        onReturn: back,
        returnLabel: origin.label,
        navigation: width >= 840
            ? Container(
                width: width >= 1200 ? 216 : 200,
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: navigation(true),
              )
            : null,
        bottomNavigation: width < 840
            ? SafeArea(child: navigation(false))
            : null,
        selectCategory: () =>
            selectCategory(context, loadManagement: widget.categories),
        onOpen: (id) async {
          await Navigator.of(context).pushNamed('${AppRoutes.movements}/$id');
        },
        onBatch: widget.onBatch == null
            ? null
            : (id) => widget.onBatch!(context, id),
      );
    } catch (_) {
      return Scaffold(
        appBar: AppBar(title: const Text('No se pudo abrir la bandeja')),
        body: TextButton(onPressed: back, child: Text(origin.label)),
      );
    }
  }
}
