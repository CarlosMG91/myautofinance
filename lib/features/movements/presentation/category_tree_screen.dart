import 'package:flutter/material.dart';

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
    _scroll.dispose();
    _createFocus.dispose();
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = await widget.loadManagement();
      final items = await service.list();
      if (mounted) setState(() => _items = items);
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) {
            _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent));
          }
        });
      }
    }
  }

  Future<void> _edit(String? id) async {
    final saved = await widget.onOpenEditor(id);
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
      await _refresh();
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focus = saved == null && id == null
          ? _createFocus
          : _focus['edit-${saved?.node.id ?? id}'];
      focus?.requestFocus();
    });
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
    border: TableBorder.all(color: const Color(0xffd5dde5)),
    children: [
      TableRow(
        decoration: const BoxDecoration(color: Color(0xffeef3f8)),
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Categorías'),
      automaticallyImplyLeading: false,
    ),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final padding = width < 600
              ? 16.0
              : width < 1200
              ? 24.0
              : 32.0;
          final visible = _items == null ? <CategoryDetails>[] : _visible;
          return SingleChildScrollView(
            controller: _scroll,
            padding: EdgeInsets.all(padding),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: widget.onReturn,
                          child: Text(widget.returnLabel),
                        ),
                        FilledButton(
                          focusNode: _createFocus,
                          onPressed: _loading || _error != null
                              ? null
                              : () => _edit(null),
                          child: const Text('Crear categoría'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Hasta tres niveles. El tipo se hereda de la raíz; los signos son independientes.',
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Mostrar también archivadas'),
                      value: _showArchived,
                      onChanged: (value) =>
                          setState(() => _showArchived = value!),
                    ),
                    if (_notice != null)
                      Semantics(
                        liveRegion: true,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(_notice!),
                        ),
                      ),
                    if (_loading)
                      Semantics(
                        liveRegion: true,
                        child: Text('Leyendo categorías…'),
                      ),
                    if (_error != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _refresh,
                        child: const Text('Reintentar'),
                      ),
                    ] else if (_items != null && !_loading) ...[
                      if (visible.isEmpty)
                        const Text(
                          'No hay categorías para mostrar. Puedes crear una o mostrar las archivadas.',
                        )
                      else if (width >= 840)
                        _table(visible)
                      else
                        for (final item in visible)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _identity(item),
                                  const SizedBox(height: 12),
                                  Text(_type(item.node)),
                                  Text(
                                    item.node.archived ? 'Archivada' : 'Activa',
                                  ),
                                  const SizedBox(height: 12),
                                  _editButton(item),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
