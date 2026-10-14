import 'package:flutter/material.dart';

import '../../features/actual_spending/actual_spending.dart';
import '../../features/movements/movements.dart';
import 'annual_actual_origin.dart';
import 'movement_links.dart';
import 'movement_list_route.dart';
import 'navigation_context.dart';
import 'navigation_session.dart';

/// Composición compartida para matriz y tarjetas; releer al terminar la acción.
final class AnnualActualNavigation {
  AnnualActualNavigation({
    required this.context,
    required this.origin,
    this.session,
  });
  final BuildContext context;
  final AnnualActualOrigin Function() origin;
  final NavigationSession? session;

  int get year => origin().context.period.year;
  int get focusedMonth => origin().context.period.month;

  Future<void> open(AnnualActualDetail detail) => _open(detail, false);

  Future<void> openMonth(
    int month, {
    String? categoryId,
    bool unclassified = false,
    MovementCategoryScope scope = MovementCategoryScope.branch,
  }) => open(
    AnnualActualDetail(
      year: year,
      month: month,
      categoryId: categoryId,
      unclassified: unclassified,
      scope: scope,
    ),
  );

  Future<void> openYear({
    String? categoryId,
    bool unclassified = false,
    MovementCategoryScope scope = MovementCategoryScope.branch,
  }) => open(
    AnnualActualDetail(
      year: year,
      categoryId: categoryId,
      unclassified: unclassified,
      scope: scope,
    ),
  );

  /// Alta explícita en el mes enfocado mediante el formulario de EP-010.
  Future<void> addMovement() =>
      _open(AnnualActualDetail(year: year, month: focusedMonth), true);

  Future<void> _open(AnnualActualDetail detail, bool create) async {
    final saved = origin();
    final focus = FocusManager.instance.primaryFocus;
    final originRoute = ModalRoute.of(context);
    await Navigator.of(context).pushNamed(
      create
          ? MovementLinks.create(detail.movements, origin: saved.route)
          : MovementLinks.list(detail.movements, origin: saved.route),
      arguments: create
          ? null
          : MovementListOrigin(saved.route, context: saved.context),
    );
    if (!context.mounted || originRoute?.isCurrent != true) return;
    await session?.returnToOrigin(SecondaryNavigationContext(saved.context));
    if (focus?.context != null) focus!.requestFocus();
  }
}
