import '../domain/budget_management.dart';
import '../domain/monthly_budget_query.dart';
import '../../movements/movements.dart';

class BudgetSource {
  const BudgetSource({
    required this.query,
    required this.management,
    required this.categories,
    required this.identity,
  });
  final MonthlyBudgetQuery query;
  final BudgetManagement management;
  final Future<List<CategoryDetails>> Function() categories;
  final Object identity;
}

typedef BudgetLoader = Future<BudgetSource> Function();
