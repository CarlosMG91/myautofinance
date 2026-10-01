import '../../core/modules/feature_module.dart';

const monthlyStatusModule = FeatureModule(
  id: ModuleId.monthlyStatus,
  dependencies: {ModuleId.budget, ModuleId.movements},
);
