import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/category_read_invalidation.dart';
import '../domain/movement_repository.dart';
import '../domain/pending_movement_management.dart';
import '../domain/pending_movement_repository.dart';

class PendingMovementSource {
  const PendingMovementSource({
    required this.management,
    required this.accounts,
    required this.batches,
    required this.invalidation,
    required this.identity,
  });
  final PendingMovementManagement management;
  final Future<Map<String, String>> Function() accounts, batches;
  final CategoryReadInvalidation invalidation;
  final Object identity;
}

typedef PendingMovementLoader = Future<PendingMovementSource> Function();

class PendingMovementController extends ChangeNotifier {
  PendingMovementController({
    required this.load,
    PendingMovementQuery? query,
    this.pageSize = 100,
  }) : query = query ?? PendingMovementQuery();

  final PendingMovementLoader load;
  final int pageSize;
  PendingMovementQuery query;
  PendingMovementPage? page;
  Map<String, String> accounts = {}, batches = {};
  final selected = <String>{};
  bool loading = false, operationActive = false, sending = false;
  bool requiresRefresh = false, filtersValid = true;
  bool get locked => loading || operationActive;
  bool get canAssign =>
      !locked && filtersValid && !requiresRefresh && page != null;
  String? error, notice;
  int pageIndex = 0;
  final _cursors = <MovementCursor?>[null];
  Object? _identity;
  String? _dataset;
  StreamSubscription<int>? _changes;
  CategoryReadInvalidation? _invalidation;
  int _generation = 0;
  bool _disposed = false;
  PendingMovementSelection? _operation;

  Future<void> refresh({
    bool restart = false,
    bool clearSelection = false,
  }) async {
    if (_disposed || operationActive) return;
    if (clearSelection) selected.clear();
    if (restart) _restart();
    final generation = ++_generation;
    loading = true;
    error = null;
    page = null; // Sin contador antiguo durante carga o fallo de lectura.
    notifyListeners();
    try {
      final source = await load();
      if (_disposed || generation != _generation) return;
      if (_identity != null && !identical(_identity, source.identity)) {
        _restart();
        selected.clear();
        notice =
            'La base local ha cambiado. Selecciona de nuevo los pendientes.';
      }
      if (!identical(_invalidation, source.invalidation)) {
        await _changes?.cancel();
        _invalidation = source.invalidation;
        _changes = source.invalidation.changes.listen((_) {
          // Una invalidación durante selector/confirmación se revalida al guardar.
          if (!operationActive && filtersValid && !requiresRefresh) {
            unawaited(refresh());
          }
        });
      }
      final labels = await source.accounts();
      final batchLabels = await source.batches();
      var result = await source.management.readPage(
        query: query,
        after: _cursors[pageIndex],
        limit: pageSize,
      );
      if (_disposed || generation != _generation) return;
      if (_dataset != null && _dataset != result.datasetId) {
        _restart();
        selected.clear();
        result = await source.management.readPage(
          query: query,
          limit: pageSize,
        );
        notice =
            'La base local ha cambiado. Selecciona de nuevo los pendientes.';
      }
      // Si una página se agotó tras una edición, volver al inicio del ámbito.
      if (result.records.isEmpty && pageIndex > 0) {
        _restart();
        selected.clear();
        result = await source.management.readPage(
          query: query,
          limit: pageSize,
        );
      }
      if (_disposed || generation != _generation) return;
      accounts = labels;
      batches = batchLabels;
      page = result;
      _identity = source.identity;
      _dataset = result.datasetId;
      selected.retainAll(result.records.map((r) => r.id));
      if (clearSelection) requiresRefresh = false;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      error = 'No se pudieron consultar los pendientes. Filtros y selección conservados; contador no disponible.';
    }
    if (_disposed || generation != _generation) return;
    loading = false;
    notifyListeners();
  }

  void _restart() {
    _cursors
      ..clear()
      ..add(null);
    pageIndex = 0;
  }

  void filtersEdited() {
    if (operationActive) return;
    selected.clear();
    filtersValid = false;
    notice = 'Selección limpiada al cambiar filtros. Aplica los filtros para consultar.';
    notifyListeners();
  }

  Future<void> apply(PendingMovementQuery filters) async {
    if (locked) return;
    query = filters;
    filtersValid = true;
    await refresh(restart: true, clearSelection: true);
  }

  Future<void> update() => refresh(restart: true, clearSelection: true);

  Future<void> next() async {
    final cursor = page?.nextCursor;
    if (!canAssign || cursor == null) return;
    selected.clear();
    _cursors.removeRange(pageIndex + 1, _cursors.length);
    _cursors.add(cursor);
    pageIndex++;
    await refresh();
  }

  Future<void> previous() async {
    if (!canAssign || pageIndex == 0) return;
    selected.clear();
    pageIndex--;
    await refresh();
  }

  void toggle(String id, bool value) {
    if (!canAssign || !page!.records.any((r) => r.id == id)) return;
    value ? selected.add(id) : selected.remove(id);
    notifyListeners();
  }

  void selectPage() {
    if (!canAssign) return;
    selected
      ..clear()
      ..addAll(page!.records.map((r) => r.id));
    notifyListeners();
  }

  void clearSelection() {
    if (locked) return;
    selected.clear();
    notifyListeners();
  }

  PendingMovementSelection? beginAssignment({String? id}) {
    if (!canAssign || (id == null && selected.isEmpty)) return null;
    final request = page!.select(id == null ? selected.toList() : [id]);
    _operation = request;
    operationActive = true;
    error = null;
    notice = null;
    notifyListeners();
    return request;
  }

  void cancelAssignment() {
    if (_disposed || sending) return;
    operationActive = false;
    _operation = null;
    notifyListeners();
  }

  void rejectAssignment(Object failure) {
    if (_disposed) return;
    operationActive = sending = false;
    _operation = null;
    requiresRefresh = failure is MovementFailure && failure.requiresRefresh;
    error =
        '${failure is MovementFailure ? failure.message : 'No se pudo guardar la categoría.'} '
        'La selección se conserva.${requiresRefresh ? ' Actualiza los pendientes y vuelve a seleccionar antes de reintentar.' : ''}';
    notifyListeners();
  }

  Future<bool> assign(
    PendingMovementSelection request,
    String categoryId,
  ) async {
    if (_disposed ||
        !operationActive ||
        sending ||
        !identical(_operation, request)) {
      return false;
    }
    sending = true;
    notifyListeners();
    try {
      final source = await load(); // Resolver siempre la conexión activa.
      if (_disposed) return false;
      if (!identical(source.identity, request.databaseIdentity)) {
        throw const MovementFailure(
          'La base local ha cambiado.',
          requiresRefresh: true,
        );
      }
      await source.management.assignCategory(request, categoryId);
    } catch (failure) {
      rejectAssignment(failure);
      return false;
    }
    if (_disposed) return true;
    operationActive = sending = false;
    _operation = null;
    selected.clear();
    notice =
        '${request.movements.ids.length} movimientos categorizados. Selección limpiada; filtros conservados.';
    await refresh(restart: true, clearSelection: true);
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _changes?.cancel();
    super.dispose();
  }
}
