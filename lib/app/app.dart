import '../features/movements/presentation/movement_list_controller.dart';
import '../features/movements/presentation/pending_movement_controller.dart';
import '../features/importing/presentation/import_controller.dart';
import '../features/importing/importing.dart' show LocalCsvSelector;
import '../features/budget/presentation/budget_source.dart';
import '../features/monthly_status/presentation/monthly_status_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/autofinance_ui.dart';

import '../core/config/app_config.dart';
import 'regional.dart';
import '../features/synchronization/presentation/drive_controller.dart';

import 'modules.dart';
import 'navigation/app_router.dart';
import 'navigation/app_routes.dart';
import 'navigation/annual_budget_navigation.dart';
import 'navigation/navigation_session.dart';
import 'navigation/navigation_session_scope.dart';
import 'navigation/session_location.dart';
import 'local_backup_session.dart';
import '../features/synchronization/presentation/local_backup_controller.dart';
import '../features/movements/presentation/category_tree_screen.dart';
import '../features/wealth/wealth.dart';

class AutofinanceApp extends StatefulWidget {
  const AutofinanceApp({
    super.key,
    this.config = const AppConfig(environment: AppEnvironment.production),
    this.localSession,
    this.localBackups,
    this.drive,
    this.categories,
    this.wealth,
    this.movements,
    this.pendingMovements,
    this.budgets,
    this.annualBudgetBuilder,
    this.monthlyStatus,
    this.imports,
    this.csvSelector,
    this.navigationSession,
    this.navigationClock,
  });

  final AppConfig config;
  final LocalBackupSession? localSession;

  /// Permite probar navegación sin abrir archivos ni servicios nativos.
  final LocalBackupController? localBackups;
  final DriveController? drive;
  final CategoryManagementLoader? categories;
  final WealthManagementLoader? wealth;
  final MovementListLoader? movements;
  final PendingMovementLoader? pendingMovements;
  final BudgetLoader? budgets;
  final AnnualBudgetBuilder? annualBudgetBuilder;
  final MonthlyStatusLoader? monthlyStatus;
  final ImportServicesLoader? imports;
  final LocalCsvSelector? csvSelector;
  final NavigationSession? navigationSession;
  final NavigationClock? navigationClock;

  /// Entradas técnicas disponibles para conectar las futuras funcionalidades.
  static const modules = applicationModules;

  @override
  State<AutofinanceApp> createState() => _AutofinanceAppState();
}

class _AutofinanceAppState extends State<AutofinanceApp> {
  final _navigator = GlobalKey<NavigatorState>();
  late final NavigationSession _navigation;
  late final NavigationSessionObserver _navigationObserver;
  late final bool _ownsNavigation;

  @override
  void initState() {
    super.initState();
    _ownsNavigation = widget.navigationSession == null;
    _navigation =
        widget.navigationSession ??
        NavigationSession(clock: widget.navigationClock);
    _navigationObserver = NavigationSessionObserver(_navigation);
  }

  @override
  void dispose() {
    if (_ownsNavigation) _navigation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backups = widget.localBackups ?? widget.localSession?.controller;
    final driveController = widget.drive ?? widget.localSession?.drive;
    final categoryLoader = widget.categories ?? widget.localSession?.categories;
    final wealthLoader = widget.wealth ?? widget.localSession?.wealth;
    return NavigationSessionScope(
      session: _navigation,
      child: MaterialApp(
        navigatorKey: _navigator,
        builder: (context, child) => CallbackShortcuts(
          bindings: {
            const SingleActivator(
              LogicalKeyboardKey.arrowLeft,
              alt: true,
            ): () =>
                _navigator.currentState?.maybePop(),
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                _navigator.currentState?.maybePop(),
          },
          child: child!,
        ),
        navigatorObservers: [_navigationObserver],
        title: 'Autofinance',
        debugShowCheckedModeBanner: false,
        locale: AppRegional.locale,
        supportedLocales: AppRegional.supportedLocales,
        localizationsDelegates: AppRegional.delegates,
        theme: AfTheme.light(),
        highContrastTheme: AfTheme.light(highContrast: true),
        themeMode: ThemeMode.light,
        // Evita una ruta de datos por debajo de la recuperación de arranque.
        onGenerateInitialRoutes: (_) => [
          AppRouter.generateRoute(
            RouteSettings(
              name: backups != null && !backups.activeAvailable
                  ? AppRoutes.localBackups
                  : SessionLocation.encode(_navigation.context),
              arguments: _navigation.context,
            ),
            localBackups: backups,
            drive: driveController,
            categories: categoryLoader,
            wealth: wealthLoader,
            movements: widget.movements ?? widget.localSession?.movements,
            pendingMovements:
                widget.pendingMovements ??
                widget.localSession?.pendingMovements,
            budgets: widget.budgets ?? widget.localSession?.budgets,
            annualBudgetBuilder: widget.annualBudgetBuilder,
            monthlyStatus:
                widget.monthlyStatus ?? widget.localSession?.monthlyStatus,
            imports: widget.imports ?? widget.localSession?.imports,
            csvSelector: widget.csvSelector,
            allowTestImports: widget.config.environment == AppEnvironment.test,
            navigationSession: _navigation,
          ),
        ],
        onGenerateRoute: (settings) => AppRouter.generateRoute(
          settings,
          localBackups: backups,
          drive: driveController,
          categories: categoryLoader,
          wealth: wealthLoader,
          movements: widget.movements ?? widget.localSession?.movements,
          pendingMovements:
              widget.pendingMovements ?? widget.localSession?.pendingMovements,
          budgets: widget.budgets ?? widget.localSession?.budgets,
          annualBudgetBuilder: widget.annualBudgetBuilder,
          monthlyStatus:
              widget.monthlyStatus ?? widget.localSession?.monthlyStatus,
          imports: widget.imports ?? widget.localSession?.imports,
          csvSelector: widget.csvSelector,
          allowTestImports: widget.config.environment == AppEnvironment.test,
          navigationSession: _navigation,
        ),
      ),
    );
  }
}
