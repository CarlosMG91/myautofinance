import '../../features/budget/budget.dart';
import 'budget_origin.dart';

class BudgetEditorOrigin {
  const BudgetEditorOrigin(
    this.month,
    this.categoryId, {
    this.listRoute,
    this.returnOrigin,
  });
  final BudgetMonth month;
  final String? categoryId;
  final String? listRoute;
  final BudgetOrigin? returnOrigin;
}
