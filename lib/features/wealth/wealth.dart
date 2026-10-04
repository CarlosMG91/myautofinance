import '../../core/modules/feature_module.dart';
export 'domain/account_repository.dart';
export 'domain/wealth_repository.dart';
export 'domain/wealth_management.dart';
export 'domain/wealth_reading.dart';
export 'domain/wealth_amount.dart';
export 'presentation/wealth_controller.dart';

const wealthModule = FeatureModule(id: ModuleId.wealth);
