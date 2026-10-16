import '../features/diagnostics/diagnostics.dart';
import '../features/indicators/indicators.dart';
import 'data/sqlite/local_database_store.dart';
import 'data/sqlite/sqlite_diagnostic_source.dart';
import 'indicator_input_factory.dart';

/// Composición pasiva para T05. La fuente resuelve de nuevo la conexión activa
/// después de restaurar; el motor EP-023 comparte el snapshot del diagnóstico.
DiagnosticExecutor createDiagnosticExecutor({
  required LocalDatabaseStore store,
}) => DiagnosticExecutor(
  SqliteDiagnosticSource(
    open: store.open,
    indicator: (database, month) => IndicatorEngine(
      catalog: IndicatorCatalog.v1(),
      inputs: createIndicatorInputProvider(database: database),
      calculations: {'colchon_emergencia': const EmergencyCushionCalculation()},
    ).evaluate('colchon_emergencia', month),
  ),
);
