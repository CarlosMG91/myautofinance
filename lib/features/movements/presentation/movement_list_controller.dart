import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/movement_repository.dart';
import '../domain/category_repository.dart';
import '../domain/category_read_invalidation.dart';

/// Etiquetas resueltas por composición; movimientos no depende de patrimonio.
class MovementListSource {
  const MovementListSource({
    required this.movements,
    required this.categories,
    required this.accounts,
    required this.invalidation,
  });
  final MovementRepository movements;
  final CategoryRepository categories;
  final Future<Map<String, String>> Function() accounts;
  final CategoryReadInvalidation invalidation;
}

typedef MovementListLoader = Future<MovementListSource> Function();

/// Captura inmutable del alcance para las confirmaciones de lote.
class MovementListContext {
  const MovementListContext({
    required this.from,
    required this.until,
    required this.accountId,
    required this.categoryId,
    required this.scope,
    required this.unclassified,
    required this.concept,
    required this.pageIndex,
  });
  final ValueDate from;
  final ValueDate? until;
  final String? accountId, categoryId;
  final MovementCategoryScope scope;
  final bool unclassified;
  final String concept;
  final int pageIndex;
}

class MovementListController extends ChangeNotifier {
  MovementListController({
    required this.load,
    required this.from,
    required this.until,
    this.categoryId,
    this.scope = MovementCategoryScope.branch,
    this.unclassified = false,
    this.pageSize = 100,
  });
  final MovementListLoader load;
  final int pageSize;
  ValueDate from;
  ValueDate? until;
  String? accountId, categoryId;
  String concept = '';
  MovementCategoryScope scope;
  bool unclassified;
  bool loading = false;
  String? error, notice;
  MovementPage? page;
  Map<String, String> accounts = {}, paths = {};
  final selected = <String>{};
  final _cursors = <MovementCursor?>[null];
  int pageIndex = 0;
  int _generation = 0;
  bool _disposed = false;
  StreamSubscription<int>? _changes;
  MovementSelection? get selection =>
      selected.isEmpty ? null : MovementSelection(selected.toList());
  MovementListContext get context => MovementListContext(
    from: from,
    until: until,
    accountId: accountId,
    categoryId: categoryId,
    scope: scope,
    unclassified: unclassified,
    concept: concept,
    pageIndex: pageIndex,
  );

  Future<void> refresh({bool restart = false}) async {
    if (restart) {
      _cursors
        ..clear()
        ..add(null);
      pageIndex = 0;
    }
    final generation = ++_generation;
    loading = true;
    error = null;
    page = null;
    notifyListeners();
    try {
      final source = await load();
      if (_disposed || generation != _generation) return;
      _changes ??= source.invalidation.changes.listen((_) {
        clearSelection();
        unawaited(refresh(restart: true));
      });
      final labels = await source.accounts();
      final nodes = await source.categories.list();
      final byId = {for (final node in nodes) node.id: node};
      String path(CategoryNode node) => node.parentId == null
          ? node.name
          : '${path(byId[node.parentId]!)} / ${node.name}';
      final categories = {for (final node in nodes) node.id: path(node)};
      final result = await source.movements.readPage(
        from: from,
        until: until,
        accountId: accountId,
        categoryId: categoryId,
        categoryScope: scope,
        unclassifiedOnly: unclassified,
        concept: concept,
        after: _cursors[pageIndex],
        limit: pageSize,
      );
      if (_disposed || generation != _generation) return;
      accounts = labels;
      paths = categories;
      page = result;
      selected.retainAll(result.records.map((e) => e.id));
    } catch (_) {
      if (_disposed || generation != _generation) return;
      error = 'No se pudieron leer los movimientos. Reintenta conservando los filtros y la selección.';
    }
    if (_disposed || generation != _generation) return;
    loading = false;
    notifyListeners();
  }

  void clearSelection() {
    if (selected.isNotEmpty) {
      notice = 'Selección limpiada al cambiar página o filtros.';
    }
    selected.clear();
  }

  Future<void> apply() {
    clearSelection();
    return refresh(restart: true);
  }

  Future<void> next() async {
    final cursor = page?.nextCursor;
    if (loading || cursor == null) return;
    clearSelection();
    _cursors.removeRange(pageIndex + 1, _cursors.length);
    _cursors.add(cursor);
    pageIndex++;
    await refresh();
  }

  Future<void> previous() async {
    if (loading || pageIndex == 0) return;
    clearSelection();
    pageIndex--;
    await refresh();
  }

  void toggle(String id, bool value) {
    if (loading || page == null || !page!.records.any((e) => e.id == id)) {
      return;
    }
    value ? selected.add(id) : selected.remove(id);
    notifyListeners();
  }

  void selectPage() {
    if (loading || page == null) return;
    selected
      ..clear()
      ..addAll(page!.records.map((e) => e.id));
    notifyListeners();
  }

  String categoryLabel(String? id) =>
      id == null ? 'Sin clasificar' : paths[id] ?? id;
  @override
  void dispose() {
    _disposed = true;
    _changes?.cancel();
    super.dispose();
  }
}

/// Formato exacto incluso en los extremos int64, sin conversión a double.
String movementEuro(int cents) {
  final magnitude = BigInt.from(cents).abs();
  final euros = (magnitude ~/ BigInt.from(100)).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  final decimals = (magnitude % BigInt.from(100)).toString().padLeft(2, '0');
  return '${cents < 0 ? '−' : '+'}$euros,$decimals €';
}
