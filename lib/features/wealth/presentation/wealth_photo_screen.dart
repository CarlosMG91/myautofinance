import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../domain/account_repository.dart';
import '../domain/wealth_amount.dart';
import '../domain/wealth_repository.dart';
import 'account_catalog_screen.dart';
import 'wealth_controller.dart';

class WealthPhotoScreen extends StatefulWidget {
  const WealthPhotoScreen({
    super.key,
    required this.controller,
    required this.month,
    required this.onReturn,
    required this.onSaved,
    this.destinations = const {},
    this.onNavigate,
  });
  final WealthController controller;
  final Month month;
  final VoidCallback onReturn;
  final ValueChanged<WealthSnapshot> onSaved;
  final Map<String, String> destinations;
  final ValueChanged<String>? onNavigate;

  @override
  State<WealthPhotoScreen> createState() => _WealthPhotoScreenState();
}

class _WealthPhotoScreenState extends State<WealthPhotoScreen> {
  WealthSnapshot? _photo;
  List<AccountRecord> _accounts = [];
  final _fields = <String, TextEditingController>{};
  final _focus = <String, FocusNode>{};
  final _initial = <String, String>{};
  bool _loading = true, _busy = false, _confirming = false, _allowPop = false;
  String? _error, _errorId;
  bool get _locked => _busy || _confirming;
  bool get _dirty =>
      _fields.entries.any((e) => e.value.text != _initial[e.key]);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    for (final focus in _focus.values) {
      focus.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final photo = await widget.controller.month(widget.month);
      if (!mounted) return;
      final values = {
        for (final value in photo.values) value.account.id: value,
      };
      _accounts =
          [...photo.values.map((value) => value.account), ...photo.pending]
            ..sort((a, b) {
              final name = a.name.compareTo(b.name);
              return name == 0 ? a.id.compareTo(b.id) : name;
            });
      for (final account in _accounts) {
        final amount = values[account.id]?.amountCents;
        final text = amount == null ? '' : wealthAmountText(amount);
        _initial[account.id] = text;
        _fields[account.id] = TextEditingController(text: text);
        _focus[account.id] = FocusNode();
      }
      setState(() {
        _photo = photo;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar la foto. ${_cause(e)}';
      });
    }
  }

  String _cause(Object e) => switch (e) {
    WealthFailure() => e.message,
    AccountFailure() => e.message,
    _ => 'El almacenamiento local no está disponible.',
  };

  Future<void> _leave(VoidCallback action) async {
    if (_locked) return;
    if (_dirty) {
      final previousFocus = FocusManager.instance.primaryFocus;
      setState(() => _confirming = true);
      final route = DialogRoute<bool>(
        context: context,
        builder: (context) => AlertDialog(
          insetPadding: const EdgeInsets.all(16),
          scrollable: true,
          title: Focus(
            autofocus: true,
            child: Semantics(
              header: true,
              child: const Text('Hay cambios sin guardar'),
            ),
          ),
          content: const Text(
            'Si sales, se descartará el borrador de esta foto.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Seguir editando'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Descartar cambios'),
            ),
          ],
        ),
      );
      final discard = await Navigator.of(context).push(route) ?? false;
      await route.completed;
      if (!mounted) return;
      setState(() => _confirming = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && previousFocus?.context != null) {
          previousFocus?.requestFocus();
        }
      });
      if (!discard) return;
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
  }

  Future<void> _save() async {
    if (_locked || _loading || _photo == null) return;
    final draft = <String, int?>{};
    for (final account in _accounts) {
      try {
        draft[account.id] = parseWealthAmount(_fields[account.id]!.text);
      } on WealthFailure catch (e) {
        setState(() {
          _error = e.message;
          _errorId = account.id;
        });
        final focus = _focus[account.id]!;
        focus.requestFocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && focus.context != null) {
            Scrollable.ensureVisible(focus.context!);
          }
        });
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
      _errorId = null;
    });
    try {
      final saved = await widget.controller.savePhoto(widget.month, draft);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _photo = saved;
        for (final entry in _fields.entries) {
          _initial[entry.key] = entry.value.text;
        }
        _allowPop = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onSaved(saved);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'No se guardó la foto. Inténtalo de nuevo. ${_cause(e)} '
            'El borrador se conserva.';
      });
    }
  }

  Widget _valueField(AccountRecord account) => Semantics(
    label: 'Valor manual de ${account.name} en euros',
    child: TextField(
      key: ValueKey('photo-value-${account.id}'),
      controller: _fields[account.id],
      focusNode: _focus[account.id],
      enabled: !_locked,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(() => _allowPop = false),
      decoration: InputDecoration(
        labelText: 'Valor (EUR)',
        helperText: _fields[account.id]!.text.trim().isEmpty
            ? 'Pendiente'
            : 'Valor manual · EUR',
        hintText: '0,00',
        errorText: _errorId == account.id ? _error : null,
        errorMaxLines: 4,
        helperMaxLines: 2,
      ),
    ),
  );

  String _classification(AccountRecord account) => account.liquidity == null
      ? 'Sin liquidez (deuda)'
      : liquidityLabel(account.liquidity!);

  Widget _entries(bool table) {
    if (!table) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final account in _accounts)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(account.name),
                    Text(accountKindLabel(account.kind)),
                    Text(_classification(account)),
                    _valueField(account),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    Widget cell(Widget child) =>
        Padding(padding: const EdgeInsets.all(8), child: child);
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(1.5),
        2: FlexColumnWidth(1.5),
        3: FlexColumnWidth(3),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            for (final heading in [
              'Ficha',
              'Tipo',
              'Liquidez del mes',
              'Valor manual',
            ])
              cell(Semantics(header: true, child: Text(heading))),
          ],
        ),
        for (final account in _accounts)
          TableRow(
            children: [
              cell(Text(account.name)),
              cell(Text(accountKindLabel(account.kind))),
              cell(Text(_classification(account))),
              cell(_valueField(account)),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(widget.month.value);
    return PopScope<Object?>(
      canPop: _allowPop || (!_dirty && !_locked),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave(widget.onReturn);
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _leave(widget.onReturn),
        },
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Text('Foto patrimonial'),
            actions: [
              if (widget.onNavigate != null)
                PopupMenuButton<String>(
                  enabled: !_locked,
                  tooltip: 'Cambiar destino',
                  icon: const Icon(Icons.menu),
                  onSelected: (path) => _leave(() => widget.onNavigate!(path)),
                  itemBuilder: (context) => [
                    for (final entry in widget.destinations.entries)
                      PopupMenuItem(value: entry.key, child: Text(entry.value)),
                  ],
                ),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: FocusTraversalGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextButton(
                            onPressed: _locked
                                ? null
                                : () => _leave(widget.onReturn),
                            child: const Text('Volver al origen'),
                          ),
                          Text(
                            'Valores del ${DateFormat("d 'de' MMMM 'de' y", 'es_ES').format(date)}',
                          ),
                          Text('Referencia fija: ${widget.month.value}'),
                          const Text(
                            'Vacío significa pendiente; 0,00 es un valor registrado. '
                            'Usa coma o punto y hasta dos decimales, sin separadores de miles. '
                            'Los valores son manuales e independientes de los movimientos.',
                          ),
                          const SizedBox(height: 16),
                          if (_loading)
                            const LinearProgressIndicator(
                              semanticsLabel: 'Cargando foto',
                            )
                          else if (_photo == null)
                            TextButton(
                              onPressed: _load,
                              child: const Text('Reintentar'),
                            )
                          else ...[
                            Text(switch (_photo!.status) {
                              WealthSnapshotStatus.absent =>
                                'Sin dato: falta foto patrimonial',
                              WealthSnapshotStatus.incomplete => 'Foto incompleta · Sin dato: foto patrimonial incompleta',
                              WealthSnapshotStatus.complete => 'Foto completa',
                            }),
                            for (final account in _photo!.pending)
                              Text(
                                'Pendiente en la foto guardada: ${account.name}',
                              ),
                            if (_accounts.isEmpty)
                              const Text('No hay fichas vigentes en este mes.'),
                            _entries(constraints.maxWidth >= 840),
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
                          if (_busy)
                            const LinearProgressIndicator(
                              semanticsLabel: 'Guardando foto',
                            ),
                          const SizedBox(height: 16),
                          if (_photo != null)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                TextButton(
                                  onPressed: _locked
                                      ? null
                                      : () => _leave(widget.onReturn),
                                  child: const Text('Cancelar'),
                                ),
                                FilledButton(
                                  onPressed: _locked || _accounts.isEmpty
                                      ? null
                                      : _save,
                                  child: Text(
                                    _busy ? 'Guardando…' : 'Guardar foto',
                                  ),
                                ),
                              ],
                            ),
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
}
