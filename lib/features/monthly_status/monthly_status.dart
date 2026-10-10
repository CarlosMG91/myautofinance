import '../../core/modules/feature_module.dart';
export 'domain/monthly_status_query.dart';

const monthlyStatusModule = FeatureModule(
  id: ModuleId.monthlyStatus,
  dependencies: {ModuleId.budget, ModuleId.movements},
);
