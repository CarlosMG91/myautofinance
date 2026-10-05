import 'package:flutter/material.dart';

import '../../features/movements/movements.dart';
import '../../features/movements/presentation/movement_form_screen.dart';
import '../../features/movements/presentation/movement_list_controller.dart';
import '../../features/movements/presentation/category_tree_screen.dart';
import '../category_selector_navigation.dart';
import 'app_routes.dart';
import 'wealth_route.dart';
import 'movement_links.dart';

class MovementEditorOrigin {
  const MovementEditorOrigin(this.context, {this.listRoute});
  final MovementListContext context;
  final String? listRoute;
}

class MovementEditorRoute extends StatelessWidget {
  const MovementEditorRoute({
    super.key,
    required this.settings,
    required this.load,
    this.categories,
  });
  final RouteSettings settings;
  final MovementListLoader load;
  final CategoryManagementLoader? categories;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(settings.name ?? '');
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    String fallback = AppRoutes.monthlyStatus;
    void back([MovementRecord? saved]) {
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop(saved);
      } else {
        final origin = settings.arguments;
        nav.pushReplacementNamed(
          origin is MovementEditorOrigin && origin.listRoute != null
              ? origin.listRoute!
              : fallback,
        );
      }
    }

    try {
      if (uri == null ||
          uri.pathSegments.length != 2 ||
          uri.queryParameters.containsKey('a') !=
              uri.queryParameters.containsKey('m')) {
        throw const MovementFailure('Ruta inválida.');
      }
      final query = MovementLinks.parse(
        uri.replace(path: AppRoutes.movements).toString(),
        defaultMonth: madridMonth(DateTime.now()),
      );
      final origin = settings.arguments is MovementEditorOrigin
          ? (settings.arguments as MovementEditorOrigin).context
          : null;
      final date = origin?.from ?? query.from;
      fallback = MovementLinks.list(
        query,
        origin: MovementLinks.origin(uri.toString()),
      );
      final id = uri.pathSegments.last == 'nuevo'
          ? null
          : uri.pathSegments.last;
      if (id != null) MovementSelection([id]);
      return MovementFormScreen(
        load: () async {
          final editor = (await load()).editor;
          if (editor == null) {
            throw const MovementFailure(
              'Gestión de movimientos no disponible.',
            );
          }
          return editor();
        },
        initialDate: date,
        returnLabel: origin == null
            ? 'Volver al origen'
            : 'Volver a Movimientos',
        id: id,
        onReturn: back,
        onSaved: (saved) {
          back(saved);
          final outside =
              saved.data.valueDate.value.substring(0, 7) !=
              date.value.substring(0, 7);
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Movimiento guardado en ${saved.data.valueDate.value.substring(0, 7)}',
              ),
              action: outside
                  ? SnackBarAction(
                      label: 'Ver mes',
                      onPressed: () {
                        navigator.pushNamed(
                          '${AppRoutes.movements}?a=${saved.data.valueDate.value.substring(0, 4)}&m=${saved.data.valueDate.value.substring(5, 7)}',
                        );
                      },
                    )
                  : null,
            ),
          );
        },
        onDeleted: () {
          back();
          messenger.showSnackBar(
            const SnackBar(content: Text('Movimiento borrado')),
          );
        },
        selectCategory: (selectedId) async {
          if (categories == null) {
            throw const MovementFailure('Categorías no disponibles.');
          }
          return selectCategory(
            context,
            loadManagement: categories!,
            selectedId: selectedId,
          );
        },
        onManageAccounts: () =>
            Navigator.of(context).pushReplacementNamed(AppRoutes.accounts),
        onManageCategories: categories == null
            ? null
            : () => navigator.pushReplacementNamed(AppRoutes.categories),
        destinations: {
          for (final d in AppRoutes.destinations)
            switch (d.path) {
              AppRoutes.monthlyStatus => 'Estado',
              AppRoutes.wealth => 'Patrimonio',
              AppRoutes.budget => 'Presupuesto',
              AppRoutes.actualSpending => 'Real',
              _ => 'Indicadores',
            }: () => Navigator.of(context).pushNamedAndRemoveUntil(
              '${d.path}?a=${date.value.substring(0, 4)}&m=${date.value.substring(5, 7)}',
              (_) => false,
            ),
        },
      );
    } catch (_) {
      return Scaffold(
        appBar: AppBar(title: const Text('No se pudo abrir este detalle')),
        body: TextButton(
          onPressed: back,
          child: const Text('Volver al origen'),
        ),
      );
    }
  }
}
