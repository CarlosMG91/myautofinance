export 'domain/category_repository.dart';
export 'domain/category_management.dart';
export 'domain/category_read_invalidation.dart';
export 'domain/category_grouping.dart';
export 'domain/movement_repository.dart';
import '../../core/modules/feature_module.dart';

const movementsModule = FeatureModule(id: ModuleId.movements);
