import 'package:sqlite3/common.dart';

/// Agregado de memoria constante. NULL señala overflow del resultado int64;
/// no depende del transporte de excepciones SQLite a través de isolates.
final class MovementSubtotal implements AggregateFunction<BigInt> {
  const MovementSubtotal();

  static final _minimum = BigInt.parse('-9223372036854775808');
  static final _maximum = BigInt.parse('9223372036854775807');

  @override
  AggregateContext<BigInt> createContext() => AggregateContext(BigInt.zero);

  @override
  void step(SqliteArguments arguments, AggregateContext<BigInt> context) {
    context.value += BigInt.from(arguments[0] as int);
  }

  @override
  Object? finalize(AggregateContext<BigInt> context) {
    final result = context.value;
    return result < _minimum || result > _maximum ? null : result.toInt();
  }
}
