import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_routes.dart';
import '../../features/synchronization/presentation/drive_controller.dart';
import '../../features/synchronization/presentation/drive_screen.dart';
import '../../features/synchronization/presentation/local_backup_controller.dart';
import '../../features/synchronization/presentation/local_backup_screen.dart';
import '../../features/movements/movements.dart';
import '../../features/movements/presentation/category_tree_screen.dart';
import '../../features/movements/presentation/category_form_screen.dart';

/// El selector conserva su propio borrador y recibe solo el alta confirmada.
/// La pila mantiene filtros, scroll y foco del origen, sin guardarlo.
class CategoryNavigationContext {
  const CategoryNavigationContext({required this.returnLabel, this.onCreated});
  final String returnLabel;
  final ValueChanged<CategoryDetails>? onCreated;
}

/// Navegación de desarrollo, sin pantallas ni operaciones financieras.
abstract final class AppRouter {
  static Route<Object?> generateRoute(
    RouteSettings settings, {
    LocalBackupController? localBackups,
    DriveController? drive,
    CategoryManagementLoader? categories,
  }) {
    Widget page;
    final uri = Uri.tryParse(settings.name ?? '');
    if (uri?.path == AppRoutes.categories ||
        uri?.path.startsWith('${AppRoutes.categories}/') == true) {
      page = categories == null
          ? const _TechnicalPlaceholder(
              title: 'Categorías no disponibles',
              message: 'No se ha inicializado el almacenamiento local.',
            )
          : _CategoryRoute(settings: settings, loadManagement: categories);
    } else if (uri?.path == AppRoutes.drive && drive != null) {
      page = _BackupRoute(settings: settings, drive: drive);
    } else if (uri?.path == AppRoutes.localBackups ||
        uri?.path.startsWith('${AppRoutes.localBackups}/') == true) {
      page = localBackups == null
          ? const _TechnicalPlaceholder(
              title: 'Copias locales no disponibles',
              message: 'No se ha inicializado el almacenamiento local.',
            )
          : _BackupRoute(settings: settings, controller: localBackups);
    } else if (settings.name == AppRoutes.home) {
      page = _TechnicalIndex(
        showManagement:
            localBackups != null || drive != null || categories != null,
        categoriesAvailable: categories != null,
      );
    } else {
      TechnicalDestination? destination;
      for (final candidate in AppRoutes.destinations) {
        if (candidate.path == uri?.path) {
          destination = candidate;
          break;
        }
      }
      page = _TechnicalPlaceholder(
        showManagement:
            localBackups != null || drive != null || categories != null,
        categoriesAvailable: categories != null,
        title: destination?.label ?? 'Error de navegación',
        message: destination == null
            ? 'Destino desconocido · ${settings.name ?? "(sin ruta)"}'
            : 'Marcador técnico · ${destination.path}',
      );
    }
    // Conserva nombre y argumentos, también en destinos desconocidos.
    return MaterialPageRoute<Object?>(
      settings: settings,
      builder: (context) {
        if (page is _BackupRoute || localBackups == null) return page;
        return ListenableBuilder(
          listenable: localBackups,
          builder: (context, _) {
            if (!localBackups.activeAvailable) {
              return _BackupRoute(
                settings: const RouteSettings(name: AppRoutes.localBackups),
                controller: localBackups,
              );
            }
            return page;
          },
        );
      },
    );
  }
}

/// La ruta original queda en la pila: conserva periodo, scroll y foco.
class _CategoryEditorOrigin {
  const _CategoryEditorOrigin(this.origin);
  final Object? origin;
}

class _CategoryRoute extends StatelessWidget {
  const _CategoryRoute({required this.settings, required this.loadManagement});
  final RouteSettings settings;
  final CategoryManagementLoader loadManagement;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.parse(settings.name!);
    final fromTree = settings.arguments is _CategoryEditorOrigin;
    final origin = fromTree
        ? (settings.arguments as _CategoryEditorOrigin).origin
        : settings.arguments;
    final label = origin is CategoryNavigationContext
        ? origin.returnLabel
        : 'Volver a ${origin is _BackupOrigin ? origin.label : 'Autofinance'}';
    void back([CategoryDetails? saved]) {
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop(saved);
      } else {
        navigator.pushReplacementNamed(AppRoutes.home);
      }
    }

    if (uri.path == AppRoutes.categories) {
      return CategoryTreeScreen(
        loadManagement: loadManagement,
        onReturn: back,
        returnLabel: label,
        onOpenEditor: (id) async {
          final result = await Navigator.of(context).pushNamed<Object?>(
            id == null
                ? AppRoutes.newCategory
                : '${AppRoutes.categories}/${Uri.encodeComponent(id)}',
            arguments: _CategoryEditorOrigin(origin),
          );
          if (!context.mounted || result is! CategoryDetails) return null;
          if (id == null &&
              origin is CategoryNavigationContext &&
              origin.onCreated != null) {
            origin.onCreated!(result);
            back();
          }
          return result;
        },
      );
    }
    if (uri.pathSegments.length != 2 || uri.pathSegments.last.isEmpty) {
      return const _TechnicalPlaceholder(
        title: 'No se pudo abrir este detalle',
        message: 'Ruta de categoría inválida.',
      );
    }
    final creating = uri.path == AppRoutes.newCategory;
    return CategoryFormScreen(
      loadManagement: loadManagement,
      categoryId: creating ? null : uri.pathSegments.last,
      onReturn: back,
      returnLabel: fromTree ? 'Volver al árbol' : label,
      onSaved: (saved) {
        if (!fromTree && creating && origin is CategoryNavigationContext) {
          origin.onCreated?.call(saved);
        }
        back(saved);
      },
    );
  }
}

class _BackupOrigin {
  const _BackupOrigin(this.route);
  final String route;
  String get label {
    final uri = Uri.tryParse(route);
    final path = uri?.path;
    for (final destination in AppRoutes.destinations) {
      if (destination.path == path) {
        final year = int.tryParse(uri?.queryParameters['a'] ?? '');
        final month = int.tryParse(uri?.queryParameters['m'] ?? '');
        if (year != null && year >= 1 && year <= 9999) {
          if (month != null && month >= 1 && month <= 12) {
            return '${destination.label}, ${DateFormat("MMMM 'de' yyyy", 'es_ES').format(DateTime(year, month))}';
          }
          return '${destination.label}, $year';
        }
        return destination.label;
      }
    }
    return 'Autofinance';
  }
}

class _BackupRoute extends StatelessWidget {
  const _BackupRoute({required this.settings, this.controller, this.drive});
  final RouteSettings settings;
  final LocalBackupController? controller;
  final DriveController? drive;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: drive ?? controller!,
    builder: (context, _) {
      final uri = Uri.tryParse(settings.name ?? '');
      final id = uri != null && uri.pathSegments.length == 2
          ? uri.pathSegments.last
          : null;
      final origin = settings.arguments is _BackupOrigin
          ? settings.arguments! as _BackupOrigin
          : const _BackupOrigin(AppRoutes.monthlyStatus);
      void returnToOrigin() {
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
        } else {
          navigator.pushReplacementNamed(origin.route);
        }
      }

      final width = MediaQuery.sizeOf(context).width;
      // Solo las rutas técnicas existentes; no se implementa contenido financiero.
      Widget destinationButton(TechnicalDestination destination) {
        final selected = Uri.tryParse(origin.route)?.path == destination.path;
        return Semantics(
          selected: selected,
          child: TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              backgroundColor: selected ? const Color(0xffeaf3fb) : null,
              side: selected
                  ? const BorderSide(color: Color(0xff124b7a), width: 2)
                  : null,
            ),
            onPressed: drive?.busy == true
                ? null
                : () => Navigator.of(context)
                      .pushNamedAndRemoveUntil(destination.path, (_) => false),
            child: Text(
              _shortLabel(destination.path),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      }

      Widget navigation(bool vertical) {
        if (!vertical && width < 600) {
          final columns = MediaQuery.textScalerOf(context).scale(14) > 20
              ? 2
              : 3;
          return Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            children: [
              for (final destination in AppRoutes.destinations)
                SizedBox(
                  width: (width - 16) / columns,
                  child: destinationButton(destination),
                ),
            ],
          );
        }
        return Flex(
          direction: vertical ? Axis.vertical : Axis.horizontal,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final destination in AppRoutes.destinations)
              if (vertical)
                destinationButton(destination)
              else
                Expanded(child: destinationButton(destination)),
          ],
        );
      }

      final allowed = drive != null ? true : controller!.activeAvailable;
      final sidebar = allowed && width >= 840
          ? Container(
              width: width >= 1200 ? 216 : 200,
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [const Text('Autofinance'), navigation(true)],
              ),
            )
          : null;
      final bottom = allowed && width < 840
          ? SafeArea(
              child: Container(
                color: Colors.white,
                constraints: const BoxConstraints(minHeight: 64),
                child: navigation(false),
              ),
            )
          : null;
      if (drive != null) {
        return DriveScreen(
          controller: drive!,
          onReturn: returnToOrigin,
          returnLabel: 'Volver a ${origin.label}',
          onOpenBackups: () =>
              Navigator.of(context)
                  .pushNamed(AppRoutes.localBackups, arguments: origin),
          navigation: sidebar,
          bottomNavigation: bottom,
        );
      }
      return LocalBackupScreen(
        controller: controller!,
        backupId: id,
        onOpenDetail: (id) =>
            Navigator.of(context)
                .pushNamed('${AppRoutes.localBackups}/$id', arguments: origin),
        onReturn: returnToOrigin,
        returnLabel: id == null
            ? 'Volver a ${origin.label}'
            : 'Volver a Copias locales',
        navigation: controller!.activeAvailable && width >= 840
            ? Container(
                width: width >= 1200 ? 216 : 200,
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [const Text('Autofinance'), navigation(true)],
                ),
              )
            : null,
        bottomNavigation: controller!.activeAvailable && width < 840
            ? SafeArea(
                child: Container(
                  color: Colors.white,
                  constraints: const BoxConstraints(minHeight: 64),
                  child: navigation(false),
                ),
              )
            : null,
      );
    },
  );

  String _shortLabel(String path) => switch (path) {
    AppRoutes.monthlyStatus => 'Estado',
    AppRoutes.wealth => 'Patrimonio',
    AppRoutes.budget => 'Presupuesto',
    AppRoutes.actualSpending => 'Real',
    _ => 'Indicadores',
  };
}

class _TechnicalIndex extends StatelessWidget {
  const _TechnicalIndex({
    this.showManagement = false,
    this.categoriesAvailable = false,
  });
  final bool showManagement;
  final bool categoriesAvailable;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Autofinance · Base técnica'),
        actions: [
          if (showManagement)
            _ManagementMenu(categoriesAvailable: categoriesAvailable),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Navegación de desarrollo · Diseño pendiente'),
              for (final destination in AppRoutes.destinations)
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pushNamed(destination.path),
                  child: Text('${destination.label} · ${destination.path}'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TechnicalPlaceholder extends StatelessWidget {
  const _TechnicalPlaceholder({
    required this.title,
    required this.message,
    this.showManagement = false,
    this.categoriesAvailable = false,
  });
  final bool showManagement;
  final bool categoriesAvailable;

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (showManagement)
            _ManagementMenu(categoriesAvailable: categoriesAvailable),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const Text('Sin contenido de producto · Diseño pendiente'),
            TextButton(
              onPressed: () {
                final navigator = Navigator.of(context);
                if (navigator.canPop()) {
                  navigator.pop();
                } else {
                  navigator.pushReplacementNamed(AppRoutes.home);
                }
              },
              child: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManagementMenu extends StatelessWidget {
  const _ManagementMenu({this.categoriesAvailable = false});
  final bool categoriesAvailable;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Gestión',
    onSelected: (value) => Navigator.of(context).pushNamed(
      value == 'categories'
          ? AppRoutes.categories
          : value == 'drive'
          ? AppRoutes.drive
          : AppRoutes.localBackups,
      arguments: _BackupOrigin(
        ModalRoute.of(context)?.settings.name ?? AppRoutes.home,
      ),
    ),
    itemBuilder: (_) => [
      const PopupMenuItem(enabled: false, child: Text('Importar CSV')),
      PopupMenuItem(
        value: 'categories',
        enabled: categoriesAvailable,
        child: const Text('Categorías'),
      ),
      const PopupMenuItem(enabled: false, child: Text('Fichas')),
      const PopupMenuItem(value: 'drive', child: Text('Copia en Drive')),
      const PopupMenuItem(value: 'local', child: Text('Copias locales')),
    ],
    child: const Padding(padding: EdgeInsets.all(12), child: Text('Gestión')),
  );
}
