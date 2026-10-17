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
  static const start = '/inicio';
  static const analysis = '/analisis';
  static const more = '/mas';
  static const management = '/gestion';
  static const exportData = '/gestion/exportar-datos';
  static const exportComplete = '/gestion/exportar-copia';
  static const diagnostics = '/diagnostico';
  static const budgetDetail = '/presupuesto/detalle';
  static const movementDetail = '/movimientos/detalle';
  static const wealthDetail = '/patrimonio/detalle';
  static const actualDetail = '/real/detalle';
  static const indicatorDetail = '/indicadores/detalle';
  static const importHistory = '/importaciones';
  static const importReview = '/importaciones/revision';
  static const importCsv = '/importaciones/csv';
  static const importBatches = '/importaciones/lotes';
  static const importRows = '/importaciones/origen';
  static const movements = '/movimientos';
  static const pendingMovements = '/pendientes-categorizacion';
  static const monthlyStatus = '/estado';
  static const wealth = '/patrimonio';
  static const wealthPhoto = '/patrimonio/foto';
  static const accounts = '/patrimonio/fichas';
  static const newAccount = '/patrimonio/fichas/nueva';
  static const budget = '/presupuesto';
  static const monthlyBudget = '/presupuesto/mensual';
  static const budgetProposal = '/presupuesto/propuesta';
  static const actualSpending = '/real';
  static const indicators = '/indicadores';
  static const error = '/error';
  static const drive = '/drive';
  static const localBackups = '/copias-locales';
  static const categories = '/categorias';
  static const newCategory = '/categorias/nueva';

  /// Solo aliases estáticos acordados. Nunca reescribe UUID ni prefijos.
  static String contentPath(String path) => switch (path) {
    home => start,
    budgetDetail => budget,
    movementDetail => movements,
    wealthDetail => wealth,
    actualDetail => actualSpending,
    indicatorDetail => indicators,
    _ => path,
  };

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
