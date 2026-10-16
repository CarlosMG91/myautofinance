import 'package:flutter/material.dart';

import '../../features/budget/presentation/budget_source.dart';
import '../../features/budget/presentation/budget_list_screen.dart';
import '../../features/budget/budget.dart';
import 'budget_links.dart';
import 'budget_editor_origin.dart';
import 'budget_origin.dart';
import 'navigation_session.dart';
import 'primary_navigation.dart';
import 'movement_list_route.dart' show MovementListOrigin;

class BudgetListRoute extends StatefulWidget {
  const BudgetListRoute({
    super.key,
    required this.settings,
    required this.load,
    this.navigationSession,
  });
  final RouteSettings settings;
  final BudgetLoader load;
  final NavigationSession? navigationSession;
  @override
  State<BudgetListRoute> createState() => _BudgetListRouteState();
}

class _BudgetListRouteState extends State<BudgetListRoute> {
  BudgetListQuery? _currentQuery;
  RouteSettings get settings => widget.settings;
  BudgetLoader get load => widget.load;
  NavigationSession? get navigationSession => widget.navigationSession;
  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.of(context);
    BudgetOrigin? origin;
    void back() {
      if (navigator.canPop()) {
        navigator.pop();
      } else if (origin != null) {
        navigator.pushReplacementNamed(origin.route, arguments: origin.context);
      } else {
        navigator.pushReplacementNamed('/estado');
      }
    }

    try {
      final query = BudgetLinks.parse(settings.name!);
      _currentQuery ??= query;
      origin = BudgetLinks.origin(settings.name!);
      Future<void> open(String? id) async {
        await navigator.pushNamed(
          id == null
              ? BudgetLinks.create(_currentQuery!, origin: origin?.route)
              : BudgetLinks.detail(id, _currentQuery!, origin: origin?.route),
          arguments: BudgetEditorOrigin(
            _currentQuery!.month,
            _currentQuery!.categoryId,
            listRoute: BudgetLinks.list(_currentQuery!, origin: origin?.route),
          ),
        );
      }

      return BudgetListScreen(
        load: load,
        query: query,
        onQueryChanged: (value) => _currentQuery = value,
        originLabel: origin == null
            ? 'Presupuesto'
            : MovementListOrigin(origin.route).label,
        shell: navigationSession == null
            ? null
            : (body, scroll) => PrimaryNavigation(
                session: navigationSession!,
                title: query.isAnnual
                    ? 'Partidas del año'
                    : query.isMonthly
                    ? 'Partidas del mes'
                    : 'Partidas del periodo',
                scrollController: scroll,
                periodControl: Text(
                  'Periodo del informe: ${query.firstMonth.value.substring(0, 7)} – ${query.lastMonth.value.substring(0, 7)}',
                ),
                backLabel: 'Volver al origen',
                onBack: () async {
                  back();
                  return true;
                },
                child: body,
              ),
        onReturn: back,
        onCreate: () => open(null),
        onOpen: open,
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
