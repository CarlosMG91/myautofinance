/// Identidades técnicas; no representan tablas ni entidades financieras.
enum ModuleId {
  monthlyStatus,
  wealth,
  budget,
  actualSpending,
  indicators,
  movements,
  importing,
  synchronization,
}

/// Contrato mínimo para componer funcionalidades en el arranque.
///
/// Las dependencias declaran consumo de entradas públicas de otros módulos.
/// No inicia servicios, abre bases de datos ni ejecuta operaciones financieras.
class FeatureModule {
  const FeatureModule({required this.id, this.dependencies = const {}});

  final ModuleId id;
  final Set<ModuleId> dependencies;
}
