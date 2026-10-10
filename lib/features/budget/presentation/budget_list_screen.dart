import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/budget_list_query.dart';
import '../domain/budget_repository.dart';
import '../../movements/movements.dart' show MovementCategoryScope;
import 'budget_source.dart';
import 'budget_ui.dart';

/// Detalle mensual de fuentes originales; usa el editor EP-011 por callback.
class BudgetListScreen extends StatefulWidget {
  const BudgetListScreen({
    super.key,
    required this.load,
    required this.query,
    required this.onReturn,
    required this.onCreate,
    required this.onOpen,
  });
  final BudgetLoader load;
  final BudgetListQuery query;
  final VoidCallback onReturn;
  final Future<void> Function() onCreate;
  final Future<void> Function(String id) onOpen;
  @override
  State<BudgetListScreen> createState() => _BudgetListScreenState();
}

class _BudgetListScreenState extends State<BudgetListScreen> {
  final _scroll = ScrollController();
  final _createFocus = FocusNode();
  final _focus = <String, FocusNode>{};
  StreamSubscription<int>? _changes;
  Object? _identity;
  List<BudgetListEntry> _entries = const [];
  bool _loading = true;
  String? _error;
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void dispose() {
    _revision++;
    _changes?.cancel();
    _scroll.dispose();
    _createFocus.dispose();
    for (final focus in _focus.values) {
      focus.dispose();
    }
    super.dispose();
  }

  Future<void> _read() async {
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final source = await widget.load();
      if (!mounted || revision != _revision) return;
      final reader = source.entries;
      if (reader == null) {
        throw const BudgetFailure('Lista de partidas no disponible.');
      }
      if (!identical(_identity, source.identity)) {
        await _changes?.cancel();
        if (!mounted || revision != _revision) return;
        _identity = source.identity;
        _changes = reader.invalidation.changes.listen((_) => _read());
      }
      final entries = await reader.read(widget.query);
      if (mounted && revision == _revision) setState(() => _entries = entries);
    } catch (e) {
      if (mounted && revision == _revision) {
        setState(() => _error = budgetError(e));
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  Future<void> _open(String? id) async {
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    await (id == null ? widget.onCreate() : widget.onOpen(id));
    if (!mounted) return;
    await _read();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients) {
        _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent));
      }
      final focus = id == null ? null : _focus[id];
      (focus?.context == null ? _createFocus : focus!).requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    const actionStyle = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(48, 48)),
    );
    final query = widget.query;
    final scope = query.unclassified
        ? 'Sin clasificar'
        : query.categoryId == null
        ? 'Todo el mes'
        : query.scope == MovementCategoryScope.direct
        ? 'Solo el nodo'
        : 'Nodo y descendientes';
    return Scaffold(
      appBar: AppBar(title: const Text('Partidas del mes')),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${query.month.value.substring(0, 7)} · $scope'),
              TextButton(
                style: actionStyle,
                onPressed: widget.onReturn,
                child: const Text('Volver al origen'),
              ),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Semantics(
                  liveRegion: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('No se pudo abrir este detalle'),
                      Text(_error!),
                      TextButton(
                        style: actionStyle,
                        onPressed: _read,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              if (!_loading && _error == null) ...[
                if (_entries.isEmpty)
                  const Text(
                    'Sin presupuesto · No hay partidas en este alcance.',
                  ),
                for (final entry in _entries)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${entry.category.path}${entry.category.node.archived ? ' · Archivada' : ''}',
                          ),
                          Text(budgetEuro(entry.record.data.amountCents)),
                          Text(entry.record.id),
                          TextButton(
                            style: actionStyle,
                            focusNode: _focus.putIfAbsent(
                              entry.record.id,
                              FocusNode.new,
                            ),
                            onPressed: () => _open(entry.record.id),
                            child: const Text('Abrir'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_entries.isNotEmpty)
                  Text(
                    'Total de partidas: ${budgetTotal(_entries.fold<BigInt>(BigInt.zero, (sum, entry) => sum + BigInt.from(entry.record.data.amountCents)))}',
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  style: actionStyle,
                  focusNode: _createFocus,
                  onPressed: () => _open(null),
                  child: const Text('Crear partida'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
