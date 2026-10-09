import 'movement_list_route.dart';
import 'pending_movement_route.dart';
import '../../features/movements/presentation/pending_movement_controller.dart';
import 'import_route.dart';
import '../../features/importing/importing.dart' show LocalCsvSelector;
import '../../features/importing/presentation/import_controller.dart';
import 'budget_route.dart';
import '../../features/budget/presentation/budget_source.dart';
import 'movement_editor_route.dart';
import 'movement_links.dart';
import 'category_navigation_context.dart';
export 'category_navigation_context.dart';
import '../../features/movements/presentation/movement_list_controller.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_routes.dart';
import 'navigation_context.dart';
import 'navigation_session.dart';
import 'session_location.dart';
import 'session_navigation_error.dart';
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
import '../../features/wealth/presentation/wealth_screen.dart';
import 'wealth_route.dart';

/// Compone las rutas de producto y los marcadores pendientes.
abstract final class AppRouter {
  static Route<Object?> generateRoute(
    RouteSettings settings, {
    LocalBackupController? localBackups,
    DriveController? drive,
    CategoryManagementLoader? categories,
    WealthManagementLoader? wealth,
    MovementListLoader? movements,
    PendingMovementLoader? pendingMovements,
    BudgetLoader? budgets,
    ImportServicesLoader? imports,
    LocalCsvSelector? csvSelector,
    bool allowTestImports = false,
    NavigationSession? navigationSession,
  }) {
    Widget page;
    final uri = Uri.tryParse(settings.name ?? '');
    var destinationSettings = settings;
    NavigationContext? invalidOrigin;
    if (navigationSession != null &&
        SessionDestination.fromPath(uri?.path ?? '') != null) {
      final result = SessionLocation.resolve(
        settings.name!,
        navigationSession,
        view: uri?.path == AppRoutes.budget && budgets != null
            ? PeriodView.monthly
            : null,
      );
      if (result is InvalidSessionLocation) {
        invalidOrigin = result.origin;
      } else {
        destinationSettings = RouteSettings(
          name: SessionLocation.encode(
            (result as ValidSessionLocation).context,
          ),
          arguments: settings.arguments,
        );
      }
    }
    if (invalidOrigin != null) {
      page = SessionNavigationError(origin: invalidOrigin);
    } else if (uri?.path == AppRoutes.importHistory ||
        uri?.path.startsWith('${AppRoutes.importHistory}/') == true) {
      page = imports == null
          ? const _TechnicalPlaceholder(
              title: 'Importaciones no disponibles',
              message: 'No se ha inicializado el almacenamiento local.',
            )
          : ImportRoute(
              settings: settings,
              load: imports,
              allowTestLaunch: allowTestImports,
              csvSelector: csvSelector,
              pendingMovements: categories == null ? null : pendingMovements,
            );
    } else if (budgets != null &&
        (uri?.path == AppRoutes.budget ||
            uri?.path.startsWith('${AppRoutes.budget}/') == true)) {
      page = BudgetRoute(
        settings: destinationSettings,
        load: budgets,
        categories: categories,
        importsAvailable: imports != null,
        pendingAvailable: pendingMovements != null && categories != null,
      );
    } else if (uri?.path == AppRoutes.pendingMovements) {
      page = pendingMovements == null || categories == null
          ? const _TechnicalPlaceholder(
              title: 'Bandeja no disponible',
              message: 'No se ha inicializado el almacenamiento local.',
            )
          : PendingMovementRoute(
              settings: settings,
              load: pendingMovements,
              categories: categories,
              onBatch: imports == null
                  ? null
                  : (context, id) async {
                      await Navigator.of(context).pushNamed(
                        "${AppRoutes.importBatches}/${Uri.encodeComponent(id)}",
                      );
                    },
            );
    } else if (uri?.path == AppRoutes.movements && movements != null) {
      page = MovementListRoute(
        settings: settings,
        load: movements,
        categories: categories,
      );
    } else if (uri?.path.startsWith('${AppRoutes.movements}/') == true &&
        movements != null) {
      page = MovementEditorRoute(
        settings: settings,
        load: movements,
        categories: categories,
      );
    } else if (wealth != null &&
        (uri?.path == AppRoutes.wealth ||
            uri?.path.startsWith('${AppRoutes.wealth}/') == true)) {
      page = _WealthRoute(
        settings: destinationSettings,
        loadManagement: wealth,
        categoriesAvailable: categories != null,
        pendingAvailable: pendingMovements != null && categories != null,
      );
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
            wealth != null ||
            movements != null ||
            imports != null,
        categoriesAvailable: categories != null,
        wealthAvailable: wealth != null,
        pendingAvailable: pendingMovements != null && categories != null,
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
            wealth != null ||
            movements != null ||
            imports != null,
        categoriesAvailable: categories != null,
        wealthAvailable: wealth != null,
        pendingAvailable: pendingMovements != null && categories != null,
        title: destination?.label ?? 'Error de navegación',
        message: destination == null
            ? 'Destino desconocido · ${settings.name ?? "(sin ruta)"}'
            : 'Marcador técnico · ${destination.path}',
        fallbackOrigin: destination == null ? navigationSession?.context : null,
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

/// Compone Patrimonio y sus formularios sin retener conexiones SQLite.
class _WealthRoute extends StatefulWidget {
  const _WealthRoute({
    required this.settings,
    required this.loadManagement,
    this.categoriesAvailable = false,
    this.pendingAvailable = false,
  });
  final RouteSettings settings;
  final WealthManagementLoader loadManagement;
  final bool categoriesAvailable;
  final bool pendingAvailable;

  @override
  State<_WealthRoute> createState() => _WealthRouteState();
}

class _WealthRouteState extends State<_WealthRoute> {
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

    if (uri?.path == AppRoutes.wealth) {
      try {
        final route = WealthRoute.parse(
          widget.settings.name!,
          defaultMonth: madridMonth(DateTime.now()),
        );
        String period(Month month) =>
            'a=${month.value.substring(0, 4)}&m=${month.value.substring(5, 7)}';
        Future<void> open(String path, Month month) async {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          final saved = await Navigator.of(context).pushNamed<Object?>(
            path == AppRoutes.pendingMovements
                ? path
                : '$path?${period(month)}',
            arguments: path == AppRoutes.pendingMovements
                ? PendingMovementOrigin(
                    route: "${AppRoutes.wealth}?${period(month)}",
                    label:
                        "Volver a Patrimonio, ${month.value.substring(0, 7)}",
                  )
                : path == AppRoutes.importCsv
                ? CsvImportOrigin(
                    '${AppRoutes.wealth}?${period(month)}',
                    'Volver a Patrimonio, ${month.value.substring(0, 7)}',
                  )
                : path == AppRoutes.movements
                ? MovementListOrigin('${AppRoutes.wealth}?${period(month)}')
                : path.startsWith(AppRoutes.accounts)
                ? _WealthOrigin(month)
                : widget.settings.arguments,
          );
          if (context.mounted && saved is WealthSnapshot) {
            _photoNotice(context, saved);
          }
        }

        return WealthScreen(
          controller: WealthController(loadManagement: widget.loadManagement),
          initialMonth: route.month!,
          onPhoto: (month) => open(AppRoutes.wealthPhoto, month),
          onAccount: (id, month) =>
              open('${AppRoutes.accounts}/${Uri.encodeComponent(id)}', month),
          onCatalog: (month) => open(AppRoutes.accounts, month),
          onReturn: Navigator.of(context).canPop() ? back : null,
          destinations: {
            for (final destination in AppRoutes.destinations)
              destination.path: switch (destination.path) {
                AppRoutes.monthlyStatus => 'Estado',
                AppRoutes.wealth => 'Patrimonio',
                AppRoutes.budget => 'Presupuesto',
                AppRoutes.actualSpending => 'Real',
                _ => 'Indicadores',
              },
          },
          onNavigate: (path, month) => Navigator.of(context)
              .pushNamedAndRemoveUntil('$path?${period(month)}', (_) => false),
          management: (month, refresh) => _ManagementMenu(
            categoriesAvailable: widget.categoriesAvailable,
            wealthAvailable: true,
            pendingAvailable: widget.pendingAvailable,
            onOpen: (path) async {
              await open(path, month);
              if (context.mounted) await refresh();
            },
          ),
        );
      } on AccountFailure catch (_) {
        // Error de navegación sin consultas ni escrituras.
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
        returnLabel: widget.settings.arguments is _WealthOrigin
            ? (widget.settings.arguments as _WealthOrigin).returnLabel
            : 'Volver al origen',
        onOpen: (id) async {
          final saved = await Navigator.of(context).pushNamed<Object?>(
            id == null
                ? AppRoutes.newAccount
                : '${AppRoutes.accounts}/${Uri.encodeComponent(id)}',
            arguments: widget.settings.arguments is _WealthOrigin
                ? _WealthOrigin(
                    (widget.settings.arguments as _WealthOrigin).month,
                    fromCatalog: true,
                  )
                : widget.settings.arguments,
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
        initialMonth: widget.settings.arguments is _WealthOrigin
            ? (widget.settings.arguments as _WealthOrigin).month
            : madridMonth(DateTime.now()),
        accountId: uri!.path == AppRoutes.newAccount
            ? null
            : uri.pathSegments.last,
        onReturn: back,
        returnLabel: widget.settings.arguments is _WealthOrigin
            ? (widget.settings.arguments as _WealthOrigin).returnLabel
            : 'Volver al origen',
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
        child: Column(
          children: [
            const Text('No se pudo abrir este detalle'),
            TextButton(onPressed: back, child: const Text('Volver al origen')),
          ],
        ),
      ),
    );
  }
}

class _WealthOrigin {
  const _WealthOrigin(this.month, {this.fromCatalog = false});
  final Month month;
  final bool fromCatalog;
  String get returnLabel => fromCatalog
      ? 'Volver a Fichas'
      : 'Volver a Patrimonio, ${month.value.substring(0, 7)}';
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
    this.pendingAvailable = false,
  });
  final bool showManagement;
  final bool categoriesAvailable;
  final bool wealthAvailable;
  final bool pendingAvailable;

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
              pendingAvailable: pendingAvailable,
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
    this.pendingAvailable = false,
    this.fallbackOrigin,
  });
  final bool showManagement;
  final bool categoriesAvailable;
  final bool wealthAvailable;
  final bool pendingAvailable;
  final NavigationContext? fallbackOrigin;

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
              pendingAvailable: pendingAvailable,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const Text('Sin contenido de producto · Diseño pendiente'),
            if (showManagement &&
                (title == 'Estado del mes' || title == 'Real anual'))
              TextButton(
                onPressed: () {
                  final origin =
                      ModalRoute.of(context)?.settings.name ??
                      AppRoutes.monthlyStatus;
                  Navigator.of(context).pushNamed(
                    MovementLinks.management(
                      origin,
                      defaultMonth: madridMonth(DateTime.now()),
                    ),
                    arguments: MovementListOrigin(origin),
                  );
                },
                child: const Text('Ver movimientos reales'),
              ),
            TextButton(
              onPressed: () {
                final navigator = Navigator.of(context);
                if (navigator.canPop()) {
                  navigator.pop();
                } else {
                  final origin = fallbackOrigin;
                  navigator.pushReplacementNamed(
                    origin == null
                        ? AppRoutes.home
                        : SessionLocation.encode(origin),
                    arguments: origin,
                  );
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
    this.pendingAvailable = false,
    this.onOpen,
  });
  final bool categoriesAvailable;
  final bool wealthAvailable;
  final bool pendingAvailable;
  final Future<void> Function(String path)? onOpen;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Gestión',
    onSelected: (value) {
      final path = value == 'pending'
          ? AppRoutes.pendingMovements
          : value == 'movements'
          ? AppRoutes.movements
          : value == 'csv'
          ? AppRoutes.importCsv
          : value == 'imports'
          ? AppRoutes.importHistory
          : value == 'categories'
          ? AppRoutes.categories
          : value == 'accounts'
          ? AppRoutes.accounts
          : value == 'drive'
          ? AppRoutes.drive
          : AppRoutes.localBackups;
      if (onOpen != null) {
        onOpen!(path);
      } else {
        Navigator.of(context).pushNamed(
          path == AppRoutes.movements
              ? MovementLinks.management(
                  ModalRoute.of(context)?.settings.name ?? AppRoutes.home,
                  defaultMonth: madridMonth(DateTime.now()),
                )
              : path,
          arguments: path == AppRoutes.pendingMovements
              ? PendingMovementOrigin(
                  route:
                      ModalRoute.of(context)?.settings.name ?? AppRoutes.home,
                  label:
                      "Volver a ${_BackupOrigin(ModalRoute.of(context)?.settings.name ?? AppRoutes.home).label}",
                )
              : path == AppRoutes.importCsv
              ? CsvImportOrigin(
                  ModalRoute.of(context)?.settings.name ?? AppRoutes.home,
                  'Volver a ${_BackupOrigin(ModalRoute.of(context)?.settings.name ?? AppRoutes.home).label}',
                )
              : path == AppRoutes.movements
              ? MovementListOrigin(
                  ModalRoute.of(context)?.settings.name ?? AppRoutes.home,
                )
              : _BackupOrigin(
                  ModalRoute.of(context)?.settings.name ?? AppRoutes.home,
                ),
        );
      }
    },
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'csv', child: Text('Importar CSV')),
      const PopupMenuItem(enabled: false, child: Text('Importar XLS')),
      const PopupMenuItem(
        value: 'imports',
        child: Text('Historial de importaciones'),
      ),
      const PopupMenuItem(value: 'movements', child: Text('Movimientos')),
      PopupMenuItem(
        value: 'pending',
        enabled: pendingAvailable,
        child: const Text('Pendientes de categorizar'),
      ),
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
