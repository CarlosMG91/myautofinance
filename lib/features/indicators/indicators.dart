import '../../core/modules/feature_module.dart';
export 'domain/emergency_cushion_calculation.dart';
export 'domain/indicator_catalog.dart';
export 'domain/indicator_definition.dart';
export 'domain/indicator_engine.dart';
export 'domain/indicator_inputs.dart';
export 'domain/indicator_result.dart';
export 'domain/repository_indicator_input_provider.dart';
export 'presentation/indicator_formatter.dart';

const indicatorsModule = FeatureModule(
  id: ModuleId.indicators,
  dependencies: {ModuleId.wealth, ModuleId.budget},
);
