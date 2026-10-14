export 'domain/annual_actual_query.dart';
export 'domain/annual_actual_detail.dart';
import '../../core/modules/feature_module.dart';

const actualSpendingModule = FeatureModule(
  id: ModuleId.actualSpending,
  dependencies: {ModuleId.movements},
);
