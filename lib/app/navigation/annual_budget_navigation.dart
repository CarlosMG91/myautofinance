import 'package:flutter/material.dart';

import '../../features/budget/budget.dart';
import '../../features/budget/presentation/budget_source.dart';
import '../../features/movements/movements.dart';
import 'app_routes.dart';
import 'budget_links.dart';
import 'budget_editor_origin.dart';
import 'budget_origin.dart';
import 'navigation_context.dart';
import 'navigation_session.dart';

/// Contrato de composición para MA-TSK-168/169, independiente de la matriz.
typedef AnnualBudgetBuilder = Widget Function(
  BuildContext context,
  AnnualBudgetNavigation navigation,
);

final class AnnualBudgetNavigation {
  AnnualBudgetNavigation({
    required this.context,
    required this.origin,
    required this.load,
    this.session,
  });
  final BuildContext context;
  final BudgetOrigin Function() origin;
  final BudgetLoader load;
  final NavigationSession? session;
  bool _openingProposal = false;

  NavigationContext get current => origin().context;
  int get year => current.period.year;
  int get focusedMonth => current.period.month;

  Future<void> _open(
    String route, {
    Object? arguments,
    BudgetOrigin? savedOrigin,
  }) async {
    final saved = savedOrigin ?? origin();
    final focus = FocusManager.instance.primaryFocus;
    final originRoute = ModalRoute.of(context);
    await Navigator.of(context).pushNamed(route, arguments: arguments);
    if (!context.mounted || originRoute?.isCurrent != true) return;
    if (session?.period == saved.context.period) {
      await session?.returnToOrigin(SecondaryNavigationContext(saved.context));
    }
    if (focus?.context != null) focus!.requestFocus();
  }

  Future<void> openMonth(int month, {String? categoryId}) => _open(
    BudgetLinks.list(
      BudgetListQuery(month: BudgetMonth(year, month), categoryId: categoryId),
      origin: origin().route,
    ),
  );

  Future<void> openYear({String? categoryId}) => _open(
    BudgetLinks.list(
      BudgetListQuery.annual(
        year,
        focusedMonth: focusedMonth,
        categoryId: categoryId,
      ),
      origin: origin().route,
    ),
  );

  /// Alta explícita o edición de la partida propia; un cero conserva su UUID.
  Future<void> openCell({
    required int month,
    required String categoryId,
    String? budgetId,
  }) {
    final query = BudgetListQuery(
      month: BudgetMonth(year, month),
      categoryId: categoryId,
      scope: MovementCategoryScope.direct,
    );
    return _open(
      budgetId == null
          ? BudgetLinks.create(query, origin: origin().route)
          : BudgetLinks.detail(budgetId, query, origin: origin().route),
      arguments: BudgetEditorOrigin(
        query.month,
        categoryId,
        returnOrigin: origin(),
      ),
    );
  }

  Future<void> openMonthlyCapture() => _open(
    Uri(
      path: AppRoutes.monthlyBudget,
      queryParameters: {
        'a': year.toString().padLeft(4, '0'),
        'm': focusedMonth.toString().padLeft(2, '0'),
        'origen': origin().route,
      },
    ).toString(),
  );

  Future<bool> canPrepareNextYear() async {
    if (year == 9999) return false;
    final source = await load();
    return source.proposalCalculator != null && source.proposalSaver != null;
  }

  Future<void> prepareNextYear() async {
    if (_openingProposal) return;
    _openingProposal = true;
    final saved = origin();
    try {
      final source = await load();
      if (!context.mounted || current.period != saved.context.period) return;
      if (saved.context.period.year == 9999 ||
          source.proposalCalculator == null ||
          source.proposalSaver == null) {
        throw const BudgetFailure(
          'La propuesta de año siguiente no está disponible.',
        );
      }
      await _open(
        Uri(
          path: AppRoutes.budgetProposal,
          queryParameters: {
            'a': saved.context.period.year.toString().padLeft(4, '0'),
            'm': saved.context.period.month.toString().padLeft(2, '0'),
            'origen': saved.route,
          },
        ).toString(),
        savedOrigin: saved,
      );
    } finally {
      _openingProposal = false;
    }
  }
}
