import 'dart:async';

/// Compartido por la sesión, también al resolver otra conexión tras restaurar.
/// Los consumidores descartan árbol, rutas, agregados e ingresos presupuestados.
/// No es una revisión persistente ni un cambio de la fórmula del indicador.
final class CategoryReadInvalidation {
  final _events = StreamController<int>.broadcast(sync: true);
  int _generation = 0;
  int get generation => _generation;
  Stream<int> get changes => _events.stream;

  /// Después del commit o de reemplazar la base; nunca durante una transacción.
  void invalidate() => _events.add(++_generation);

  Future<void> close() => _events.close();
}
