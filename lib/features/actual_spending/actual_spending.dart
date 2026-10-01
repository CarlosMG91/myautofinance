import '../../core/modules/feature_module.dart';

const actualSpendingModule = FeatureModule(
  id: ModuleId.actualSpending,
  dependencies: {ModuleId.movements},
);
