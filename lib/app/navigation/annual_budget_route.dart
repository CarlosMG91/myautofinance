import 'package:flutter/material.dart';

import '../../features/budget/presentation/budget_source.dart';
import '../../features/budget/presentation/annual_budget_screen.dart';
import 'annual_budget_navigation.dart';
import 'budget_origin.dart';
import 'navigation_context.dart';
import 'navigation_session.dart';
import 'period_controls.dart';
import 'primary_navigation.dart';

/// Entrada anual. Las composiciones visuales se inyectan tras su aprobación.
class AnnualBudgetRoute extends StatefulWidget {
  const AnnualBudgetRoute({
    super.key,
    required this.origin,
    required this.load,
    this.session,
    this.builder,
    this.management,
  });
  final BudgetOrigin origin;
  final BudgetLoader load;
  final NavigationSession? session;
  final AnnualBudgetBuilder? builder;
  final Widget Function(
    String Function() origin,
    Future<bool> Function() canLeave,
    Future<void> Function() refresh,
  )?
  management;
  @override
  State<AnnualBudgetRoute> createState() => _AnnualBudgetRouteState();
}

class _AnnualBudgetRouteState extends State<AnnualBudgetRoute> {
  late final NavigationSession _session =
      widget.session ??
      NavigationSession(initialContext: widget.origin.context);
  Future<bool>? _proposalAvailable;
  int? _capabilityYear;

  @override
  void dispose() {
    if (widget.session == null) _session.dispose();
    super.dispose();
  }

  BudgetOrigin _origin() {
    final current = _session.context;
    return current.destination == SessionDestination.budget &&
            current.view == PeriodView.annual
        ? BudgetOrigin(current)
        : widget.origin;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _session,
    builder: (context, _) {
      final navigation = AnnualBudgetNavigation(
        context: context,
        origin: _origin,
        load: widget.load,
        session: _session,
      );
      if (widget.builder != null) return widget.builder!(context, navigation);
      if (_capabilityYear != navigation.year) {
        _capabilityYear = navigation.year;
        _proposalAvailable = navigation.canPrepareNextYear();
      }
      return FutureBuilder<bool>(
        future: _proposalAvailable,
        builder: (context, snapshot) => AnnualBudgetScreen(
          load: widget.load,
          year: navigation.year,
          focusedMonth: navigation.focusedMonth,
          initialExpanded: (_origin().context.filters['abiertas'] ?? '')
              .split(',')
              .where((s) => s.isNotEmpty)
              .toSet(),
          initialExpandedMonths: (_origin().context.filters['meses'] ?? '')
              .split(',')
              .where((s) => s.isNotEmpty)
              .toSet(),
          initialScrollOffset: _origin().context.scrollOffset,
          initialFocus: _origin().context.focus,
          shell: (child, canLeave, refresh, scroll) => PrimaryNavigation(
            session: _session,
            title: 'Presupuesto anual',
            wrapHeader: true,
            scrollController: scroll,
            beforeNavigate: canLeave,
            actions: [
              if (widget.management != null)
                widget.management!(() => _origin().route, canLeave, refresh),
            ],
            child: child,
          ),
          controls: (canLeave) => PeriodControls(
            session: _session,
            beforeChange: (_) => canLeave(),
          ),
          openMonth: (month, category) =>
              navigation.openMonth(month, categoryId: category),
          openYear: (category) => navigation.openYear(categoryId: category),
          openCell: (month, category, id) => navigation.openCell(
            month: month,
            categoryId: category,
            budgetId: id,
          ),
          openCapture: navigation.openMonthlyCapture,
          openProposal: snapshot.data == true
              ? navigation.prepareNextYear
              : null,
          onOrigin: (expanded, offset, focus, months) {
            final current = _origin().context;
            final filters = {
              'abiertas': expanded.join(','),
              if (months.isNotEmpty) 'meses': months.join(','),
            };
            if (current.filters['abiertas'] == filters['abiertas'] &&
                current.filters['meses'] == filters['meses'] &&
                current.scrollOffset == offset &&
                current.focus == focus) {
              return;
            }
            _session.setContext(
              NavigationContext(
                destination: current.destination,
                period: current.period,
                view: current.view,
                branchId: current.branchId,
                scope: current.scope,
                filters: filters,
                scrollOffset: offset,
                focus: focus,
              ),
              deferNotification: true,
            );
          },
        ),
      );
    },
  );
}
