import '../../core/modules/feature_module.dart';
export 'domain/monthly_status_query.dart';
export 'domain/monthly_figure_detail.dart';

const monthlyStatusModule = FeatureModule(
  id: ModuleId.monthlyStatus,
  dependencies: {ModuleId.budget, ModuleId.movements},
);
