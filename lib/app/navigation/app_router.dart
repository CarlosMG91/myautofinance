import 'movement_list_route.dart';
import 'pending_movement_route.dart';
import '../../features/movements/presentation/pending_movement_controller.dart';
import 'import_route.dart';
import '../../features/importing/importing.dart' show LocalCsvSelector;
import '../../features/importing/presentation/import_controller.dart';
import 'budget_route.dart';
import 'annual_budget_navigation.dart';
import 'annual_actual_route.dart';
import '../../features/actual_spending/presentation/annual_actual_screen.dart';
import 'monthly_status_route.dart';
import '../../features/monthly_status/presentation/monthly_status_screen.dart';
import '../../features/budget/presentation/budget_source.dart';
import 'movement_editor_route.dart';
import 'movement_links.dart';
import 'category_navigation_context.dart';
export 'category_navigation_context.dart';
import '../../features/movements/presentation/movement_list_controller.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../ui/autofinance_ui.dart';
import '../../core/modules/feature_module.dart' show ModuleId;

import 'app_routes.dart';
import 'navigation_context.dart';
import 'navigation_session.dart';
import 'navigation_session_scope.dart';
import 'navigation_period.dart';
import 'period_controls.dart';
import 'primary_navigation.dart';
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
    AnnualBudgetBuilder? annualBudgetBuilder,
    MonthlyStatusLoader? monthlyStatus,
    AnnualActualLoader? annualActual,
    ImportServicesLoader? imports,
    LocalCsvSelector? csvSelector,
    bool allowTestImports = false,
    NavigationSession? navigationSession,
  }) {
    final originalSettings = settings;
    final raw = Uri.tryParse(settings.name ?? '');
    if (raw != null && AppRoutes.contentPath(raw.path) != raw.path) {
      settings = RouteSettings(
        name: raw.replace(path: AppRoutes.contentPath(raw.path)).toString(),
        arguments: settings.arguments,
      );
    }
    Widget page;
    final uri = Uri.tryParse(settings.name ?? '');
    var destinationSettings = settings;
    NavigationContext? invalidOrigin;
    if (navigationSession != null &&
        SessionDestination.fromPath(uri?.path ?? '') != null) {
      final result = SessionLocation.resolve(settings.name!, navigationSession);
      if (result is InvalidSessionLocation) {
        invalidOrigin = result.origin;
      } else {
        final selected = (result as ValidSessionLocation).context;
        destinationSettings = RouteSettings(
          name: SessionLocation.encode(selected),
          arguments:
              settings.arguments ??
              (selected.destination == SessionDestination.budget
                  ? selected
                  : null),
        );
      }
    }
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasFragment ||
        uri.queryParametersAll.values.any((v) => v.length != 1)) {
      page = _TechnicalPlaceholder(
        title: 'No se pudo abrir este detalle',
        message: 'Ruta de navegación inválida.',
        fallbackOrigin: navigationSession?.context,
      );
    } else if (invalidOrigin != null) {
      page = SessionNavigationError(origin: invalidOrigin);
    } else if (uri.path == AppRoutes.start && monthlyStatus != null) {
      page = MonthlyStatusRoute(
        settings: settings,
        load: monthlyStatus,
        session: navigationSession,
        home: true,
        wealth: wealth,
        onImport: imports == null
            ? null
            : (context, origin) async {
                await Navigator.of(context).pushNamed(
                  AppRoutes.importCsv,
                  arguments: CsvImportOrigin(origin, 'Volver a Inicio'),
                );
              },
        onCategorize: pendingMovements == null || categories == null
            ? null
            : (context, origin) async {
                await Navigator.of(context).pushNamed(
                  AppRoutes.pendingMovements,
                  arguments: PendingMovementOrigin(
                    route: origin,
                    label: 'Volver a Inicio',
                  ),
                );
              },
        management: (origin, refresh) => const SizedBox.shrink(),
      );
    } else if (const {
      AppRoutes.start,
      AppRoutes.analysis,
      AppRoutes.more,
      AppRoutes.management,
      AppRoutes.diagnostics,
    }.contains(uri.path)) {
      page = _ShellEntry(
        destination: SessionDestination.fromPath(uri.path)!,
        session: navigationSession,
        management: _ManagementMenu(
          categoriesAvailable: categories != null,
          wealthAvailable: wealth != null,
          pendingAvailable: pendingMovements != null && categories != null,
          importsAvailable: imports != null,
          driveAvailable: drive != null,
          backupsAvailable: localBackups != null,
          origin: navigationSession == null
              ? null
              : () => SessionLocation.encode(navigationSession.context),
        ),
      );
    } else if (uri.path == AppRoutes.monthlyStatus && monthlyStatus != null) {
      page = MonthlyStatusRoute(
        settings: settings,
        load: monthlyStatus,
        session: navigationSession,
        management: (origin, refresh) => _ManagementMenu(
          categoriesAvailable: categories != null,
          wealthAvailable: wealth != null,
          pendingAvailable: pendingMovements != null && categories != null,
          origin: origin,
          onReturned: refresh,
        ),
      );
    } else if (uri.path == AppRoutes.actualSpending && annualActual != null) {
      page = AnnualActualRoute(
        settings: originalSettings,
        load: annualActual,
        session: navigationSession,
        detail: raw?.path == AppRoutes.actualDetail,
      );
    } else if (uri.path == AppRoutes.importHistory ||
        uri.path.startsWith('${AppRoutes.importHistory}/') == true) {
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
        (uri.path == AppRoutes.budget ||
            uri.path.startsWith('${AppRoutes.budget}/') == true)) {
      page = BudgetRoute(
        settings: destinationSettings,
        load: budgets,
        categories: categories,
        importsAvailable: imports != null,
        pendingAvailable: pendingMovements != null && categories != null,
        navigationSession: navigationSession,
        annualBuilder: annualBudgetBuilder,
        annualManagement: (origin, canLeave, refresh) => _ManagementMenu(
          categoriesAvailable: categories != null,
          wealthAvailable: wealth != null,
          pendingAvailable: pendingMovements != null && categories != null,
          origin: origin,
          beforeOpen: canLeave,
          onReturned: refresh,
        ),
      );
    } else if (uri.path == AppRoutes.pendingMovements) {
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
    } else if (uri.path == AppRoutes.movements && movements != null) {
      page = MovementListRoute(
        settings: settings,
        load: movements,
        categories: categories,
        navigationSession: navigationSession,
      );
    } else if (uri.path.startsWith('${AppRoutes.movements}/') == true &&
        movements != null) {
      page = MovementEditorRoute(
        settings: settings,
        load: movements,
        categories: categories,
        navigationSession: navigationSession,
      );
    } else if (wealth != null &&
        (uri.path == AppRoutes.wealth ||
            uri.path.startsWith('${AppRoutes.wealth}/') == true)) {
      page = _WealthRoute(
        settings: destinationSettings,
        loadManagement: wealth,
        categoriesAvailable: categories != null,
        pendingAvailable: pendingMovements != null && categories != null,
        navigationSession: navigationSession,
      );
    } else if (uri.path == AppRoutes.categories ||
        uri.path.startsWith('${AppRoutes.categories}/') == true) {
      page = categories == null
          ? const _TechnicalPlaceholder(
              title: 'Categorías no disponibles',
              message: 'No se ha inicializado el almacenamiento local.',
            )
          : _CategoryRoute(settings: settings, loadManagement: categories);
    } else if (uri.path == AppRoutes.drive && drive != null) {
      page = _BackupRoute(settings: settings, drive: drive);
    } else if (uri.path == AppRoutes.localBackups ||
        uri.path.startsWith('${AppRoutes.localBackups}/') == true) {
      page = localBackups == null
          ? const _TechnicalPlaceholder(
              title: 'Copias locales no disponibles',
              message: 'No se ha inicializado el almacenamiento local.',
            )
          : _BackupRoute(settings: settings, controller: localBackups);
    } else {
      TechnicalDestination? destination;
      for (final candidate in AppRoutes.destinations) {
        if (candidate.path == uri.path) {
          destination = candidate;
          break;
        }
      }
      if (uri.path == AppRoutes.movements) {
        destination = const TechnicalDestination(
          AppRoutes.movements,
          ModuleId.movements,
          'Movimientos',
        );
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
        navigationSession: destination == null ? null : navigationSession,
      );
    }
    // Conserva nombre y argumentos, también en destinos desconocidos.
    return MaterialPageRoute<Object?>(
      settings: originalSettings,
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
    this.navigationSession,
  });
  final RouteSettings settings;
  final WealthManagementLoader loadManagement;
  final bool categoriesAvailable;
  final bool pendingAvailable;
  final NavigationSession? navigationSession;

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
                : path == AppRoutes.movements
                ? MovementLinks.management(
                    '${AppRoutes.wealth}?${period(month)}',
                    defaultMonth: month,
                  )
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
          shell: widget.navigationSession == null
              ? null
              : (body, scroll, month, select, refresh) => PrimaryNavigation(
                  session: widget.navigationSession!,
                  title: 'Patrimonio',
                  scrollController: scroll,
                  periodControl: PeriodControls(
                    session: widget.navigationSession!,
                    beforeChange: (period) async {
                      select(period.civilMonth);
                      return true;
                    },
                  ),
                  child: body,
                ),
          controller: WealthController(loadManagement: widget.loadManagement),
          initialMonth: route.month!,
          initialScrollOffset: widget.settings.arguments is NavigationContext
              ? (widget.settings.arguments as NavigationContext).scrollOffset
              : 0,
          initialFocus: widget.settings.arguments is NavigationContext
              ? (widget.settings.arguments as NavigationContext).focus
              : null,
          onOrigin: widget.navigationSession == null
              ? null
              : (offset, focus) {
                  final session = widget.navigationSession!;
                  session.setContext(
                    session.context.withPosition(offset, focus),
                    deferNotification: true,
                  );
                },
          periodControls: widget.navigationSession == null
              ? null
              : (selected, select) => PeriodControls(
                  session: widget.navigationSession!,
                  beforeChange: (period) async {
                    select(period.civilMonth);
                    return true;
                  },
                ),
          onPeriodChanged: widget.navigationSession == null
              ? null
              : (month) => widget.navigationSession!.selectPeriod(
                  NavigationPeriod.fromMonth(month),
                ),
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
    final destination = SessionDestination.fromPath(path ?? '');
    return destination == null
        ? 'Autofinance'
        : PrimaryNavigation.labels[destination]!;
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
          : const _BackupOrigin(AppRoutes.start);
      void returnToOrigin() {
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
        } else {
          navigator.pushReplacementNamed(origin.route);
        }
      }

      final session = NavigationSessionScope.maybeOf(context);
      Widget shell(Widget body) => PrimaryNavigation(
        session: session!,
        title: drive != null
            ? 'Copia en Drive'
            : id == null
            ? 'Copias locales'
            : 'Detalle de copia local',
        backLabel: id == null
            ? 'Volver a ${origin.label}'
            : 'Volver a Copias locales',
        selectedDestination:
            SessionDestination.fromPath(
              Uri.tryParse(origin.route)?.path ?? '',
            ) ??
            SessionDestination.management,
        navigationAvailable: controller?.activeAvailable ?? true,
        beforeNavigate: () async => !(drive?.busy ?? controller!.busy),
        periodControl: IgnorePointer(
          ignoring: drive?.busy ?? controller!.busy,
          child: PeriodControls(session: session),
        ),
        onBack: controller?.activeAvailable == false && id == null
            ? null
            : () async {
                if (drive?.busy ?? controller!.busy) return false;
                returnToOrigin();
                return true;
              },
        contextTrail: Text(
          controller?.activeAvailable == false
              ? 'Recuperación local · sin base activa'
              : 'Origen: ${origin.label}',
        ),
        child: body,
      );
      if (drive != null) {
        return DriveScreen(
          controller: drive!,
          onReturn: returnToOrigin,
          returnLabel: 'Volver a ${origin.label}',
          onOpenBackups: () =>
              Navigator.of(context)
                  .pushNamed(AppRoutes.localBackups, arguments: origin),
          shell: session == null ? null : shell,
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
        shell: session == null ? null : shell,
      );
    },
  );
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
    this.navigationSession,
  });
  final bool showManagement;
  final bool categoriesAvailable;
  final bool wealthAvailable;
  final bool pendingAvailable;
  final NavigationContext? fallbackOrigin;
  final NavigationSession? navigationSession;

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final session = navigationSession;
    if (session != null) {
      return PrimaryNavigation(
        session: session,
        title: title,
        actions: [
          if (showManagement)
            _ManagementMenu(
              categoriesAvailable: categoriesAvailable,
              wealthAvailable: wealthAvailable,
              pendingAvailable: pendingAvailable,
              origin: () => SessionLocation.encode(session.context),
            ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(message),
            const Text('Sin contenido de producto · Diseño pendiente'),
            if (showManagement &&
                (title == 'Estado del mes' || title == 'Real anual'))
              TextButton(
                onPressed: () {
                  final origin = SessionLocation.encode(session.context);
                  Navigator.of(context).pushNamed(
                    MovementLinks.management(
                      origin,
                      defaultMonth: session.period.civilMonth,
                    ),
                    arguments: MovementListOrigin(origin),
                  );
                },
                child: const Text('Ver movimientos reales'),
              ),
          ],
        ),
      );
    }
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
    this.importsAvailable = true,
    this.driveAvailable = true,
    this.backupsAvailable = true,
    this.onOpen,
    this.origin,
    this.onReturned,
    this.beforeOpen,
  });
  final bool categoriesAvailable, wealthAvailable, pendingAvailable;
  final bool importsAvailable, driveAvailable, backupsAvailable;
  final Future<void> Function(String path)? onOpen;
  final String Function()? origin;
  final Future<void> Function()? onReturned;
  final Future<bool> Function()? beforeOpen;

  List<({String id, String label, String path, bool enabled, IconData icon})>
  get entries => [
    (
      id: 'csv',
      label: 'Importar CSV',
      path: AppRoutes.importCsv,
      enabled: importsAvailable,
      icon: AfIcons.importFile,
    ),
    (
      id: 'openbank',
      label: 'Importar Openbank',
      path: '/importaciones/openbank',
      enabled: false,
      icon: AfIcons.importFile,
    ),
    (
      id: 'imports',
      label: 'Historial de importaciones',
      path: AppRoutes.importHistory,
      enabled: importsAvailable,
      icon: AfIcons.importFile,
    ),
    (
      id: 'movements',
      label: 'Movimientos',
      path: AppRoutes.movements,
      enabled: true,
      icon: AfIcons.receipt,
    ),
    (
      id: 'pending',
      label: 'Pendientes de categorizar',
      path: AppRoutes.pendingMovements,
      enabled: pendingAvailable,
      icon: AfIcons.category,
    ),
    (
      id: 'categories',
      label: 'Categorías',
      path: AppRoutes.categories,
      enabled: categoriesAvailable,
      icon: AfIcons.category,
    ),
    (
      id: 'accounts',
      label: 'Fichas',
      path: AppRoutes.accounts,
      enabled: wealthAvailable,
      icon: AfIcons.account,
    ),
    (
      id: 'drive',
      label: 'Copia en Drive',
      path: AppRoutes.drive,
      enabled: driveAvailable,
      icon: AfIcons.upload,
    ),
    (
      id: 'local',
      label: 'Copias locales',
      path: AppRoutes.localBackups,
      enabled: backupsAvailable,
      icon: AfIcons.download,
    ),
    (
      id: 'diagnostics',
      label: 'Diagnóstico de coherencia',
      path: AppRoutes.diagnostics,
      enabled: true,
      icon: AfIcons.analysis,
    ),
  ];

  Future<void> open(BuildContext context, String value) async {
    final entry = entries.firstWhere((e) => e.id == value);
    if (!entry.enabled) return;
    if (beforeOpen != null && !await beforeOpen!()) return;
    if (!context.mounted) return;
    final session = NavigationSessionScope.maybeOf(context);
    final source =
        origin?.call() ??
        ModalRoute.of(context)?.settings.name ??
        AppRoutes.home;
    final path = entry.path;
    if (onOpen != null) {
      await onOpen!(path);
    } else {
      await Navigator.of(context).pushNamed(
        path == AppRoutes.movements
            ? MovementLinks.management(
                source,
                defaultMonth:
                    session?.period.civilMonth ?? madridMonth(DateTime.now()),
              )
            : path,
        arguments: path == AppRoutes.pendingMovements
            ? PendingMovementOrigin(
                route: source,
                label: 'Volver a ${_BackupOrigin(source).label}',
              )
            : path == AppRoutes.importCsv
            ? CsvImportOrigin(source, 'Volver a ${_BackupOrigin(source).label}')
            : path == AppRoutes.movements
            ? MovementListOrigin(source, context: session?.context)
            : _BackupOrigin(source),
      );
      if (context.mounted) await onReturned?.call();
    }
  }

  List<Widget> links(BuildContext context) => [
    for (final e in entries)
      AfAction(
        label: e.label,
        icon: e.icon,
        unavailableReason: e.enabled
            ? null
            : e.id == 'openbank'
            ? 'Recorrido pendiente de conectar.'
            : 'Servicio local no disponible.',
        onPressed: e.enabled ? () => open(context, e.id) : null,
      ),
  ];

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Gestión',
    onSelected: (value) => open(context, value),
    itemBuilder: (_) => [
      for (final e in entries)
        PopupMenuItem(value: e.id, enabled: e.enabled, child: Text(e.label)),
    ],
    child: const Padding(padding: EdgeInsets.all(12), child: Text('Gestión')),
  );
}

/// Agrupaciones de rutas y slots de entrada; ninguna cifra inventada.
class _ShellEntry extends StatefulWidget {
  const _ShellEntry({
    required this.destination,
    required this.management,
    this.session,
  });
  final SessionDestination destination;
  final NavigationSession? session;
  final _ManagementMenu management;
  @override
  State<_ShellEntry> createState() => _ShellEntryState();
}

class _ShellEntryState extends State<_ShellEntry> {
  late final _session = widget.session ?? NavigationSession();
  @override
  void initState() {
    super.initState();
    if (widget.session == null) _session.changeDestination(widget.destination);
  }

  @override
  void dispose() {
    if (widget.session == null) _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final destination = widget.destination;
    void open(SessionDestination target) {
      final next = _session.contextForDestination(target);
      Navigator.of(context)
          .pushNamed(SessionLocation.encode(next), arguments: next);
    }

    final argument = ModalRoute.of(context)?.settings.arguments;
    final selected =
        destination == SessionDestination.diagnostics &&
            argument is _BackupOrigin &&
            Uri.tryParse(argument.route)?.path == AppRoutes.management
        ? SessionDestination.management
        : destination;
    return PrimaryNavigation(
      session: _session,
      title: PrimaryNavigation.labels[destination]!,
      selectedDestination: selected,
      detailAction: destination == SessionDestination.home
          ? AfAction(
              label: 'Ver detalle',
              icon: AfIcons.analysis,
              onPressed: () => open(SessionDestination.status),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          if (destination == SessionDestination.home) ...[
            const Text(
              'El resumen de Inicio se incorpora en su pantalla. La comparación mensual completa sigue disponible en Ver detalle.',
            ),
            AfAction(
              label: 'Importar CSV',
              icon: AfIcons.importFile,
              unavailableReason: widget.management.importsAvailable
                  ? null
                  : 'Servicio local no disponible.',
              onPressed: widget.management.importsAvailable
                  ? () => widget.management.open(context, 'csv')
                  : null,
            ),
            AfAction(
              label: 'Categorizar pendientes',
              icon: AfIcons.category,
              unavailableReason: widget.management.pendingAvailable
                  ? null
                  : 'Servicio local no disponible.',
              onPressed: widget.management.pendingAvailable
                  ? () => widget.management.open(context, 'pending')
                  : null,
            ),
          ],
          if (destination == SessionDestination.analysis ||
              destination == SessionDestination.more) ...[
            if (destination == SessionDestination.more)
              AfAction(
                label: 'Análisis',
                icon: AfIcons.analysis,
                onPressed: () => open(SessionDestination.analysis),
              ),
            AfAction(
              label: 'Real anual',
              icon: AfIcons.analysis,
              onPressed: () => open(SessionDestination.actual),
            ),
            AfAction(
              label: 'Indicadores',
              icon: AfIcons.analysis,
              onPressed: () => open(SessionDestination.indicators),
            ),
            AfAction(
              label: 'Diagnóstico de coherencia',
              icon: AfIcons.analysis,
              onPressed: () => open(SessionDestination.diagnostics),
            ),
            if (destination == SessionDestination.more)
              AfAction(
                label: 'Gestión',
                icon: AfIcons.management,
                onPressed: () => open(SessionDestination.management),
              ),
          ],
          if (destination == SessionDestination.management)
            ...widget.management.links(context),
          if (destination == SessionDestination.diagnostics)
            const Text(
              'Diagnóstico no disponible: pendiente de la interfaz de EP-025. No se ejecuta automáticamente.',
            ),
        ],
      ),
    );
  }
}
