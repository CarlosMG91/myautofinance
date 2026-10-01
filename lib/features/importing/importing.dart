import '../../core/modules/feature_module.dart';
export 'domain/import_batch_repository.dart';

const importingModule = FeatureModule(
  id: ModuleId.importing,
  dependencies: {ModuleId.movements, ModuleId.budget},
);
