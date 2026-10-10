import '../../core/modules/feature_module.dart';
export 'domain/budget_repository.dart';
export 'domain/budget_list_query.dart';
export 'domain/budget_management.dart';
export 'domain/monthly_budget_query.dart';
export 'domain/budget_proposal.dart';
export 'domain/budget_proposal_calculator.dart';
export 'domain/budget_proposal_editor.dart';
export 'domain/budget_proposal_saver.dart';

const budgetModule = FeatureModule(
  id: ModuleId.budget,
  dependencies: {ModuleId.movements},
);
