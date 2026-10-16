import '../../core/modules/feature_module.dart';

export 'domain/diagnostic_action.dart';
export 'domain/diagnostic_evidence.dart';
export 'domain/diagnostic_result.dart';
export 'domain/diagnostic_rule.dart';

/// Propietario EP-025. Declararlo no ejecuta ni conecta el diagnóstico.
const diagnosticsModule = FeatureModule(
  id: ModuleId.diagnostics,
  dependencies: {
    ModuleId.budget,
    ModuleId.movements,
    ModuleId.importing,
    ModuleId.wealth,
    ModuleId.indicators,
  },
);
