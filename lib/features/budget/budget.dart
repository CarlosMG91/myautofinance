import '../../core/modules/feature_module.dart';
export 'domain/budget_repository.dart';
export 'domain/budget_management.dart';
export 'domain/monthly_budget_query.dart';

const budgetModule = FeatureModule(
  id: ModuleId.budget,
  dependencies: {ModuleId.movements},
);
