import 'package:flutter/material.dart';

import '../../features/budget/budget.dart';
import '../../features/movements/movements.dart' show MovementSelection;
import '../../features/budget/presentation/budget_source.dart';
import '../../features/budget/presentation/monthly_budget_screen.dart';
import '../../features/budget/presentation/budget_form_screen.dart';
import '../../features/budget/presentation/budget_proposal_screen.dart';
import '../../features/movements/presentation/category_tree_screen.dart';
import '../category_selector_navigation.dart';
import 'app_routes.dart';
import 'pending_movement_route.dart';
import 'wealth_route.dart';
import 'category_navigation_context.dart';
import 'import_route.dart';
import 'navigation_session.dart';
import 'period_controls.dart';
import 'movement_links.dart';
import 'movement_list_route.dart';
import 'budget_links.dart';
import 'budget_list_route.dart';
import 'budget_editor_origin.dart';
export 'budget_editor_origin.dart';
import '../../features/wealth/wealth.dart' show Month;

class BudgetRoute extends StatefulWidget {
  const BudgetRoute({
    super.key,
    required this.settings,
    required this.load,
    this.categories,
    this.importsAvailable = false,
    this.pendingAvailable = false,
    this.navigationSession,
  });
  final RouteSettings settings;
  final BudgetLoader load;
  final CategoryManagementLoader? categories;
  final bool importsAvailable;
  final bool pendingAvailable;
  final NavigationSession? navigationSession;
  @override
  State<BudgetRoute> createState() => _BudgetRouteState();
}

class _BudgetRouteState extends State<BudgetRoute> {
  static const _labels = {
    '/estado': 'Estado',
    '/patrimonio': 'Patrimonio',
    '/presupuesto': 'Presupuesto',
    '/real': 'Real',
    '/indicadores': 'Indicadores',
  };
  String _period(BudgetMonth month) =>
      'a=${month.value.substring(0, 4)}&m=${month.value.substring(5, 7)}';
  BudgetMonth _parse(Uri uri) {
    final now = madridMonth(DateTime.now());
    if (uri.path == AppRoutes.budgetProposal) {
      if (uri.hasScheme ||
          uri.hasAuthority ||
          uri.hasFragment ||
          uri.queryParametersAll.values.any((values) => values.length != 1)) {
        throw const BudgetFailure('Ruta de propuesta inválida.');
      }
      final year = uri.queryParameters['a'];
      final month = uri.queryParameters['m'];
      if ((year != null && !RegExp(r'^\d{4}$').hasMatch(year)) ||
          (month != null &&
              (year == null || !RegExp(r'^\d{2}$').hasMatch(month)))) {
        throw const BudgetFailure('Periodo de propuesta inválido.');
      }
      if (year == null) {
        return widget.navigationSession?.period.budgetMonth ??
            BudgetMonth.parse(now.value);
      }
      final selectedYear = int.parse(year);
      return BudgetMonth(
        selectedYear,
        month == null
            ? widget.navigationSession?.rememberedMonth(selectedYear) ?? 1
            : int.parse(month),
      );
    }
    if (uri.queryParameters.containsKey('a') !=
        uri.queryParameters.containsKey('m')) {
      throw const BudgetFailure('Periodo incompleto.');
    }
    final a = uri.queryParameters['a'], m = uri.queryParameters['m'];
    if (a != null &&
        (!RegExp(r'^\d{4}$').hasMatch(a) || !RegExp(r'^\d{2}$').hasMatch(m!))) {
      throw const BudgetFailure('Periodo inválido.');
    }
    return a == null
        ? BudgetMonth.parse(now.value)
        : BudgetMonth(int.parse(a), int.parse(m!));
  }

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.of(context);
    var fallback = AppRoutes.monthlyStatus;
    void back([Object? result]) {
      if (navigator.canPop()) {
        navigator.pop(result);
      } else {
        navigator.pushReplacementNamed(fallback);
      }
    }

    try {
      final uri = Uri.parse(widget.settings.name!);
      if (uri.path == BudgetLinks.path) {
        return BudgetListRoute(settings: widget.settings, load: widget.load);
      }
      if (uri.hasScheme ||
          uri.hasAuthority ||
          uri.hasFragment ||
          uri.queryParametersAll.values.any((v) => v.length != 1)) {
        throw const BudgetFailure('Ruta inválida.');
      }
      final month = _parse(uri);
      fallback = '${AppRoutes.budget}?${_period(month)}';
      if (uri.path == AppRoutes.budgetProposal) {
        return BudgetProposalScreen(
          load: widget.load,
          sourceYear: int.parse(month.value.substring(0, 4)),
          onReturn: (year, saved) {
            final originalYear = int.parse(month.value.substring(0, 4));
            if (!saved && year == originalYear && navigator.canPop()) {
              navigator.pop();
            } else {
              final selectedMonth = year == originalYear
                  ? int.parse(month.value.substring(5, 7))
                  : widget.navigationSession?.rememberedMonth(year) ?? 1;
              navigator.pushNamedAndRemoveUntil(
                '${AppRoutes.budget}?${_period(BudgetMonth(year, selectedMonth))}',
                (_) => false,
              );
            }
            if (saved) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Propuesta guardada en $year')),
              );
            }
          },
        );
      }
      if (uri.path == AppRoutes.budget) {
        return MonthlyBudgetScreen(
          load: widget.load,
          month: month,
          onProposal: (selected) async {
            await navigator.pushNamed(
              '${AppRoutes.budgetProposal}?${_period(selected)}',
            );
          },
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
              : (selected, change) => PeriodControls(
                  session: widget.navigationSession!,
                  beforeChange: (period) => change(period.budgetMonth),
                ),
          destinations: _labels,
          onNavigate: (path, selected) => navigator.pushNamedAndRemoveUntil(
            '$path?${_period(selected)}',
            (_) => false,
          ),
          onOpen: (row, selected) async {
            await navigator.pushNamed(
              '${AppRoutes.budget}/partidas/${row?.budget?.id ?? 'nueva'}?${_period(selected)}',
              arguments: BudgetEditorOrigin(selected, row?.categoryId),
            );
          },
          management: (selected, refresh, canOpen) => PopupMenuButton<String>(
            tooltip: 'Gestión',
            onSelected: (path) async {
              if (!await canOpen() || !mounted) return;
              await navigator.pushNamed(
                path == AppRoutes.movements
                    ? MovementLinks.management(
                        '${AppRoutes.budget}?${_period(selected)}',
                        defaultMonth:
                            widget.navigationSession?.period.civilMonth ??
                            Month.parse(selected.value),
                      )
                    : path,
                arguments: path == AppRoutes.movements
                    ? MovementListOrigin(
                        '${AppRoutes.budget}?${_period(selected)}',
                      )
                    : path == AppRoutes.pendingMovements
                    ? PendingMovementOrigin(
                        route: "${AppRoutes.budget}?${_period(selected)}",
                        label:
                            "Volver a Presupuesto, ${selected.value.substring(0, 7)}",
                      )
                    : path == AppRoutes.importCsv
                    ? CsvImportOrigin(
                        '${AppRoutes.budget}?${_period(selected)}',
                        'Volver a Presupuesto, ${selected.value.substring(0, 7)}',
                      )
                    : CategoryNavigationContext(
                        returnLabel:
                            'Volver a Presupuesto, ${selected.value.substring(0, 7)}',
                      ),
              );
              if (mounted) await refresh();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: AppRoutes.movements,
                child: Text('Movimientos'),
              ),
              PopupMenuItem(
                value: AppRoutes.pendingMovements,
                enabled: widget.pendingAvailable,
                child: const Text("Pendientes de categorizar"),
              ),
              const PopupMenuItem(
                value: AppRoutes.importHistory,
                child: Text('Historial de importaciones'),
              ),
              PopupMenuItem(
                value: AppRoutes.importCsv,
                enabled: widget.importsAvailable,
                child: const Text('Importar CSV'),
              ),
              if (widget.categories != null)
                const PopupMenuItem(
                  value: AppRoutes.categories,
                  child: Text('Categorías'),
                ),
              const PopupMenuItem(
                value: AppRoutes.accounts,
                child: Text('Fichas'),
              ),
              const PopupMenuItem(
                value: AppRoutes.drive,
                child: Text('Copia en Drive'),
              ),
            ],
          ),
        );
      }
      if (uri.pathSegments.length != 3 ||
          uri.pathSegments.first != 'presupuesto' ||
          uri.pathSegments[1] != 'partidas' ||
          uri.pathSegments.last.isEmpty) {
        throw const BudgetFailure('Ruta inválida.');
      }
      if (uri.pathSegments.last != 'nueva') {
        MovementSelection([uri.pathSegments.last]);
      }
      if (uri.queryParameters.keys.any(
        (key) => !const {'a', 'm', 'rama', 'alcance', 'origen'}.contains(key),
      )) {
        throw const BudgetFailure('Ruta de partida inválida.');
      }
      if (uri.queryParameters.containsKey('origen') ||
          uri.queryParameters.containsKey('rama') ||
          uri.queryParameters.containsKey('alcance')) {
        final query = BudgetLinks.parse(
          uri.replace(path: BudgetLinks.path).toString(),
        );
        fallback = BudgetLinks.list(
          query,
          origin: BudgetLinks.origin(uri.toString())?.route,
        );
      }
      final origin = widget.settings.arguments is BudgetEditorOrigin
          ? widget.settings.arguments as BudgetEditorOrigin
          : null;
      if (origin?.listRoute != null) BudgetLinks.parse(origin!.listRoute!);
      final initial = origin?.month ?? month;
      fallback = origin?.listRoute ?? fallback;
      final messenger = ScaffoldMessenger.of(context);
      return BudgetFormScreen(
        load: widget.load,
        month: initial,
        id: uri.pathSegments.last == 'nueva' ? null : uri.pathSegments.last,
        categoryId:
            origin?.categoryId ??
            (uri.queryParameters['rama'] == 'sin-clasificar'
                ? null
                : uri.queryParameters['rama']),
        selectCategory: (id) async {
          if (widget.categories == null) {
            throw const BudgetFailure('Categorías no disponibles.');
          }
          return selectCategory(
            context,
            loadManagement: widget.categories!,
            selectedId: id,
          );
        },
        onReturn: back,
        onSaved: (saved) {
          back(saved);
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Partida guardada en ${saved.data.month.value.substring(0, 7)}',
              ),
              action: saved.data.month.value != initial.value
                  ? SnackBarAction(
                      label: 'Ver mes',
                      onPressed: () => navigator.pushNamed(
                        '${AppRoutes.budget}?${_period(saved.data.month)}',
                      ),
                    )
                  : null,
            ),
          );
        },
        onDeleted: () {
          back();
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Partida eliminada · Sin presupuesto'),
            ),
          );
        },
        destinations: {
          for (final d in _labels.entries)
            d.value: () => navigator.pushNamedAndRemoveUntil(
              '${d.key}?${_period(initial)}',
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
