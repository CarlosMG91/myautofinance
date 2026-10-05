import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/movement_repository.dart';
import '../domain/movement_management.dart';
import '../domain/category_management.dart';
import 'movement_editor_source.dart';
import 'movement_list_controller.dart' show movementEuro;

class MovementFormScreen extends StatefulWidget {
  const MovementFormScreen({
    super.key,
    required this.load,
    required this.initialDate,
    required this.onReturn,
    required this.onSaved,
    required this.onDeleted,
    required this.selectCategory,
    this.id,
    this.onManageAccounts,
    this.onManageCategories,
    this.destinations = const {},
    this.returnLabel = 'Volver a Movimientos',
  });
  final MovementEditorLoader load;
  final ValueDate initialDate;
  final String? id;
  final VoidCallback onReturn, onDeleted;
  final ValueChanged<MovementRecord> onSaved;
  final Future<CategoryDetails?> Function(String? selectedId) selectCategory;
  final VoidCallback? onManageAccounts;
  final VoidCallback? onManageCategories;
  final Map<String, VoidCallback> destinations;
  final String returnLabel;
  @override
  State<MovementFormScreen> createState() => _MovementFormScreenState();
}

class _MovementFormScreenState extends State<MovementFormScreen> {
  final _date = TextEditingController(),
      _concept = TextEditingController(),
      _amount = TextEditingController(),
      _discretion = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _dateFocus = FocusNode(),
      _conceptFocus = FocusNode(),
      _amountFocus = FocusNode(),
      _accountFocus = FocusNode();
  MovementRecord? _old;
  List<MovementAccountOption> _accounts = [];
  List<CategoryDetails> _categories = [];
  String? _account, _category, _error, _readError;
  bool _loading = true,
      _busy = false,
      _confirming = false,
      _editing = false,
      _allowPop = false,
      _picking = false;
  late final AppLifecycleListener _lifecycle;
  bool get _locked => _busy || _confirming || _picking || _allowPop;
  String _decimal(int cents) {
    final n = BigInt.from(cents).abs();
    return '${cents < 0 ? '-' : '+'}${n ~/ BigInt.from(100)},${(n % BigInt.from(100)).toString().padLeft(2, '0')}';
  }

  bool get _dirty =>
      _editing &&
      (_date.text != (_old?.data.valueDate.value ?? widget.initialDate.value) ||
          _concept.text != (_old?.data.concept ?? '') ||
          _amount.text !=
              (_old == null ? '' : _decimal(_old!.data.amountCents)) ||
          _discretion.text != (_old?.data.discretion ?? '') ||
          _account != _old?.data.accountId ||
          _category != _old?.data.categoryId);
  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        if (_locked) return AppExitResponse.cancel;
        if (!_dirty) return AppExitResponse.exit;
        return await _ask(
              'Hay cambios sin guardar',
              'Descartar el borrador y cerrar Autofinance.',
              'Descartar cambios',
              cancel: 'Seguir editando',
            )
            ? AppExitResponse.exit
            : AppExitResponse.cancel;
      },
    );
    _load();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    for (final f in [_dateFocus, _conceptFocus, _amountFocus, _accountFocus]) {
      f.dispose();
    }
    for (final c in [_date, _concept, _amount, _discretion]) {
      c.dispose();
    }
    super.dispose();
  }

  void _reset() {
    _date.text = _old?.data.valueDate.value ?? widget.initialDate.value;
    _concept.text = _old?.data.concept ?? '';
    _amount.text = _old == null ? '' : _decimal(_old!.data.amountCents);
    _discretion.text = _old?.data.discretion ?? '';
    _account = _old?.data.accountId;
    _category = _old?.data.categoryId;
    _error = null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _readError = null;
    });
    try {
      final source = await widget.load();
      final old = widget.id == null
          ? null
          : await source.management.get(widget.id!);
      final accounts = await source.accounts();
      final categories = await source.categories();
      if (!mounted) return;
      setState(() {
        _old = old;
        _accounts = accounts;
        _categories = categories;
        _editing = widget.id == null;
        _reset();
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _readError =
              'No se pudo abrir este detalle. Comprueba la ruta o reintenta.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _ask(
    String title,
    String message,
    String action, {
    String cancel = 'Cancelar',
  }) async {
    final focus = FocusManager.instance.primaryFocus;
    setState(() => _confirming = true);
    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.all(16),
        title: Focus(
          autofocus: true,
          child: Semantics(header: true, child: Text(title)),
        ),
        content: Text(message),
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
    final result = await Navigator.of(context).push(route) ?? false;
    await route.completed;
    if (mounted) {
      setState(() => _confirming = false);
      if (focus?.context != null) focus?.requestFocus();
    }
    return result;
  }

  Future<void> _leave(VoidCallback action) async {
    if (_locked) return;
    if (_dirty &&
        !await _ask(
          'Hay cambios sin guardar',
          'El borrador se conserva si sigues editando.',
          'Descartar cambios',
          cancel: 'Seguir editando',
        )) {
      return;
    }
    if (mounted) action();
  }

  void _exit(VoidCallback action) {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
  }

  Future<void> _save() async {
    if (_locked) return;
    if (!_form.currentState!.validate()) {
      final focus =
          _validation(_date.text, (s) {
                ValueDate.parse(s.trim());
              }) !=
              null
          ? _dateFocus
          : _concept.text.trim().isEmpty
          ? _conceptFocus
          : _validation(_amount.text, parseMovementAmount) != null
          ? _amountFocus
          : _accountFocus;
      focus.requestFocus();
      if (focus.context != null) await Scrollable.ensureVisible(focus.context!);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final source = await widget.load();
      final data = _old;
      final saved = data == null
          ? await source.management.create(
              accountId: _account!,
              valueDate: _date.text.trim(),
              concept: _concept.text,
              amount: _amount.text,
              categoryId: _category,
              discretion: _discretion.text,
            )
          : await source.management.edit(
              data.id,
              accountId: _account!,
              valueDate: _date.text.trim(),
              concept: _concept.text,
              amount: _amount.text,
              category: _category == data.data.categoryId
                  ? null
                  : MovementChange(_category),
              discretion: _discretion.text == (data.data.discretion ?? '')
                  ? null
                  : MovementChange(_discretion.text),
            );
      if (!mounted) return;
      _exit(() => widget.onSaved(saved));
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is MovementFailure
              ? e.message
              : 'No se pudo guardar. El borrador se conserva; reintenta.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_locked || _old == null) return;
    if (!await _ask(
      'Borrar 1 movimiento',
      '${_old!.data.concept}\nUUID: ${_old!.id}\nEsta acción elimina este movimiento.',
      'Confirmar borrado',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await (await widget.load()).management.delete(_old!.id);
      if (mounted) _exit(widget.onDeleted);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is MovementFailure
              ? e.message
              : 'No se pudo borrar. Reintenta.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    if (_locked) return;
    setState(() => _picking = true);
    try {
      final selected = await widget.selectCategory(_category);
      final categories = await (await widget.load()).categories();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        if (selected != null &&
            (!selected.node.archived ||
                selected.node.id == _old?.data.categoryId)) {
          _category = selected.node.id;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo leer la categoría. Reintenta.');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  String get _categoryLabel {
    final item = _categories.where((c) => c.node.id == _category).firstOrNull;
    return _category == null
        ? 'Sin clasificar'
        : '${item?.path ?? _category}${item?.node.archived == true ? ' · Archivada' : ''}';
  }

  String? _validation(String? value, void Function(String) validate) {
    try {
      validate(value ?? '');
      return null;
    } on MovementFailure catch (e) {
      return e.message;
    }
  }

  List<MovementAccountOption> get _eligible {
    try {
      final date = ValueDate.parse(_date.text.trim());
      return _accounts.where((a) => a.eligible(date)).toList();
    } on MovementFailure {
      return [];
    }
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? Function(String?)? validator,
    int lines = 1,
    FocusNode? focus,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextFormField(
      controller: c,
      focusNode: focus,
      enabled: !_locked,
      maxLines: lines,
      decoration: InputDecoration(labelText: label),
      validator: validator,
      onChanged: (_) => setState(() {}),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final eligible = _eligible;
    final selected = _accounts.where((a) => a.id == _account).firstOrNull;
    return PopScope(
      canPop: _allowPop || (!_dirty && !_locked),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave(() => _exit(widget.onReturn));
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _leave(() => _exit(widget.onReturn)),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              actions: [
                if (widget.onManageAccounts != null ||
                    widget.onManageCategories != null)
                  PopupMenuButton<VoidCallback>(
                    tooltip: 'Gestión',
                    enabled: !_locked,
                    onSelected: (action) => _leave(() => _exit(action)),
                    itemBuilder: (_) => [
                      if (widget.onManageCategories != null)
                        PopupMenuItem(
                          value: widget.onManageCategories!,
                          child: const Text('Categorías'),
                        ),
                      if (widget.onManageAccounts != null)
                        PopupMenuItem(
                          value: widget.onManageAccounts!,
                          child: const Text('Fichas'),
                        ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Gestión'),
                    ),
                  ),
              ],
              title: Text(
                _editing
                    ? (_old == null ? 'Añadir movimiento' : 'Editar movimiento')
                    : 'Detalle de movimiento',
              ),
              leading: IconButton(
                tooltip: widget.returnLabel,
                onPressed: _locked
                    ? null
                    : () => _leave(() => _exit(widget.onReturn)),
                icon: const Icon(Icons.arrow_back),
              ),
            ),
            bottomNavigationBar: widget.destinations.isEmpty || width >= 840
                ? null
                : SafeArea(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        for (final entry in widget.destinations.entries)
                          TextButton(
                            onPressed: _locked
                                ? null
                                : () => _leave(() => _exit(entry.value)),
                            child: Text(entry.key),
                          ),
                      ],
                    ),
                  ),
            body: SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (width >= 840 && widget.destinations.isNotEmpty)
                    Container(
                      width: width >= 1200 ? 216 : 200,
                      color: Colors.white,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text('Autofinance'),
                          for (final entry in widget.destinations.entries)
                            TextButton(
                              onPressed: _locked
                                  ? null
                                  : () => _leave(() => _exit(entry.value)),
                              child: Text(entry.key),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(
                        width >= 1200
                            ? 32
                            : width >= 600
                            ? 24
                            : 16,
                      ),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_loading)
                                const Text('Cargando detalle…')
                              else if (_readError != null) ...[
                                Semantics(
                                  liveRegion: true,
                                  child: Text(_readError!),
                                ),
                                TextButton(
                                  onPressed: _load,
                                  child: const Text('Reintentar'),
                                ),
                              ] else ...[
                                Text(
                                  'UUID: ${_old?.id ?? 'Nuevo movimiento manual'}',
                                ),
                                Text(
                                  'Procedencia: ${_old?.importRowId ?? 'Manual'} · Lote: ${_old?.batchId ?? 'Sin lote'} · Fila: ${_old?.sourceOrdinal ?? 'Sin fila'}',
                                ),
                                if (_editing)
                                  Form(
                                    key: _form,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _field(
                                          _date,
                                          'Fecha de valor · AAAA-MM-DD',
                                          focus: _dateFocus,
                                          validator: (v) => _validation(v, (s) {
                                            ValueDate.parse(s.trim());
                                          }),
                                        ),
                                        _field(
                                          _concept,
                                          'Concepto',
                                          focus: _conceptFocus,
                                          validator: (v) =>
                                              v == null || v.trim().isEmpty
                                              ? 'El concepto es obligatorio.'
                                              : null,
                                        ),
                                        _field(
                                          _amount,
                                          'Importe firmado (EUR)',
                                          focus: _amountFocus,
                                          validator: (v) => _validation(
                                            v,
                                            parseMovementAmount,
                                          ),
                                        ),
                                        const Text(
                                          'Usa + para entrada y - para salida. Coma o punto, hasta dos decimales, sin miles. Cero no es válido.',
                                        ),
                                        DropdownButtonFormField<String>(
                                          key: ValueKey(
                                            '$_account-${_date.text}-${eligible.map((a) => a.id).join()}',
                                          ),
                                          initialValue: _account ?? '',
                                          focusNode: _accountFocus,
                                          isExpanded: true,
                                          itemHeight: null,
                                          isDense: false,
                                          decoration: const InputDecoration(
                                            labelText:
                                                'Cuenta vigente en el mes',
                                          ),
                                          items: [
                                            const DropdownMenuItem(
                                              value: '',
                                              child: Text('Elegir cuenta'),
                                            ),
                                            if (_account != null &&
                                                !eligible.any(
                                                  (a) => a.id == _account,
                                                ))
                                              DropdownMenuItem(
                                                value: _account,
                                                enabled: false,
                                                child: Text(
                                                  '${selected?.name ?? _account} · Referencia histórica no elegible',
                                                ),
                                              ),
                                            for (final a in eligible)
                                              DropdownMenuItem(
                                                value: a.id,
                                                child: Text(
                                                  '${a.name} · ${a.id.substring(0, 8)}',
                                                ),
                                              ),
                                          ],
                                          onChanged: _locked
                                              ? null
                                              : (v) => setState(
                                                  () => _account = v == ''
                                                      ? null
                                                      : v,
                                                ),
                                          validator: (_) =>
                                              eligible.any(
                                                (a) => a.id == _account,
                                              )
                                              ? null
                                              : 'Elige una cuenta vigente para esta fecha.',
                                        ),
                                        if (eligible.isEmpty)
                                          const Text(
                                            'No hay cuentas corrientes vigentes para esta fecha. Gestiona sus altas y vigencia en Gestión → Fichas o cambia la fecha.',
                                          ),
                                        Text(
                                          'Categoría opcional: $_categoryLabel',
                                        ),
                                        Wrap(
                                          spacing: 8,
                                          children: [
                                            OutlinedButton(
                                              onPressed: _locked ? null : _pick,
                                              child: const Text(
                                                'Seleccionar categoría',
                                              ),
                                            ),
                                            TextButton(
                                              onPressed:
                                                  _locked || _category == null
                                                  ? null
                                                  : () => setState(
                                                      () => _category = null,
                                                    ),
                                              child: const Text(
                                                'Quitar categoría',
                                              ),
                                            ),
                                          ],
                                        ),
                                        _field(
                                          _discretion,
                                          'Discrecionalidad opcional',
                                          lines: 3,
                                        ),
                                        const Text(
                                          'Texto libre. Vacío significa sin indicar.',
                                        ),
                                        Wrap(
                                          spacing: 12,
                                          children: [
                                            TextButton(
                                              onPressed: _locked
                                                  ? null
                                                  : () => _leave(() {
                                                      if (_old == null) {
                                                        _exit(widget.onReturn);
                                                      } else {
                                                        setState(() {
                                                          _editing = false;
                                                          _reset();
                                                        });
                                                      }
                                                    }),
                                              child: const Text('Cancelar'),
                                            ),
                                            FilledButton(
                                              onPressed: _locked ? null : _save,
                                              child: Text(
                                                _busy
                                                    ? 'Guardando…'
                                                    : 'Guardar movimiento',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  )
                                else ...[
                                  Text('Fecha: ${_old!.data.valueDate.value}'),
                                  Text('Concepto: ${_old!.data.concept}'),
                                  Text(
                                    'Cuenta: ${selected?.name ?? _old!.data.accountId}',
                                  ),
                                  Text('Categoría: $_categoryLabel'),
                                  Text(
                                    'Importe EUR: ${movementEuro(_old!.data.amountCents)}',
                                  ),
                                  Text(
                                    'Discrecionalidad: ${_old!.data.discretion ?? 'Sin dato'}',
                                  ),
                                  Wrap(
                                    spacing: 12,
                                    children: [
                                      FilledButton(
                                        onPressed: _locked
                                            ? null
                                            : () => setState(
                                                () => _editing = true,
                                              ),
                                        child: const Text('Editar'),
                                      ),
                                      TextButton(
                                        onPressed: _locked ? null : _delete,
                                        child: const Text('Borrar movimiento'),
                                      ),
                                    ],
                                  ),
                                ],
                                if (_error != null)
                                  Semantics(
                                    liveRegion: true,
                                    child: Text(_error!),
                                  ),
                              ],
                              TextButton(
                                onPressed: _locked
                                    ? null
                                    : () =>
                                          _leave(() => _exit(widget.onReturn)),
                                child: Text(widget.returnLabel),
                              ),
                              if (widget.onManageAccounts != null)
                                TextButton(
                                  onPressed: _locked
                                      ? null
                                      : () => _leave(
                                          () => _exit(widget.onManageAccounts!),
                                        ),
                                  child: const Text('Gestión → Fichas'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
