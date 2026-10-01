import '../../core/modules/feature_module.dart';

const indicatorsModule = FeatureModule(
  id: ModuleId.indicators,
  dependencies: {ModuleId.wealth, ModuleId.budget},
);
