import 'category_management.dart';

/// Proyección del árbol actual. Recrear tras una invalidación de categorías.
/// Las entradas contienen solo sumas directas por UUID, nunca filas de ancestros.
final class CategoryGrouping {
  CategoryGrouping(Iterable<CategoryDetails> categories)
    : categories = Map.unmodifiable({
        for (final category in categories) category.node.id: category,
      });

  final Map<String, CategoryDetails> categories;

  /// Cada importe se suma una vez por ancestro, manteniendo su signo.
  /// El total general se obtiene de las entradas directas, no de este mapa.
  /// «Sin clasificar» (UUID null) permanece fuera del árbol.
  Map<String, int> aggregate(Map<String, int> directCents) =>
      _aggregate(directCents, 0, (a, b) => a + b);

  /// Acumulación exacta para informes que comprueban int64 al publicar cifras.
  /// También permite agregar contadores sin perder presencia por neto cero.
  Map<String, BigInt> aggregateExact(Map<String, BigInt> direct) =>
      _aggregate(direct, BigInt.zero, (a, b) => a + b);

  Map<String, T> _aggregate<T>(
    Map<String, T> direct,
    T zero,
    T Function(T, T) add,
  ) {
    final totals = {for (final id in categories.keys) id: zero};
    for (final entry in direct.entries) {
      String? id = entry.key;
      final seen = <String>{};
      while (id != null) {
        if (!seen.add(id)) throw StateError('El árbol contiene un ciclo.');
        final category = categories[id];
        if (category == null) throw StateError('Categoría ausente: $id');
        totals[id] = add(totals[id] as T, entry.value);
        id = category.node.parentId;
      }
    }
    return Map.unmodifiable(totals);
  }
}
