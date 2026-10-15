import '../../core/modules/feature_module.dart';
export 'domain/indicator_catalog.dart';
export 'domain/indicator_definition.dart';
export 'domain/indicator_engine.dart';
export 'domain/indicator_inputs.dart';
export 'domain/indicator_result.dart';

const indicatorsModule = FeatureModule(
  id: ModuleId.indicators,
  dependencies: {ModuleId.wealth, ModuleId.budget},
);
