import '../domain/budget_management.dart';
import '../domain/budget_proposal_calculator.dart';
import '../domain/budget_proposal_saver.dart';
import '../domain/monthly_budget_query.dart';
import '../../movements/movements.dart';

class BudgetSource {
  const BudgetSource({
    required this.query,
    required this.management,
    required this.categories,
    required this.identity,
    this.proposalCalculator,
    this.proposalSaver,
  });
  final MonthlyBudgetQuery query;
  final BudgetManagement management;
  final Future<List<CategoryDetails>> Function() categories;
  final Object identity;
  final BudgetProposalCalculator? proposalCalculator;
  final BudgetProposalSaver? proposalSaver;
}

typedef BudgetLoader = Future<BudgetSource> Function();
