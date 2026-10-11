import 'package:flutter/material.dart';

import '../../features/budget/presentation/budget_source.dart';
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
  final Widget Function(String Function() origin)? management;
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
      return PrimaryNavigation(
        session: _session,
        title: 'Presupuesto anual',
        wrapHeader: true,
        actions: [
          if (widget.management != null)
            widget.management!(() => _origin().route),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PeriodControls(session: _session),
            const Text(
              'Matriz anual pendiente de integración de MA-TSK-168/169.',
            ),
            TextButton(
              onPressed: navigation.openMonthlyCapture,
              child: const Text('Captura mensual'),
            ),
            FutureBuilder<bool>(
              future: _proposalAvailable,
              builder: (context, snapshot) => TextButton(
                onPressed: snapshot.data == true
                    ? () async {
                        try {
                          await navigation.prepareNextYear();
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'La propuesta de año siguiente no está disponible.',
                                ),
                              ),
                            );
                          }
                        }
                      }
                    : null,
                child: const Text('Preparar año siguiente'),
              ),
            ),
          ],
        ),
      );
    },
  );
}
