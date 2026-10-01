/// Identidad compartida entre copias y revisión de mutaciones confirmadas.
final class DatasetState {
  const DatasetState({required this.datasetId, required this.revision});
  final String datasetId;
  final int revision;
}

/// Todos los repositorios usados en la operación deben compartir conexión.
/// Esperar cada operación; un error revierte datos y revisión conjuntamente.
abstract interface class UnitOfWork {
  Future<T> run<T>(Future<T> Function() operation);
  Future<DatasetState> readState();
}
