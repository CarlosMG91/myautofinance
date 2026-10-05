import 'package:flutter/material.dart';

import '../../features/movements/movements.dart';
import '../../features/movements/presentation/movement_list_controller.dart';
import '../../features/movements/presentation/movement_list_screen.dart';
import '../../features/wealth/wealth.dart';
import 'app_routes.dart';
import 'wealth_route.dart';
import 'movement_editor_route.dart';

class MovementListOrigin {
  const MovementListOrigin(this.route);
  final String route;
  String get label {
    final uri = Uri.tryParse(route);
    for (final destination in AppRoutes.destinations) {
      if (destination.path == uri?.path) {
        final a = uri?.queryParameters['a'];
        final m = uri?.queryParameters['m'];
        return '${destination.label}${a == null ? '' : ', ${m == null ? a : '$m/$a'}'}';
      }
    }
    return 'Autofinance';
  }
}

/// Los informes pueden fijar c (UUID), alcance=direct/branch o sinClasificar=1.
class MovementListRoute extends StatefulWidget {
  const MovementListRoute({
    super.key,
    required this.settings,
    required this.load,
  });
  final RouteSettings settings;
  final MovementListLoader load;
  @override
  State<MovementListRoute> createState() => _MovementListRouteState();
}

class _MovementListRouteState extends State<MovementListRoute> {
  MovementListController? _controller;
  @override
  Widget build(BuildContext context) {
    final uri = Uri.parse(widget.settings.name!);
    final params = uri.queryParameters;
    try {
      final current = madridMonth(DateTime.now());
      final month = Month(
        int.parse(params['a'] ?? current.value.substring(0, 4)),
        int.parse(params['m'] ?? current.value.substring(5, 7)),
      );
      final controller = _controller ??= MovementListController(
        load: widget.load,
        from: ValueDate.parse(params['desde'] ?? month.value),
        until: params['hasta'] != null
            ? ValueDate.parse(params['hasta']!)
            : month.next == null
            ? null
            : ValueDate.parse(month.next!.value),
        categoryId: params['c'],
        unclassified: params['sinClasificar'] == '1',
        scope: params['alcance'] == 'direct'
            ? MovementCategoryScope.direct
            : MovementCategoryScope.branch,
      );
      if (controller.unclassified && controller.categoryId != null ||
          controller.until != null &&
              controller.from.compareTo(controller.until!) >= 0) {
        controller.dispose();
        throw const MovementFailure('Periodo o categoría ambiguos.');
      }
      final width = MediaQuery.sizeOf(context).width;
      Widget navigation(bool vertical) => Wrap(
        direction: vertical ? Axis.vertical : Axis.horizontal,
        spacing: 4,
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
                onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
                  '${destination.path}?a=${controller.from.value.substring(0, 4)}&m=${controller.from.value.substring(5, 7)}',
                  (_) => false,
                ),
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
      return MovementListScreen(
        returnLabel:
            'Volver a ${widget.settings.arguments is MovementListOrigin ? (widget.settings.arguments as MovementListOrigin).label : 'Estado del mes'}',
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
        controller: controller,
        onReturn: () => Navigator.of(context).canPop()
            ? Navigator.of(context).pop()
            : Navigator.of(context)
                  .pushReplacementNamed(AppRoutes.monthlyStatus),
        onCreate: () async {
          await Navigator.of(context).pushNamed(
            '${AppRoutes.movements}/nuevo',
            arguments: MovementEditorOrigin(controller.context),
          );
        },
        onOpen: (id) async {
          await Navigator.of(context).pushNamed(
            '${AppRoutes.movements}/$id',
            arguments: MovementEditorOrigin(controller.context),
          );
        },
      );
    } catch (_) {
      return Scaffold(
        appBar: AppBar(title: const Text('No se pudo abrir este detalle')),
        body: TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Volver al origen'),
        ),
      );
    }
  }
}
