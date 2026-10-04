import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/account_repository.dart';
import '../domain/wealth_management.dart';
import 'account_catalog_screen.dart';
import 'wealth_controller.dart';
import 'liquidity_form_screen.dart';

class AccountFormScreen extends StatefulWidget {
  const AccountFormScreen({
    super.key,
    required this.loadManagement,
    required this.initialMonth,
    required this.onReturn,
    this.returnLabel = 'Volver al origen',
    required this.onSaved,
    this.accountId,
  });
  final WealthManagementLoader loadManagement;
  final Month initialMonth;
  final String? accountId;
  final VoidCallback onReturn;
  final String returnLabel;
  final ValueChanged<AccountDetails> onSaved;
  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends State<AccountFormScreen> {
  final _name = TextEditingController();
  final _start = TextEditingController();
  final _end = TextEditingController();
  final _nameFocus = FocusNode();
  final _startFocus = FocusNode();
  final _endFocus = FocusNode();
  final _liquidityFocus = FocusNode();
  AccountDetails? _old;
  AccountKind _kind = AccountKind.account;
  Liquidity? _liquidity;
  bool _loaded = false,
      _busy = false,
      _editing = false,
      _allowPop = false,
      _confirming = false;
  String? _readError, _error, _errorField;
  bool get _creating => widget.accountId == null;
  bool get _locked => _busy || _confirming;
  bool get _dirty =>
      _loaded &&
      _editing &&
      (_name.text != (_old?.account.name ?? '') ||
          _start.text !=
              (_old?.account.activeFrom.value.substring(0, 7) ??
                  widget.initialMonth.value.substring(0, 7)) ||
          _end.text !=
              (_old?.account.activeThrough?.value.substring(0, 7) ?? '') ||
          (_creating && (_kind != AccountKind.account || _liquidity != null)));

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _start, _end]) {
      c.dispose();
    }
    for (final f in [_nameFocus, _startFocus, _endFocus, _liquidityFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _readError = null;
    });
    try {
      final old = _creating
          ? null
          : await (await widget.loadManagement()).details(widget.accountId!);
      if (!mounted) return;
      setState(() {
        _old = old;
        _loaded = true;
        _editing = _creating;
        _name.text = old?.account.name ?? '';
        _kind = old?.account.kind ?? AccountKind.account;
        _start.text = (old?.account.activeFrom ?? widget.initialMonth).value
            .substring(0, 7);
        _end.text = old?.account.activeThrough?.value.substring(0, 7) ?? '';
      });
      if (_creating) _nameFocus.requestFocus();
    } catch (e) {
      if (mounted) {
        setState(
          () => _readError = e is AccountFailure
              ? e.message
              : 'No se pudo leer la ficha. Inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
        constraints: const BoxConstraints(maxWidth: 560),
        insetPadding: const EdgeInsets.all(16),
        scrollable: true,
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

  Future<void> _leave() async {
    if (_locked) return;
    if (_dirty &&
        !await _ask(
          'Hay cambios sin guardar',
          'El borrador se descartará al volver.',
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

  void _invalid(String field, String message, FocusNode focus) {
    setState(() {
      _errorField = field;
      _error = message;
    });
    focus.requestFocus();
  }

  Month? _parse(String text) {
    if (!RegExp(r'^[0-9]{4}-[0-9]{2}$').hasMatch(text)) return null;
    try {
      return Month.parse('$text-01');
    } on AccountFailure {
      return null;
    }
  }

  Future<void> _save() async {
    if (_locked || !_loaded || !_editing) return;
    if (_name.text.trim().isEmpty) {
      _invalid('name', 'El nombre no puede estar vacío.', _nameFocus);
      return;
    }
    final start = _parse(_start.text);
    if (start == null) {
      _invalid(
        'start',
        'Introduce un mes válido con formato AAAA-MM.',
        _startFocus,
      );
      return;
    }
    final end = _end.text.isEmpty ? null : _parse(_end.text);
    if (_end.text.isNotEmpty && end == null) {
      _invalid(
        'end',
        'Introduce un mes válido con formato AAAA-MM.',
        _endFocus,
      );
      return;
    }
    if (end != null && end.compareTo(start) < 0) {
      _invalid('end', 'La baja no puede preceder al alta.', _endFocus);
      return;
    }
    if (_creating && _kind != AccountKind.debt && _liquidity == null) {
      setState(() {
        _errorField = 'liquidity';
        _error = 'Selecciona la liquidez del activo.';
      });
      _liquidityFocus.requestFocus();
      return;
    }
    if (!_creating &&
        _old!.account.activeThrough == null &&
        end != null &&
        !await _ask(
          'Dar de baja la ficha',
          'Último mes vigente: ${_end.text}, incluido. Se conservarán la identidad, los movimientos y las fotos. La baja se rechazará si deja referencias fuera de vigencia.',
          'Guardar baja',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _errorField = null;
    });
    try {
      final service = await widget.loadManagement();
      final saved = _creating
          ? await service.create(
              name: _name.text,
              kind: _kind,
              activeFrom: start,
              activeThrough: end,
              liquidity: _kind == AccountKind.debt ? null : _liquidity,
            )
          : await service.edit(
              widget.accountId!,
              name: _name.text,
              activeThrough: end,
            );
      if (!mounted) return;
      setState(() {
        _allowPop = true;
        _busy = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onSaved(saved);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is AccountFailure ? e.message : 'No se pudo guardar. El borrador se conserva; inténtalo de nuevo.';
      });
      _endFocus.requestFocus();
    }
  }

  Future<void> _editLiquidity(bool historical) async {
    if (_locked || _editing || _old == null || _kind == AccountKind.debt) {
      return;
    }
    final saved = await Navigator.of(context).push<AccountDetails>(
      MaterialPageRoute(
        builder: (_) => LiquidityFormScreen(
          details: _old!,
          initialMonth: widget.initialMonth,
          loadManagement: widget.loadManagement,
          historical: historical,
        ),
      ),
    );
    if (!mounted || saved == null) return;
    setState(() => _old = saved);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Liquidez guardada')));
  }

  Widget _history() {
    final periods = _old!.history;
    String month(Month value) => value.value.substring(0, 7);
    String end(LiquidityPeriod p) =>
        p.until == null ? 'Fin de vigencia' : month(p.until!);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 600) {
          return Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              const TableRow(
                children: [
                  Text('Liquidez'),
                  Text('Desde (incluido)'),
                  Text('Hasta (excluido)'),
                ],
              ),
              for (final p in periods)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(liquidityLabel(p.liquidity)),
                    ),
                    Text(month(p.from)),
                    Text(end(p)),
                  ],
                ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final p in periods)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '${liquidityLabel(p.liquidity)} · desde ${month(p.from)} (incluido) hasta ${end(p)} (excluido)',
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _field(
    TextEditingController controller,
    FocusNode focus,
    String label,
    String field,
    bool enabled,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: controller,
      focusNode: focus,
      enabled: enabled && !_locked,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        helperText: field == 'name' ? null : 'AAAA-MM · mes incluido',
        errorText: _errorField == field ? _error : null,
      ),
    ),
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
          title: Text(_creating ? 'Crear ficha' : 'Ficha'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: FocusTraversalGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextButton(
                        onPressed: _locked ? null : _leave,
                        child: Text(widget.returnLabel),
                      ),
                      if (_busy)
                        const LinearProgressIndicator(
                          semanticsLabel: 'Procesando ficha',
                        ),
                      if (_readError != null) ...[
                        const Text('No se pudo abrir este detalle'),
                        Text(_readError!),
                        TextButton(
                          onPressed: _locked ? null : _load,
                          child: const Text('Reintentar'),
                        ),
                      ],
                      if (_loaded) ...[
                        if (_old != null) ...[
                          Text(_old!.account.name),
                          Text('Alta: ${_old!.account.activeFrom.value}'),
                          if (_old!.account.activeThrough != null)
                            Text('Baja: ${_old!.account.activeThrough!.value}'),
                          if (!_editing)
                            TextButton(
                              onPressed: _locked
                                  ? null
                                  : () {
                                      setState(() => _editing = true);
                                      _nameFocus.requestFocus();
                                    },
                              child: const Text('Editar ficha'),
                            ),
                        ],
                        _field(_name, _nameFocus, 'Nombre', 'name', _editing),
                        if (_creating)
                          DropdownButtonFormField<AccountKind>(
                            initialValue: _kind,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Tipo',
                            ),
                            items: [
                              for (final kind in AccountKind.values)
                                DropdownMenuItem(
                                  value: kind,
                                  child: Text(accountKindLabel(kind)),
                                ),
                            ],
                            onChanged: _locked
                                ? null
                                : (value) => setState(() {
                                    _kind = value!;
                                    _liquidity = null;
                                  }),
                          )
                        else
                          Text(
                            'Tipo: ${accountKindLabel(_kind)} · solo lectura',
                          ),
                        const SizedBox(height: 16),
                        if (_creating && _kind != AccountKind.debt) ...[
                          DropdownButtonFormField<Liquidity>(
                            key: ValueKey(_kind),
                            focusNode: _liquidityFocus,
                            initialValue: _liquidity,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Liquidez (obligatoria)',
                              errorText: _errorField == 'liquidity'
                                  ? _error
                                  : null,
                            ),
                            items: [
                              for (final value in Liquidity.values)
                                DropdownMenuItem(
                                  value: value,
                                  child: Text(liquidityLabel(value)),
                                ),
                            ],
                            onChanged: _locked
                                ? null
                                : (value) => setState(() => _liquidity = value),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_kind == AccountKind.debt)
                          const Text('Las deudas no tienen liquidez.'),
                        _field(
                          _start,
                          _startFocus,
                          'Mes de alta',
                          'start',
                          _creating,
                        ),
                        _field(
                          _end,
                          _endFocus,
                          'Mes de baja (opcional)',
                          'end',
                          _editing && _old?.account.activeThrough == null,
                        ),
                        const Text(
                          'La baja conserva el histórico. Las fichas cerradas siguen consultables y no se reabren.',
                        ),
                        if (_old != null && _kind != AccountKind.debt) ...[
                          const SizedBox(height: 16),
                          const Text('Historial de liquidez'),
                          _history(),
                          if (!_editing)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                TextButton(
                                  onPressed: _locked
                                      ? null
                                      : () => _editLiquidity(false),
                                  child: const Text('Cambiar liquidez'),
                                ),
                                TextButton(
                                  onPressed: _locked
                                      ? null
                                      : () => _editLiquidity(true),
                                  child: const Text(
                                    'Corregir liquidez histórica',
                                  ),
                                ),
                              ],
                            ),
                        ],
                        if (_error != null)
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        if (_editing)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton(
                                onPressed: _locked ? null : _leave,
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                onPressed: _locked ? null : _save,
                                child: Text(_busy ? 'Guardando…' : 'Guardar'),
                              ),
                            ],
                          ),
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
  );
}
