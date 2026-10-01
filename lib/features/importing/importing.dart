import '../../core/modules/feature_module.dart';

const importingModule = FeatureModule(
  id: ModuleId.importing,
  dependencies: {ModuleId.movements, ModuleId.budget},
);
