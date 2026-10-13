import 'dart:async';

import 'package:flutter/material.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

import '../domain/category_management.dart';
import '../domain/category_repository.dart';

/// Resuelve el servicio al leer/escribir: una restauración puede reabrir SQLite.
typedef CategoryManagementLoader = Future<CategoryManagement> Function();

class CategoryTreeScreen extends StatefulWidget {
  const CategoryTreeScreen({
    super.key,
    required this.loadManagement,
    required this.onOpenEditor,
    required this.onReturn,
    required this.returnLabel,
  });
  final CategoryManagementLoader loadManagement;
  final Future<CategoryDetails?> Function(String? id) onOpenEditor;
  final VoidCallback onReturn;
  final String returnLabel;

  @override
  State<CategoryTreeScreen> createState() => _CategoryTreeScreenState();
}

class _CategoryTreeScreenState extends State<CategoryTreeScreen> {
  List<CategoryDetails>? _items;
  String? _error;
  String? _notice;
  bool _loading = false;
  bool _refreshPending = false;
  bool _editing = false;
  StreamSubscription<int>? _changes;
  bool _showArchived = false;
  final _collapsed = <String>{};
  final _scroll = ScrollController();
  final _focus = <String, FocusNode>{};
  final _createFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _changes?.cancel();
    _scroll.dispose();
    _createFocus.dispose();
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) {
      _refreshPending = true;
      return;
    }
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = await widget.loadManagement();
      if (!mounted) return;
      _changes ??= service.invalidation.changes.listen((_) {
        _notice = null;
        if (_editing) {
          _refreshPending = true;
        } else {
          unawaited(_refresh());
        }
      });
      final items = await service.list();
      if (mounted && !_refreshPending) setState(() => _items = items);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is CategoryFailure
              ? e.message
              : 'No se pudieron leer las categorías. Inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_refreshPending) {
          _refreshPending = false;
          unawaited(_refresh());
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) {
            _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent));
          }
        });
      }
    }
  }

  Future<void> _edit(String? id) async {
    _editing = true;
    CategoryDetails? result;
    try {
      result = await widget.onOpenEditor(id);
    } finally {
      _editing = false;
    }
    final saved = result;
    if (!mounted) return;
    if (saved != null) {
      setState(() {
        _notice =
            'Categoría guardada: ${saved.path}. ${saved.node.isIncome ? 'Ingreso' : 'Salida'}.';
        if (saved.node.archived) _showArchived = true;
        // Conserva la expansión del resto del árbol y abre el destino guardado.
        String? ancestor = saved.node.parentId;
        while (ancestor != null) {
          _collapsed.remove(ancestor);
          ancestor = _items!
              .where((item) => item.node.id == ancestor)
              .firstOrNull
              ?.node
              .parentId;
        }
      });
    }
    if (saved != null || _refreshPending) {
      _refreshPending = false;
      await _refresh();
    }
    if (!mounted) return;
    final focus = saved == null && id == null
        ? _createFocus
        : _focus['edit-${saved?.node.id ?? id}'];
    void restoreFocus() {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) focus?.requestFocus();
      });
      // La lectura puede acabar después del último frame de la transición.
      WidgetsBinding.instance.scheduleFrame();
    }

    final animation = ModalRoute.of(context)?.secondaryAnimation;
    if (animation != null && animation.status != AnimationStatus.dismissed) {
      void afterReturn(AnimationStatus status) {
        if (status != AnimationStatus.dismissed) return;
        animation.removeStatusListener(afterReturn);
        restoreFocus();
      }

      animation.addStatusListener(afterReturn);
    } else {
      restoreFocus();
    }
  }

  List<CategoryDetails> get _visible {
    final output = <CategoryDetails>[];
    void walk(String? parent) {
      for (final item in _items!) {
        if (item.node.parentId != parent) continue;
        if (item.node.archived && !_showArchived) continue;
        output.add(item);
        if (!_collapsed.contains(item.node.id)) walk(item.node.id);
      }
    }

    walk(null);
    return output;
  }

  Widget _identity(CategoryDetails item) {
    final node = item.node;
    final hasChildren = _items!.any(
      (child) =>
          child.node.parentId == node.id &&
          (_showArchived || !child.node.archived),
    );
    final expanded = !_collapsed.contains(node.id);
    return Padding(
      padding: EdgeInsets.only(left: (node.depth - 1) * 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasChildren)
            MergeSemantics(
              child: Semantics(
                expanded: expanded,
                label: '${expanded ? 'Contraer' : 'Expandir'} ${item.path}',
                child: TextButton(
                  focusNode: _focus.putIfAbsent(
                    'toggle-${node.id}',
                    FocusNode.new,
                  ),
                  onPressed: () => setState(() {
                    expanded
                        ? _collapsed.add(node.id)
                        : _collapsed.remove(node.id);
                    _notice =
                        '${item.path} ${expanded ? 'contraída' : 'expandida'}.';
                  }),
                  child: Text(
                    '${expanded ? '−' : '+'} ${node.name}',
                    softWrap: true,
                  ),
                ),
              ),
            )
          else
            Text(
              node.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          Text(item.path),
          Text('Nivel ${node.depth}', style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  String _type(CategoryNode node) =>
      '${node.isIncome ? 'Ingreso' : 'Salida'}${node.parentId != null ? ' · heredado' : ''}';

  Widget _editButton(CategoryDetails item) => MergeSemantics(
    child: Semantics(
      label: 'Editar ${item.path}',
      child: OutlinedButton(
        focusNode: _focus.putIfAbsent('edit-${item.node.id}', FocusNode.new),
        onPressed: () => _edit(item.node.id),
        child: const Text('Editar / gestionar'),
      ),
    ),
  );

  Widget _table(List<CategoryDetails> items) => Table(
    columnWidths: const {
      0: FlexColumnWidth(3),
      1: FlexColumnWidth(1.5),
      2: FlexColumnWidth(1),
      3: FlexColumnWidth(1.5),
    },
    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
    border: const TableBorder(
      horizontalInside: BorderSide(color: AfTokens.border),
    ),
    children: [
      TableRow(
        decoration: const BoxDecoration(color: AfTokens.surfaceSubtle),
        children: [
          for (final label in [
            'Categoría / ruta',
            'Tipo efectivo',
            'Estado',
            'Acciones',
          ])
            Padding(
              padding: const EdgeInsets.all(10),
              child: Semantics(
                header: true,
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
      for (final item in items)
        TableRow(
          children: [
            Padding(padding: const EdgeInsets.all(10), child: _identity(item)),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(_type(item.node)),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(item.node.archived ? 'Archivada' : 'Activa'),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: _editButton(item),
            ),
          ],
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final visible = _items == null ? <CategoryDetails>[] : _visible;
    return AfCatalogPage(
      title: 'Categorías',
      contextTrail: const Text('Gestión · Organización de ingresos y salidas'),
      scrollController: _scroll,
      actions: [
        AfAction(
          label: widget.returnLabel,
          onPressed: widget.onReturn,
          variant: AfActionVariant.link,
          icon: AfIcons.back,
        ),
        FilledButton(
          focusNode: _createFocus,
          onPressed: _loading || _error != null ? null : () => _edit(null),
          child: const Text('Crear categoría'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          const Text(
            'Hasta tres niveles. El tipo se hereda de la raíz; los signos son independientes.',
          ),
          Material(
            color: Colors.transparent,
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Mostrar también archivadas'),
              value: _showArchived,
              onChanged: (value) => setState(() => _showArchived = value!),
            ),
          ),
          if (_notice != null)
            AfStatus(kind: AfStatusKind.success, message: _notice!),
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
            )
          else if (_items != null && !_loading)
            if (visible.isEmpty)
              const AfStatus(
                kind: AfStatusKind.empty,
                message: 'No hay categorías para mostrar. Puedes crear una o mostrar las archivadas.',
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 840 &&
                      !AfTokens.reflow(context, constraints.maxWidth)) {
                    return _table(visible);
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: [
                      for (final item in visible)
                        AfCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: 12,
                            children: [
                              _identity(item),
                              AfValueRow(
                                label: _type(item.node),
                                value: Text(
                                  item.node.archived ? 'Archivada' : 'Activa',
                                ),
                              ),
                              _editButton(item),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
        ],
      ),
    );
  }
}
