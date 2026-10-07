import '../../core/modules/feature_module.dart';

/// Marcadores técnicos; las etiquetas no fijan el diseño de producto.
class TechnicalDestination {
  const TechnicalDestination(this.path, this.module, this.label);

  final String path;
  final ModuleId module;
  final String label;
}

abstract final class AppRoutes {
  static const home = '/';
  static const importHistory = '/importaciones';
  static const importReview = '/importaciones/revision';
  static const importBatches = '/importaciones/lotes';
  static const importRows = '/importaciones/origen';
  static const movements = '/movimientos';
  static const monthlyStatus = '/estado';
  static const wealth = '/patrimonio';
  static const wealthPhoto = '/patrimonio/foto';
  static const accounts = '/patrimonio/fichas';
  static const newAccount = '/patrimonio/fichas/nueva';
  static const budget = '/presupuesto';
  static const actualSpending = '/real';
  static const indicators = '/indicadores';
  static const error = '/error';
  static const drive = '/drive';
  static const localBackups = '/copias-locales';
  static const categories = '/categorias';
  static const newCategory = '/categorias/nueva';

  static const destinations = <TechnicalDestination>[
    TechnicalDestination(
      monthlyStatus,
      ModuleId.monthlyStatus,
      'Estado del mes',
    ),
    TechnicalDestination(
      wealth,
      ModuleId.wealth,
      'Cuentas, deudas e inversiones',
    ),
    TechnicalDestination(budget, ModuleId.budget, 'Presupuesto anual'),
    TechnicalDestination(actualSpending, ModuleId.actualSpending, 'Real anual'),
    TechnicalDestination(indicators, ModuleId.indicators, 'Indicadores'),
  ];
}
