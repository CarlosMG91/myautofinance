import 'package:flutter/material.dart';

import '../../features/budget/budget.dart';
import '../../features/budget/presentation/budget_source.dart';
import '../../features/budget/presentation/monthly_budget_screen.dart';
import '../../features/budget/presentation/budget_form_screen.dart';
import '../../features/movements/presentation/category_tree_screen.dart';
import '../category_selector_navigation.dart';
import 'app_routes.dart';
import 'pending_movement_route.dart';
import 'wealth_route.dart';
import 'category_navigation_context.dart';
import 'import_route.dart';
import 'navigation_session.dart';
import 'period_controls.dart';

class BudgetEditorOrigin {
  const BudgetEditorOrigin(this.month, this.categoryId);
  final BudgetMonth month;
  final String? categoryId;
}

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
      final month = _parse(uri);
      fallback = '${AppRoutes.budget}?${_period(month)}';
      if (uri.path == AppRoutes.budget) {
        return MonthlyBudgetScreen(
          load: widget.load,
          month: month,
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
                path,
                arguments: path == AppRoutes.pendingMovements
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
          uri.pathSegments[1] != 'partidas' ||
          uri.pathSegments.last.isEmpty) {
        throw const BudgetFailure('Ruta inválida.');
      }
      final origin = widget.settings.arguments is BudgetEditorOrigin
          ? widget.settings.arguments as BudgetEditorOrigin
          : null;
      final initial = origin?.month ?? month;
      final messenger = ScaffoldMessenger.of(context);
      return BudgetFormScreen(
        load: widget.load,
        month: initial,
        id: uri.pathSegments.last == 'nueva' ? null : uri.pathSegments.last,
        categoryId: origin?.categoryId,
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
