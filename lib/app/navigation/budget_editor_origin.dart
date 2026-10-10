import '../../features/budget/budget.dart';

class BudgetEditorOrigin {
  const BudgetEditorOrigin(this.month, this.categoryId, {this.listRoute});
  final BudgetMonth month;
  final String? categoryId;
  final String? listRoute;
}
