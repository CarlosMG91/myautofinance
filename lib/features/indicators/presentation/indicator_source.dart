import '../domain/indicator_engine.dart';

typedef IndicatorLoader = Future<IndicatorSource> Function();

/// App resuelve el motor de nuevo en cada lectura, también tras restaurar SQLite.
final class IndicatorSource {
  const IndicatorSource({required this.engine, required this.changes});
  final IndicatorEngine engine;
  final Stream<int> changes;
}
