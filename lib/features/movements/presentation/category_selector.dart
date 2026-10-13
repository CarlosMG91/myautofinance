import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

import '../domain/category_management.dart';
import '../domain/category_repository.dart';
import 'category_tree_screen.dart' show CategoryManagementLoader;

/// Borrador local: cancelar devuelve null; el consumidor conserva su UUID.
/// Crear abre el formulario inyectado y no modifica el borrador del consumidor.
class CategorySelector extends StatefulWidget {
  const CategorySelector({
    super.key,
    required this.loadManagement,
    required this.onReturn,
    required this.onCreate,
    this.selectedId,
  });
  final CategoryManagementLoader loadManagement;
  final String? selectedId;
  final ValueChanged<CategoryDetails?> onReturn;
  final Future<CategoryDetails?> Function() onCreate;

  @override
  State<CategorySelector> createState() => _CategorySelectorState();
}

class _CategorySelectorState extends State<CategorySelector> {
  List<CategoryDetails> _items = [];
  String? _selectedId;
  String? _error;
  bool _loading = true;
  bool _creating = false;
  int _request = 0;
  StreamSubscription<int>? _changes;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId;
    _refresh();
  }

  @override
  void dispose() {
    _request++;
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = await widget.loadManagement();
      if (!mounted || request != _request) return;
      _changes ??= service.invalidation.changes.listen((_) => _refresh());
      final items = await service.list();
      if (!mounted || request != _request) return;
      setState(() => _items = items);
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = error is CategoryFailure
            ? error.message
            : 'No se pudieron leer las categorías. Inténtalo de nuevo.';
      });
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    setState(() => _creating = true);
    try {
      final created = await widget.onCreate();
      if (!mounted) return;
      if (created != null) _selectedId = created.node.id;
      await _refresh(); // Cancelar el alta mantiene la selección anterior.
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo abrir el alta de categoría.');
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _items
        .where((item) => item.node.id == _selectedId)
        .firstOrNull;
    final options = _items.where((item) => !item.node.archived).toList();
    final busy = _loading || _creating;
    // Una referencia archivada existente se puede conservar, nunca reasignar.
    final canConfirm =
        !busy &&
        _error == null &&
        selected != null &&
        (!selected.node.archived || selected.node.id == widget.selectedId);
    return PopScope(
      canPop: !_creating,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (!_creating) widget.onReturn(null);
          },
        },
        child: Focus(
          autofocus: true,
          child: AfCatalogPage(
            title: 'Seleccionar categoría',
            contextTrail: const Text(
              'Hasta tres niveles · Tipo heredado de la raíz',
            ),
            actions: [
              OutlinedButton(
                onPressed: busy ? null : _create,
                child: const Text('Crear categoría'),
              ),
              TextButton(
                onPressed: _creating ? null : () => widget.onReturn(null),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: canConfirm ? () => widget.onReturn(selected) : null,
                child: const Text('Seleccionar'),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [
                if (selected != null)
                  AfCard(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        'Selección: ${selected.path}${selected.node.archived ? ' · Archivada' : ''} · ${selected.node.isIncome ? 'Ingreso' : 'Salida'}',
                      ),
                    ),
                  ),
                if (_loading)
                  const AfStatus(
                    kind: AfStatusKind.loading,
                    message: 'Leyendo categorías…',
                  ),
                if (_error != null)
                  AfStatus(
                    kind: AfStatusKind.error,
                    message: _error!,
                    action: AfAction(label: 'Reintentar', onPressed: _refresh),
                  ),
                if (options.isEmpty && !busy && _error == null)
                  const AfStatus(
                    kind: AfStatusKind.empty,
                    message: 'No hay categorías activas.',
                  ),
                for (final item in options)
                  Padding(
                    padding: EdgeInsets.only(left: (item.node.depth - 1) * 12),
                    child: Semantics(
                      selected: item.node.id == _selectedId,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: item.node.id == _selectedId
                              ? AfTokens.accentTint
                              : null,
                          alignment: Alignment.centerLeft,
                        ),
                        onPressed: busy || _error != null
                            ? null
                            : () => setState(() => _selectedId = item.node.id),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.path),
                            Text(
                              '${item.node.isIncome ? 'Ingreso' : 'Salida'} · ${item.node.id}',
                            ),
                            Text(
                              'Nivel ${item.node.depth}${item.node.id == _selectedId ? ' · Seleccionada' : ''}',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
