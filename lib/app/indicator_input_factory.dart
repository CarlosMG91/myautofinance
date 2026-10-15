import '../features/indicators/indicators.dart';
import 'data/sqlite/local_database.dart';
import 'data/sqlite/sqlite_budget_repository.dart';
import 'data/sqlite/sqlite_read_unit_of_work.dart';
import 'wealth_management_factory.dart';
import '../features/indicators/presentation/indicator_source.dart';
import '../features/movements/movements.dart' show CategoryReadInvalidation;

/// Una conexión de sesión para patrimonio, presupuesto, árbol y revisión.
IndicatorInputProvider createIndicatorInputProvider({
  required LocalDatabase database,
}) => RepositoryIndicatorInputProvider(
  wealth: createWealthManagement(database: database),
  budgets: SqliteBudgetRepository(database),
  unitOfWork: SqliteReadUnitOfWork(database),
);

IndicatorSource createIndicatorSource({
  required LocalDatabase database,
  required CategoryReadInvalidation invalidation,
}) => IndicatorSource(
  engine: IndicatorEngine(
    catalog: IndicatorCatalog.v1(),
    inputs: createIndicatorInputProvider(database: database),
    calculations: {'colchon_emergencia': const EmergencyCushionCalculation()},
  ),
  changes: invalidation.changes,
);
