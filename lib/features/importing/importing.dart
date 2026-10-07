import '../../core/modules/feature_module.dart';
export 'domain/import_batch_repository.dart';
export 'domain/import_file.dart';
export 'domain/import_session.dart';
export 'domain/interpreted_import.dart';

const importingModule = FeatureModule(
  id: ModuleId.importing,
  dependencies: {ModuleId.movements, ModuleId.budget},
);
