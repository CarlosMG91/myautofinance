import '../core/modules/feature_module.dart';
import '../features/monthly_status/monthly_status.dart';
import '../features/wealth/wealth.dart';
import '../features/budget/budget.dart';
import '../features/actual_spending/actual_spending.dart';
import '../features/indicators/indicators.dart';
import '../features/movements/movements.dart';
import '../features/importing/importing.dart';
import '../features/synchronization/synchronization.dart';

/// Composición explícita; importar este catálogo no activa los módulos.
const applicationModules = <FeatureModule>[
  monthlyStatusModule,
  wealthModule,
  budgetModule,
  actualSpendingModule,
  indicatorsModule,
  movementsModule,
  importingModule,
  synchronizationModule,
];
