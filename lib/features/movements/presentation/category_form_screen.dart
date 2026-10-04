import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../domain/category_management.dart';
import '../domain/category_repository.dart';
import 'category_tree_screen.dart';

class CategoryFormScreen extends StatefulWidget {
  const CategoryFormScreen({
    super.key,
    required this.loadManagement,
    required this.onSaved,
    required this.onReturn,
    this.categoryId,
    this.returnLabel = 'Volver al árbol',
  });
  final CategoryManagementLoader loadManagement;
  final String? categoryId;
  final ValueChanged<CategoryDetails> onSaved;
  final VoidCallback onReturn;
  final String returnLabel;
  @override
  State<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends State<CategoryFormScreen> {
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  final _parentFocus = FocusNode();
  final _typeFocus = FocusNode();
  final _saveFocus = FocusNode();
  final _archiveFocus = FocusNode();
  List<CategoryDetails>? _items;
  CategoryDetails? _old;
  String? _parentId;
  bool _income = false;
  bool _canChangeType = false;
  bool _busy = false;
  bool _confirming = false;
  bool _allowPop = false;
  String? _readError;
  String? _error;
  Map<String, String> _fieldErrors = {};
  List<CategoryBudgetConflict> _conflicts = [];

  bool get _dirty =>
      _items != null &&
      (_name.text != (_old?.node.name ?? '') ||
          _parentId != _old?.node.parentId ||
          (_parentId == null &&
              !_promoting &&
              _income != (_old?.node.isIncome ?? false)));
  bool get _promoting => _old?.node.parentId != null && _parentId == null;
  bool get _locked => _busy || _confirming;
  bool get _readOnlyType =>
      _parentId != null || _promoting || (_old != null && !_canChangeType);
  CategoryDetails? _find(String? id) {
    for (final item in _items ?? <CategoryDetails>[]) {
      if (item.node.id == id) return item;
    }
    return null;
  }

  bool get _effectiveIncome => _parentId != null
      ? _find(_parentId)!.node.isIncome
      : _promoting
      ? _old!.node.isIncome
      : _income;
  String _type(bool income) => income ? 'Ingreso' : 'Salida';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    for (final focus in [
      _nameFocus,
      _parentFocus,
      _typeFocus,
      _saveFocus,
      _archiveFocus,
    ]) {
      focus.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _readError = null;
      _busy = true;
    });
    try {
      final service = await widget.loadManagement();
      final items = await service.list();
      CategoryDetails? old;
      if (widget.categoryId != null) {
        old = items
            .where((item) => item.node.id == widget.categoryId)
            .firstOrNull;
        if (old == null) {
          throw const CategoryFailure(
            'No se pudo abrir este detalle. La categoría no existe.',
          );
        }
      }
      final canChange = old == null
          ? true
          : await service.canChangeRootType(old.node.id);
      if (!mounted) return;
      setState(() {
        _items = items;
        _old = old;
        _canChangeType = canChange;
        _name.text = old?.node.name ?? '';
        _parentId = old?.node.parentId;
        _income = old?.node.isIncome ?? false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _nameFocus.requestFocus();
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _readError = e is CategoryFailure
              ? e.message
              : 'No se pudo abrir este detalle. Inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Set<String> get _branch {
    if (_old == null) return {};
    final ids = {_old!.node.id};
    for (var i = 0; i < 3; i++) {
      ids.addAll(
        _items!
            .where((item) => ids.contains(item.node.parentId))
            .map((item) => item.node.id)
            .toList(),
      );
    }
    return ids;
  }

  Future<bool> _ask(
    String title,
    List<String> paragraphs,
    String action, {
    String cancel = 'Cancelar',
  }) async {
    if (_confirming || !mounted) return false;
    final returnFocus = FocusManager.instance.primaryFocus;
    setState(() => _confirming = true);
    final dialog = DialogRoute<bool>(
      context: context,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      builder: (context) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 560),
        insetPadding: const EdgeInsets.all(16),
        contentPadding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
        ),
        scrollable: true,
        title: Focus(
          autofocus: true,
          child: Semantics(header: true, child: Text(title)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final text in paragraphs)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(text),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    final accepted = await Navigator.of(context).push(dialog) ?? false;
    await dialog.completed;
    if (mounted) {
      setState(() => _confirming = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && returnFocus?.context != null) {
          returnFocus?.requestFocus();
        }
      });
    }
    return accepted;
  }

  Future<void> _leave() async {
    if (_locked) return;
    if (_dirty &&
        !await _ask(
          'Hay cambios sin guardar',
          ['Descartar vuelve al contexto anterior sin guardar el borrador.'],
          'Descartar cambios',
          cancel: 'Seguir editando',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReturn();
    });
  }

  void _validation(String message, FocusNode focus, String field) {
    setState(() {
      _error = message;
      _fieldErrors = {field: message};
      _conflicts = [];
    });
    focus.requestFocus();
  }

  Future<void> _save() async {
    if (_locked || _items == null) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      _validation('El nombre no puede estar vacío.', _nameFocus, 'name');
      return;
    }
    final parent = _find(_parentId);
    if (parent?.node.archived == true) {
      _validation(
        'El padre está archivado. Reactiva primero su rama.',
        _parentFocus,
        'parentId',
      );
      return;
    }
    if (_parentId != null && _branch.contains(_parentId)) {
      _validation(
        'El padre no puede ser esta categoría ni un descendiente: crearía un ciclo.',
        _parentFocus,
        'parentId',
      );
      return;
    }
    final branchHeight = _old == null
        ? 1
        : _items!
              .where((item) => _branch.contains(item.node.id))
              .map((item) => item.node.depth - _old!.node.depth + 1)
              .reduce((a, b) => a > b ? a : b);
    if ((parent?.node.depth ?? 0) + branchHeight > 3) {
      _validation(
        'La rama completa superaría tres niveles. Elige un padre menos profundo.',
        _parentFocus,
        'parentId',
      );
      return;
    }
    if (_old != null && _old!.node.parentId != _parentId) {
      final after = parent == null ? name : '${parent.path} / $name';
      final ok = await _ask(
        _parentId == null ? 'Convertir en raíz' : 'Trasladar rama completa',
        [
          'Antes: ${_old!.path} · ${_type(_old!.node.isIncome)}',
          'Después: $after · ${_type(_effectiveIncome)}',
          '${_branch.length} categorías. Todo el histórico sigue sus UUID y adopta la clasificación actual; conserva importes, signos, fechas, cuentas y discrecionalidad. Los agregados cambian; los totales generales permanecen.',
          'El indicador consulta el presupuesto de ingresos con las raíces actuales. Las fotos y la fórmula permanecen.',
        ],
        _parentId == null ? 'Convertir en raíz' : 'Trasladar rama',
      );
      if (!ok || !mounted) return;
    }
    await _write(
      (service) => _old == null
          ? service.create(
              name: name,
              parentId: _parentId,
              isIncome: _parentId == null ? _income : null,
            )
          : service.edit(
              _old!.node.id,
              name: name,
              parentId: _parentId,
              isIncome: _parentId != null || _promoting ? null : _income,
            ),
    );
  }

  Future<void> _archive() async {
    if (_locked || _old == null) return;
    if (_dirty &&
        !await _ask(
          'Hay cambios sin guardar',
          [
            'Los cambios del formulario se descartarán al cambiar el estado de la rama.',
          ],
          'Descartar cambios',
          cancel: 'Seguir editando',
        )) {
      return;
    }
    if (!mounted) return;
    final archived = _old!.node.archived;
    final ok = await _ask(
      archived ? 'Reactivar rama completa' : 'Archivar rama completa',
      [
        '${_old!.path} · ${_branch.length} categorías.',
        archived
            ? 'Se reactivan todos los descendientes, incluidos los archivados previamente.'
            : 'La rama no estará disponible para nuevas asignaciones. El histórico y las correcciones de registros ya referenciados se conservan.',
      ],
      archived ? 'Reactivar rama' : 'Archivar rama',
    );
    if (!ok || !mounted) return;
    await _write(
      (service) => archived
          ? service.reactivate(_old!.node.id)
          : service.archive(_old!.node.id),
    );
  }

  Future<void> _write(
    Future<CategoryDetails> Function(CategoryManagement) operation,
  ) async {
    if (_locked) return;
    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = {};
      _conflicts = [];
    });
    try {
      final service = await widget.loadManagement();
      final saved = await operation(service);
      if (!mounted) return;
      setState(() {
        _allowPop = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onSaved(saved);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (e is CategoryFormFailure) {
          _fieldErrors = e.fields;
          _error = e.toString();
        } else if (e is CategoryFailure) {
          _error = e.message;
          _conflicts = e.budgetConflicts;
        } else {
          _error = 'No se pudo guardar la categoría. El borrador se conserva; inténtalo de nuevo.';
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        (_fieldErrors.containsKey('name') ? _nameFocus : _parentFocus)
            .requestFocus();
      });
    }
  }

  Widget _parentPicker() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Padre', style: TextStyle(fontSize: 16)),
      const SizedBox(height: 8),
      OutlinedButton(
        focusNode: _parentFocus,
        onPressed: _locked
            ? null
            : () async {
                final selected = await showDialog<String>(
                  context: context,
                  builder: (context) => SimpleDialog(
                    insetPadding: const EdgeInsets.all(16),
                    title: const Text('Seleccionar padre'),
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, ''),
                        child: const Text('Sin padre · convertir en raíz'),
                      ),
                      for (final item in _items!)
                        TextButton(
                          onPressed: () => Navigator.pop(context, item.node.id),
                          child: Text(
                            '${item.path}${item.node.archived ? ' · archivada' : ''} · ${item.node.id}',
                          ),
                        ),
                    ],
                  ),
                );
                if (mounted && selected != null) {
                  setState(() {
                    _parentId = selected.isEmpty ? null : selected;
                  });
                }
                if (mounted) _parentFocus.requestFocus();
              },
        child: Text(
          _parentId == null
              ? 'Sin padre · convertir en raíz'
              : '${_find(_parentId)!.path} · ${_parentId!}',
        ),
      ),
      if (_fieldErrors['parentId'] != null)
        Text(
          _fieldErrors['parentId']!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      const SizedBox(height: 8),
      const Text(
        'El traslado incluye toda la rama. No admite ciclos, cuarto nivel ni padre archivado.',
        style: TextStyle(fontSize: 14),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: _allowPop || (!_dirty && !_locked),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _leave();
    },
    child: CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _leave},
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.categoryId == null ? 'Crear categoría' : 'Editar categoría',
          ),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: EdgeInsets.all(constraints.maxWidth < 600 ? 16 : 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: FocusTraversalGroup(
                    policy: OrderedTraversalPolicy(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextButton(
                          onPressed: _locked ? null : _leave,
                          child: Text(widget.returnLabel),
                        ),
                        if (_items == null && _readError == null)
                          Semantics(
                            liveRegion: true,
                            child: Text('Leyendo categoría…'),
                          ),
                        if (_readError != null) ...[
                          Semantics(liveRegion: true, child: Text(_readError!)),
                          TextButton(
                            onPressed: _busy ? null : _load,
                            child: const Text('Reintentar'),
                          ),
                        ],
                        if (_items != null) ...[
                          Text(
                            _old == null
                                ? 'Nueva identidad; los nombres duplicados están permitidos.'
                                : '${_old!.path} · UUID ${_old!.node.id} · ${_old!.node.archived ? 'Archivada' : 'Activa'}',
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _name,
                            focusNode: _nameFocus,
                            enabled: !_locked,
                            decoration: InputDecoration(
                              labelText: 'Nombre',
                              errorText: _fieldErrors['name'],
                            ),
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _save(),
                          ),
                          const SizedBox(height: 16),
                          _parentPicker(),
                          const SizedBox(height: 16),
                          if (_readOnlyType)
                            InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Tipo · solo lectura',
                              ),
                              child: Text(_type(_effectiveIncome)),
                            )
                          else
                            DropdownButtonFormField<bool>(
                              initialValue: _income,
                              focusNode: _typeFocus,
                              decoration: InputDecoration(
                                labelText: 'Tipo',
                                errorText: _fieldErrors['isIncome'],
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: true,
                                  child: Text('Ingreso'),
                                ),
                                DropdownMenuItem(
                                  value: false,
                                  child: Text('Salida'),
                                ),
                              ],
                              onChanged: _locked
                                  ? null
                                  : (value) => setState(() => _income = value!),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            _parentId != null
                                ? 'Hereda ${_type(_effectiveIncome)} de la raíz destino. Todo el histórico adopta esta clasificación sin invertir signos.'
                                : _promoting
                                ? 'Promoción: conserva el tipo efectivo anterior. No se elige otro tipo.'
                                : _old != null && !_canChangeType
                                ? 'Tipo bloqueado: existen movimientos o partidas en esta raíz o sus descendientes, incluidos históricos y archivados.'
                                : 'Marca exclusiva de raíz sin registros. No se deduce del signo.',
                            style: const TextStyle(fontSize: 14),
                          ),
                          if (_error != null)
                            Semantics(
                              liveRegion: true,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _error!,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                    ),
                                    for (final conflict in _conflicts)
                                      Text(
                                        '${DateFormat("MMMM 'de' yyyy", 'es_ES').format(DateTime.parse(conflict.month))}: ${conflict.ancestorPath} [${conflict.ancestorId}] ↔ ${conflict.descendantPath} [${conflict.descendantId}]',
                                      ),
                                    const Text(
                                      'El borrador se conserva. Revisa las partidas en conflicto antes de reintentar.',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (_busy)
                            Semantics(
                              liveRegion: true,
                              child: Text('Guardando categoría…'),
                            ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton(
                                onPressed: _locked ? null : _leave,
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                focusNode: _saveFocus,
                                onPressed: _locked ? null : _save,
                                child: Text(
                                  _old == null
                                      ? 'Crear categoría'
                                      : 'Revisar y guardar',
                                ),
                              ),
                            ],
                          ),
                          if (_old != null) ...[
                            const SizedBox(height: 24),
                            const Text(
                              'Estado de la rama',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${_branch.length} categorías. Archivar conserva el histórico y retira la rama de nuevas asignaciones. Reactivar incluye todos los descendientes.',
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              focusNode: _archiveFocus,
                              onPressed: _locked ? null : _archive,
                              child: Text(
                                _old!.node.archived
                                    ? 'Reactivar rama completa'
                                    : 'Archivar rama completa',
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
