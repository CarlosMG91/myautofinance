import 'package:flutter/material.dart';

import '../../features/movements/movements.dart';
import '../../features/movements/presentation/movement_list_controller.dart';
import '../../features/movements/presentation/movement_list_screen.dart';
import 'app_routes.dart';
import 'wealth_route.dart';
import 'movement_editor_route.dart';
import 'movement_links.dart';
import '../category_selector_navigation.dart';
import '../../features/movements/presentation/category_tree_screen.dart';

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
    this.categories,
  });
  final RouteSettings settings;
  final MovementListLoader load;
  final CategoryManagementLoader? categories;
  @override
  State<MovementListRoute> createState() => _MovementListRouteState();
}

class _MovementListRouteState extends State<MovementListRoute> {
  MovementListController? _controller;
  @override
  Widget build(BuildContext context) {
    try {
      final query = MovementLinks.parse(
        widget.settings.name!,
        defaultMonth: madridMonth(DateTime.now()),
      );
      final controller = _controller ??= MovementListController(
        load: widget.load,
        from: query.from,
        until: query.until,
        categoryId: query.categoryId,
        unclassified: query.unclassified,
        scope: query.scope,
        accountId: query.accountId,
        concept: query.concept,
      );
      final origin = widget.settings.arguments is MovementListOrigin
          ? (widget.settings.arguments as MovementListOrigin).route
          : MovementLinks.origin(widget.settings.name!) ??
                AppRoutes.monthlyStatus;
      String currentRoute() => MovementLinks.list(
        MovementListQuery(
          from: controller.from,
          until: controller.until,
          accountId: controller.accountId,
          categoryId: controller.categoryId,
          scope: controller.scope,
          unclassified: controller.unclassified,
          concept: controller.concept,
        ),
        origin: origin,
      );
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
                onPressed: controller.batchActive
                    ? null
                    : () => Navigator.of(context).pushNamedAndRemoveUntil(
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
        returnLabel: 'Volver a ${MovementListOrigin(origin).label}',
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
            : Navigator.of(context).pushReplacementNamed(origin),
        selectCategory: widget.categories == null
            ? null
            : () => selectCategory(context, loadManagement: widget.categories!),
        onCreate: () async {
          await Navigator.of(context).pushNamed(
            '${AppRoutes.movements}/nuevo',
            arguments: MovementEditorOrigin(
              controller.context,
              listRoute: currentRoute(),
            ),
          );
        },
        onOpen: (id) async {
          await Navigator.of(context).pushNamed(
            '${AppRoutes.movements}/$id',
            arguments: MovementEditorOrigin(
              controller.context,
              listRoute: currentRoute(),
            ),
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
