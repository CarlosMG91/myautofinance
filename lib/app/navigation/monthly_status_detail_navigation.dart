import 'package:flutter/material.dart';

import '../../features/monthly_status/monthly_status.dart';
import 'navigation_context.dart';
import 'navigation_session.dart';
import 'monthly_status_origin.dart';
import 'movement_links.dart';
import 'movement_list_route.dart';
import 'budget_links.dart';

/// Inyectar en Estado PC/Android. Captura el contexto al pulsar cada cifra.
MonthlyStatusDetailCallbacks createMonthlyStatusDetailCallbacks({
  required BuildContext context,
  required NavigationContext Function() origin,
  NavigationSession? session,
}) {
  Future<void> open(
    MonthlyFigureDetail detail,
    bool budget,
    MonthlyStatusOrigin saved,
  ) async {
    final focus = FocusManager.instance.primaryFocus;
    final route = budget
        ? BudgetLinks.list(detail.budgets, origin: saved.route)
        : MovementLinks.list(detail.movements, origin: saved.route);
    await Navigator.of(context).pushNamed(
      route,
      arguments: budget
          ? null
          : MovementListOrigin(saved.route, context: saved.context),
    );
    if (!context.mounted) return;
    await session?.returnToOrigin(SecondaryNavigationContext(saved.context));
    if (focus?.context != null) focus!.requestFocus();
  }

  return MonthlyStatusDetailCallbacks(
    onMovements: (detail) => open(detail, false, MonthlyStatusOrigin(origin())),
    onBudgets: (detail) => open(detail, true, MonthlyStatusOrigin(origin())),
    onDifference: (detail) async {
      final saved = MonthlyStatusOrigin(origin());
      final focus = FocusManager.instance.primaryFocus;
      final choice = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Origen de la diferencia'),
          content: const Text(
            'La diferencia es real menos previsto. Elige los registros que quieres consultar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Ver movimientos reales'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ver partidas previstas'),
            ),
          ],
        ),
      );
      if (choice != null && context.mounted) await open(detail, choice, saved);
      if (focus?.context != null) focus!.requestFocus();
    },
  );
}
