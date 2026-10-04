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
import '../../features/wealth/wealth.dart';
import '../../features/wealth/presentation/account_catalog_screen.dart';
import '../../features/wealth/presentation/account_form_screen.dart';
import '../../features/wealth/presentation/wealth_photo_screen.dart';
import 'wealth_route.dart';

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
    WealthManagementLoader? wealth,
  }) {
    Widget page;
    final uri = Uri.tryParse(settings.name ?? '');
    if (wealth != null &&
        (uri?.path == AppRoutes.wealth ||
            uri?.path.startsWith('${AppRoutes.wealth}/') == true)) {
      page = _WealthRoute(settings: settings, loadManagement: wealth);
    } else if (uri?.path == AppRoutes.categories ||
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
            localBackups != null ||
            drive != null ||
            categories != null ||
            wealth != null,
        categoriesAvailable: categories != null,
        wealthAvailable: wealth != null,
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
            localBackups != null ||
            drive != null ||
            categories != null ||
            wealth != null,
        categoriesAvailable: categories != null,
        wealthAvailable: wealth != null,
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

/// Host de composición de MA-TSK-071; los formularios y la vista financiera
/// completa pertenecen a los siguientes tickets de EP-009.
class _WealthRoute extends StatefulWidget {
  const _WealthRoute({required this.settings, required this.loadManagement});
  final RouteSettings settings;
  final WealthManagementLoader loadManagement;

  @override
  State<_WealthRoute> createState() => _WealthRouteState();
}

class _WealthRouteState extends State<_WealthRoute> {
  late Future<Object?> data = _load();

  Future<Object?> _load() async {
    final route = WealthRoute.parse(
      widget.settings.name!,
      defaultMonth: madridMonth(DateTime.now()),
    );
    return route.load(WealthController(loadManagement: widget.loadManagement));
  }

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(widget.settings.name ?? '');
    void back([Object? result]) {
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop(result);
      } else {
        final origin = widget.settings.arguments;
        navigator.pushReplacementNamed(
          origin is _BackupOrigin ? origin.route : AppRoutes.monthlyStatus,
        );
      }
    }

    if (uri?.path == AppRoutes.wealthPhoto) {
      final WealthRoute route;
      try {
        route = WealthRoute.parse(
          widget.settings.name!,
          defaultMonth: madridMonth(DateTime.now()),
        );
      } on AccountFailure catch (e) {
        return Scaffold(
          appBar: AppBar(title: const Text('Patrimonio')),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('No se pudo abrir este detalle'),
                  Text(e.message),
                  TextButton(
                    onPressed: back,
                    child: const Text('Volver al origen'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      final period =
          'a=${route.month!.value.substring(0, 4)}&m=${route.month!.value.substring(5, 7)}';
      return WealthPhotoScreen(
        controller: WealthController(loadManagement: widget.loadManagement),
        month: route.month!,
        onReturn: () {
          if (Navigator.of(context).canPop()) {
            back();
          } else {
            Navigator.of(context).pushReplacementNamed(
              '${AppRoutes.wealth}?$period',
              arguments: widget.settings.arguments,
            );
          }
        },
        onSaved: (saved) {
          if (Navigator.of(context).canPop()) {
            back(saved);
          } else {
            Navigator.of(context).pushReplacementNamed(
              '${AppRoutes.wealth}?$period',
              arguments: widget.settings.arguments,
            );
            _photoNotice(context, saved);
          }
        },
        destinations: {
          for (final destination in AppRoutes.destinations)
            destination.path: destination.label,
        },
        onNavigate: (path) => Navigator.of(context).pushReplacementNamed(
          '$path?$period',
          arguments: widget.settings.arguments,
        ),
      );
    }

    if (uri?.path == AppRoutes.accounts) {
      return AccountCatalogScreen(
        controller: WealthController(loadManagement: widget.loadManagement),
        onReturn: back,
        onOpen: (id) async {
          final saved = await Navigator.of(context).pushNamed<Object?>(
            id == null
                ? AppRoutes.newAccount
                : '${AppRoutes.accounts}/${Uri.encodeComponent(id)}',
            arguments: widget.settings.arguments,
          );
          if (context.mounted && saved is AccountDetails) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Ficha guardada')));
          }
        },
      );
    }
    if (uri?.pathSegments.length == 3 && uri?.pathSegments[1] == 'fichas') {
      return AccountFormScreen(
        loadManagement: widget.loadManagement,
        initialMonth: madridMonth(DateTime.now()),
        accountId: uri!.path == AppRoutes.newAccount
            ? null
            : uri.pathSegments.last,
        onReturn: back,
        onSaved: (saved) {
          if (Navigator.of(context).canPop()) {
            back(saved);
          } else {
            Navigator.of(context).pushReplacementNamed(AppRoutes.accounts);
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Ficha guardada')));
          }
        },
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Patrimonio')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: FutureBuilder<Object?>(
            future: data,
            builder: (context, snapshot) {
              void back() {
                final navigator = Navigator.of(context);
                if (navigator.canPop()) {
                  navigator.pop();
                } else {
                  final origin = widget.settings.arguments;
                  final month = madridMonth(DateTime.now()).value;
                  navigator.pushReplacementNamed(
                    origin is _BackupOrigin
                        ? origin.route
                        : '${AppRoutes.monthlyStatus}?a=${month.substring(0, 4)}&m=${month.substring(5, 7)}',
                  );
                }
              }

              final value = snapshot.data;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (snapshot.connectionState != ConnectionState.done)
                    const LinearProgressIndicator()
                  else if (snapshot.hasError)
                    const Text('No se pudo abrir este detalle')
                  else ...[
                    const Text('Consulta de Patrimonio'),
                    if (value is List<AccountRecord>)
                      for (final account in value)
                        TextButton(
                          onPressed: () => Navigator.of(context).pushNamed(
                            '${AppRoutes.accounts}/${Uri.encodeComponent(account.id)}',
                            arguments: widget.settings.arguments,
                          ),
                          child: Text(account.name),
                        ),
                    if (value is AccountDetails) ...[
                      Text(value.account.name),
                      Text('Alta: ${value.account.activeFrom.value}'),
                      if (value.account.activeThrough != null)
                        Text('Baja: ${value.account.activeThrough!.value}'),
                      Text('Periodos de liquidez: ${value.history.length}'),
                    ],
                    if (value is WealthSnapshot) ...[
                      Text('Foto del día 1 · ${value.month.value}'),
                      Text(switch (value.status) {
                        WealthSnapshotStatus.absent =>
                          'Sin dato: falta foto patrimonial',
                        WealthSnapshotStatus.incomplete =>
                          'Sin dato: foto patrimonial incompleta',
                        WealthSnapshotStatus.complete => 'Foto completa',
                      }),
                      for (final account in value.pending)
                        Text('Pendiente: ${account.name}'),
                      FilledButton(
                        onPressed: () async {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          final month = value.month.value;
                          final saved = await Navigator.of(context)
                              .pushNamed<Object?>(
                                '${AppRoutes.wealthPhoto}?a=${month.substring(0, 4)}&m=${month.substring(5, 7)}',
                                arguments: widget.settings.arguments,
                              );
                          if (!context.mounted || saved is! WealthSnapshot) {
                            return;
                          }
                          setState(() {
                            data = _load();
                          });
                          _photoNotice(context, saved);
                        },
                        child: const Text('Registrar / editar foto'),
                      ),
                    ],
                  ],
                  TextButton(
                    onPressed: back,
                    child: const Text('Volver al origen'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

void _photoNotice(BuildContext context, WealthSnapshot saved) {
  final status = switch (saved.status) {
    WealthSnapshotStatus.absent => 'Sin dato: falta foto patrimonial',
    WealthSnapshotStatus.incomplete =>
      'Foto incompleta. Pendientes: ${saved.pending.map((a) => a.name).join(', ')}',
    WealthSnapshotStatus.complete => 'Foto completa',
  };
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Foto guardada · ${saved.month.value}. $status')),
  );
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
    this.wealthAvailable = false,
  });
  final bool showManagement;
  final bool categoriesAvailable;
  final bool wealthAvailable;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Autofinance · Base técnica'),
        actions: [
          if (showManagement)
            _ManagementMenu(
              categoriesAvailable: categoriesAvailable,
              wealthAvailable: wealthAvailable,
            ),
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
    this.wealthAvailable = false,
  });
  final bool showManagement;
  final bool categoriesAvailable;
  final bool wealthAvailable;

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (showManagement)
            _ManagementMenu(
              categoriesAvailable: categoriesAvailable,
              wealthAvailable: wealthAvailable,
            ),
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
  const _ManagementMenu({
    this.categoriesAvailable = false,
    this.wealthAvailable = false,
  });
  final bool categoriesAvailable;
  final bool wealthAvailable;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Gestión',
    onSelected: (value) => Navigator.of(context).pushNamed(
      value == 'categories'
          ? AppRoutes.categories
          : value == 'accounts'
          ? AppRoutes.accounts
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
      PopupMenuItem(
        value: 'accounts',
        enabled: wealthAvailable,
        child: const Text('Fichas'),
      ),
      const PopupMenuItem(value: 'drive', child: Text('Copia en Drive')),
      const PopupMenuItem(value: 'local', child: Text('Copias locales')),
    ],
    child: const Padding(padding: EdgeInsets.all(12), child: Text('Gestión')),
  );
}
