import 'package:flutter/material.dart';

import '../features/movements/movements.dart';
import '../features/movements/presentation/category_selector.dart';
import '../features/movements/presentation/category_tree_screen.dart';
import 'navigation/app_routes.dart';
import 'navigation/category_navigation_context.dart';

/// La pantalla consumidora conserva su borrador y solo aplica un resultado no null.
/// Usa las rutas aprobadas sin modificar Gestión ni rutas de EP-009.
Future<CategoryDetails?> selectCategory(
  BuildContext context, {
  required CategoryManagementLoader loadManagement,
  String? selectedId,
}) => Navigator.of(context).push<CategoryDetails>(
  MaterialPageRoute<CategoryDetails>(
    builder: (selectorContext) => CategorySelector(
      loadManagement: loadManagement,
      selectedId: selectedId,
      onReturn: (selection) => Navigator.of(selectorContext).pop(selection),
      onCreate: () async {
        final result = await Navigator.of(selectorContext).pushNamed<Object?>(
          AppRoutes.newCategory,
          arguments: const CategoryNavigationContext(
            returnLabel: 'Volver al selector',
          ),
        );
        return result is CategoryDetails ? result : null;
      },
    ),
  ),
);
