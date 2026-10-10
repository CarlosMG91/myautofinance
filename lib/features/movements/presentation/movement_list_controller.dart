import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/movement_repository.dart';
import '../domain/category_repository.dart';
import '../domain/category_read_invalidation.dart';
import '../domain/movement_management.dart';
import 'movement_editor_source.dart';

/// Etiquetas resueltas por composición; movimientos no depende de patrimonio.
class MovementListSource {
  const MovementListSource({
    required this.movements,
    required this.categories,
    required this.accounts,
    required this.invalidation,
    required this.identity,
    required this.management,
    this.editor,
  });
  final MovementRepository movements;
  final CategoryRepository categories;
  final Future<Map<String, String>> Function() accounts;
  final CategoryReadInvalidation invalidation;

  /// Identidad de la conexión activa; cambia incluso al restaurar la misma copia.
  final Object identity;
  final MovementManagement management;
  final MovementEditorLoader? editor;
}

typedef MovementListLoader = Future<MovementListSource> Function();

enum MovementBatchAction { assignCategory, removeCategory, delete }

/// UUID y base leídos antes del selector/confirmación, nunca una consulta viva.
class MovementBatchRequest {
  const MovementBatchRequest(this.selection, this.context, this.identity);
  final MovementSelection selection;
  final MovementListContext context;
  final Object identity;
}

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
    this.scrollOffset = 0,
    this.focus,
  });
  final ValueDate from;
  final ValueDate? until;
  final String? accountId, categoryId;
  final MovementCategoryScope scope;
  final bool unclassified;
  final String concept;
  final int pageIndex;
  final double scrollOffset;
  final String? focus;
}

class MovementListController extends ChangeNotifier {
  MovementListController({
    required this.load,
    required this.from,
    required this.until,
    this.categoryId,
    this.accountId,
    this.concept = '',
    this.scope = MovementCategoryScope.branch,
    this.unclassified = false,
    this.pageSize = 100,
  });
  final MovementListLoader load;
  final int pageSize;
  ValueDate from;
  ValueDate? until;
  String? accountId, categoryId;
  String concept;
  MovementCategoryScope scope;
  bool unclassified;
  bool loading = false;
  bool batchActive = false;
  bool get locked => loading || batchActive;
  String? error, notice;
  MovementPage? page;
  Map<String, String> accounts = {}, paths = {};
  final selected = <String>{};
  final _cursors = <MovementCursor?>[null];
  int pageIndex = 0;
  int periodRevision = 0;
  double scrollOffset = 0;
  String? focus;
  int _generation = 0;
  bool _disposed = false;
  Object? _readIdentity;
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
    scrollOffset: scrollOffset,
    focus: focus,
  );

  Future<void> refresh({bool restart = false}) async {
    if (batchActive || _disposed) return;
    if (restart) {
      _cursors
        ..clear()
        ..add(null);
      pageIndex = 0;
    }
    final generation = ++_generation;
    final query = context;
    var cursor = _cursors[pageIndex];
    loading = true;
    error = null;
    page = null;
    notifyListeners();
    try {
      final source = await load();
      if (_disposed || generation != _generation) return;
      final replaced =
          _readIdentity != null && !identical(_readIdentity, source.identity);
      if (replaced) {
        // El cursor pertenece a la imagen anterior, aunque su revisión coincida.
        _cursors
          ..clear()
          ..add(null);
        pageIndex = 0;
        cursor = null;
      }
      _changes ??= source.invalidation.changes.listen((_) {
        unawaited(refresh());
      });
      final labels = await source.accounts();
      final nodes = await source.categories.list();
      final byId = {for (final node in nodes) node.id: node};
      if (query.categoryId != null && !byId.containsKey(query.categoryId)) {
        throw const MovementFailure('La categoría no existe.');
      }
      String path(CategoryNode node) => node.parentId == null
          ? node.name
          : '${path(byId[node.parentId]!)} / ${node.name}';
      final categories = {for (final node in nodes) node.id: path(node)};
      final result = await source.movements.readPage(
        from: query.from,
        until: query.until,
        accountId: query.accountId,
        categoryId: query.categoryId,
        categoryScope: query.scope,
        unclassifiedOnly: query.unclassified,
        concept: query.concept,
        after: cursor,
        limit: pageSize,
      );
      if (_disposed || generation != _generation) return;
      accounts = labels;
      paths = categories;
      page = result;
      if (replaced) {
        selected.clear();
        notice = 'La base local ha cambiado. Revisa los movimientos y selecciona de nuevo.';
      }
      _readIdentity = source.identity;
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
    if (batchActive) return;
    if (selected.isNotEmpty) {
      notice = 'Selección limpiada al cambiar página o filtros.';
    }
    selected.clear();
  }

  Future<void> apply() {
    if (locked) return Future.value();
    clearSelection();
    scrollOffset = 0;
    focus = null;
    return refresh(restart: true);
  }

  /// El default de sesión puede cambiar mientras una lectura sigue pendiente.
  /// Los rangos explícitos se resuelven en app y no llaman a este método.
  Future<void> changePeriod(ValueDate value, ValueDate? end) {
    if (batchActive || _disposed) return Future.value();
    from = value;
    until = end;
    periodRevision++;
    clearSelection();
    scrollOffset = 0;
    focus = null;
    return refresh(restart: true);
  }

  Future<void> next() async {
    final cursor = page?.nextCursor;
    if (locked || cursor == null) return;
    clearSelection();
    _cursors.removeRange(pageIndex + 1, _cursors.length);
    _cursors.add(cursor);
    pageIndex++;
    await refresh();
  }

  Future<void> previous() async {
    if (locked || pageIndex == 0) return;
    clearSelection();
    pageIndex--;
    await refresh();
  }

  void toggle(String id, bool value) {
    if (locked || page == null || !page!.records.any((e) => e.id == id)) {
      return;
    }
    value ? selected.add(id) : selected.remove(id);
    notifyListeners();
  }

  void selectPage() {
    if (locked || page == null) return;
    selected
      ..clear()
      ..addAll(page!.records.map((e) => e.id));
    notifyListeners();
  }

  String categoryLabel(String? id) =>
      id == null ? 'Sin clasificar' : paths[id] ?? id;

  MovementBatchRequest? beginBatch() {
    if (locked || selection == null || page == null || _readIdentity == null) {
      return null;
    }
    final request = MovementBatchRequest(selection!, context, _readIdentity!);
    batchActive = true;
    error = null;
    notice = null;
    notifyListeners();
    return request;
  }

  void cancelBatch() {
    if (_disposed) return;
    batchActive = false;
    notifyListeners();
  }

  void rejectBatch(Object failure) {
    if (_disposed) return;
    batchActive = false;
    error =
        'Lote rechazado: ${failure is MovementFailure ? failure.message : 'No se pudo completar la operación local.'} La selección se conserva.';
    notifyListeners();
  }

  Future<void> executeBatch(
    MovementBatchRequest request,
    MovementBatchAction action, {
    String? categoryId,
  }) async {
    if (!batchActive || _disposed) return;
    try {
      final source = await load();
      if (_disposed) return;
      if (!identical(source.identity, request.identity)) {
        throw const MovementFailure(
          'La base local se ha sustituido. Reintenta la lectura y selecciona de nuevo antes de escribir.',
        );
      }
      final ids = request.selection.ids;
      switch (action) {
        case MovementBatchAction.assignCategory:
          if (categoryId == null) {
            throw const MovementFailure('Elige una categoría activa.');
          }
          await source.management.assignCategory(ids, categoryId);
        case MovementBatchAction.removeCategory:
          await source.management.removeCategory(ids);
        case MovementBatchAction.delete:
          await source.management.deleteBatch(ids);
      }
      if (_disposed) return;
      batchActive = false;
      if (action == MovementBatchAction.delete) selected.removeAll(ids);
      final plural = ids.length == 1 ? '' : 's';
      notice =
          '${ids.length} movimiento$plural ${switch (action) {
            MovementBatchAction.assignCategory => 'categorizado$plural',
            MovementBatchAction.removeCategory => 'sin categoría',
            MovementBatchAction.delete => 'borrado$plural',
          }}.';
      await refresh(restart: action == MovementBatchAction.delete);
    } catch (failure) {
      rejectBatch(failure);
    }
  }

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
