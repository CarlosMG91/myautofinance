import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../ui/autofinance_ui.dart';

import '../domain/account_repository.dart';
import '../domain/wealth_reading.dart';
import '../domain/wealth_repository.dart';
import 'account_catalog_screen.dart';
import 'wealth_controller.dart';

/// Consulta fotos manuales, sin calcular saldos desde movimientos.
class WealthScreen extends StatefulWidget {
  const WealthScreen({
    super.key,
    required this.controller,
    required this.initialMonth,
    required this.onPhoto,
    required this.onAccount,
    required this.onCatalog,
    required this.destinations,
    required this.onNavigate,
    required this.management,
    this.onReturn,
    this.periodControls,
    this.onPeriodChanged,
    this.onOrigin,
    this.shell,
    this.initialScrollOffset = 0,
    this.initialFocus,
  });
  final WealthController controller;
  final Month initialMonth;
  final Future<void> Function(Month month) onPhoto;
  final Future<void> Function(String id, Month month) onAccount;
  final Future<void> Function(Month month) onCatalog;
  final Map<String, String> destinations;
  final void Function(String path, Month month) onNavigate;
  final Widget Function(Month month, Future<void> Function() refresh)
  management;
  final VoidCallback? onReturn;
  final Widget Function(Month month, void Function(Month month) select)?
  periodControls;
  final void Function(Month month)? onPeriodChanged;
  final void Function(double offset, String? focus)? onOrigin;
  final double initialScrollOffset;
  final String? initialFocus;
  final Widget Function(
    Widget body,
    ScrollController scroll,
    Month month,
    void Function(Month) select,
    Future<void> Function() refresh,
  )?
  shell;
  @override
  State<WealthScreen> createState() => _WealthScreenState();
}

class _WealthScreenState extends State<WealthScreen> {
  late Month _month = widget.initialMonth;
  late final _yearInput = TextEditingController(
    text: _month.value.substring(0, 4),
  );
  late final Map<int, int> _remembered = {_year: _number};
  late Future<List<WealthReading>> _data = _readYear(_year);
  final _scroll = ScrollController();
  final _originNodes = <String, FocusNode>{};
  FocusNode _node(String token) =>
      _originNodes.putIfAbsent(token, () => FocusNode(debugLabel: token));
  String? _yearError;
  bool _changingPeriod = false;
  String? _originFocus;
  ({
    String month,
    Future<List<WealthReading>> data,
    double offset,
    String? focus,
  })?
  _restore;
  int get _year => int.parse(_month.value.substring(0, 4));
  int get _number => int.parse(_month.value.substring(5, 7));
  String _monthName(int number) =>
      DateFormat.MMMM('es_ES').format(DateTime(2026, number));
  String get _period => '${_monthName(_number)} $_year';

  Future<List<WealthReading>> _readYear(int year) {
    final data = widget.controller.readYear(year);
    // El fallo puede llegar antes del próximo frame, cuando FutureBuilder
    // todavía no se ha suscrito. Conserva el error para su presentación.
    data.ignore();
    return data;
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_publishOrigin);
    _restore = (
      month: _month.value,
      data: _data,
      offset: widget.initialScrollOffset,
      focus: widget.initialFocus,
    );
  }

  void _publishOrigin([String? focus]) {
    if (_changingPeriod || ModalRoute.of(context)?.isCurrent == false) return;
    _originFocus = focus ?? _originFocus;
    widget.onOrigin?.call(
      _scroll.hasClients ? _scroll.offset : 0,
      _originFocus,
    );
  }

  @override
  void dispose() {
    _yearInput.dispose();
    _scroll.dispose();
    for (final node in _originNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _refresh({double? restoreOffset, String? restoreFocus}) async {
    final month = _month.value;
    final offset = restoreOffset ?? (_scroll.hasClients ? _scroll.offset : 0.0);
    final data = widget.controller.readYear(_year);
    setState(() {
      _data = data;
      _restore = (
        month: month,
        data: data,
        offset: offset,
        focus: restoreFocus,
      );
    });
    // FutureBuilder presenta los fallos, también después de volver de un editor.
    try {
      await data;
    } catch (_) {}
  }

  void _restoreAfterRead() {
    final restore = _restore;
    if (restore == null) return;
    _restore = null;
    // FutureBuilder puede suscribirse a un Future ya resuelto en el siguiente
    // frame. Restaurar solo después de construir las filas, no en la carga.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          restore.month == _month.value &&
          identical(restore.data, _data) &&
          _scroll.hasClients) {
        final focus = _originNodes[restore.focus];
        if (focus?.context != null) focus?.requestFocus();
        _scroll.jumpTo(
          restore.offset.clamp(0, _scroll.position.maxScrollExtent),
        );
      }
    });
  }

  void _select(int year, int number, {bool publish = true}) {
    if (year != _year || number != _number) {
      _changingPeriod = true;
      _restore = null;
      _originFocus = null;
      if (_scroll.hasClients) _scroll.jumpTo(0);
      FocusManager.instance.primaryFocus?.unfocus();
      _changingPeriod = false;
    }
    setState(() {
      final changedYear = year != _year;
      _month = Month(year, number);
      _remembered[year] = number;
      _yearInput.text = year.toString().padLeft(4, '0');
      _yearError = null;
      if (changedYear) _data = _readYear(year);
    });
    if (publish) widget.onPeriodChanged?.call(_month);
  }

  void _applyYear() {
    final year = int.tryParse(_yearInput.text);
    if (year == null || year < 1 || year > 9999) {
      setState(() => _yearError = 'Introduce un año entre 1 y 9999.');
      return;
    }
    _select(year, _remembered[year] ?? 1);
  }

  Future<void> _open(String token, Future<void> Function() action) async {
    final month = _month.value;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    _publishOrigin(token);
    await action();
    if (!mounted) return;
    await _refresh(
      restoreOffset: month == _month.value ? offset : null,
      restoreFocus: month == _month.value ? token : null,
    );
  }

  String _status(WealthSnapshotStatus status) => switch (status) {
    WealthSnapshotStatus.absent => 'Sin dato: falta foto patrimonial',
    WealthSnapshotStatus.incomplete => 'Sin dato: foto patrimonial incompleta',
    WealthSnapshotStatus.complete => 'Foto completa',
  };
  String _money(int cents) {
    final digits = cents.toString().replaceFirst('-', '').padLeft(3, '0');
    final whole = digits
        .substring(0, digits.length - 2)
        .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
    return '${cents < 0 ? '−' : ''}$whole,${digits.substring(digits.length - 2)}\u00a0€';
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final desktop = width >= 840;
      final body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Foto del día 1 · ${_month.value.substring(8, 10)}/${_month.value.substring(5, 7)}/${_month.value.substring(0, 4)} · $_period',
          ),
          const Text(
            'Fotos manuales, independientes de los movimientos. Las deudas se restan de los activos.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                focusNode: _node('photo'),
                onPressed: () => _open('photo', () => widget.onPhoto(_month)),
                child: const Text('Registrar / editar foto'),
              ),
              TextButton(
                focusNode: _node('catalog'),
                onPressed: () =>
                    _open('catalog', () => widget.onCatalog(_month)),
                child: const Text('Gestionar fichas'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<WealthReading>>(
            future: _data,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Column(
                  children: [
                    Text('Cargando patrimonio…'),
                    LinearProgressIndicator(
                      semanticsLabel: 'Leyendo las doce fotos',
                    ),
                  ],
                );
              }
              _restoreAfterRead();
              if (snapshot.hasError) {
                final error = snapshot.error;
                final cause = switch (error) {
                  WealthFailure() => error.message,
                  AccountFailure() => error.message,
                  _ => 'El almacenamiento local no está disponible.',
                };
                return Semantics(
                  liveRegion: true,
                  child: Column(
                    children: [
                      Text('No se pudo cargar el patrimonio. $cause'),
                      TextButton(
                        onPressed: _refresh,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                );
              }
              final readings = snapshot.data!;
              final reading = readings[_number - 1];
              final totals = reading.totals;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(_status(reading.status)),
                  ),
                  if (reading.values.isEmpty && reading.pending.isEmpty)
                    const Text(
                      'No hay fichas vigentes en este mes. Crea una cuenta, cartera o deuda desde Gestionar fichas.',
                    ),
                  if (reading.pending.isNotEmpty)
                    Text(
                      'Pendientes: ${reading.pending.map((a) => a.name).join(', ')}',
                    ),
                  Card(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Patrimonio neto: ${totals == null ? 'Sin dato' : _money(totals.netWorthCents)}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Activos líquidos: ${totals == null ? 'Sin dato' : _money(totals.liquidAssetsCents)}',
                          ),
                          Text(
                            'Activos totales: ${totals == null ? 'Sin dato' : _money(totals.assetsCents)}',
                          ),
                          Text(
                            'Deudas: ${totals == null ? 'Sin dato' : _money(totals.debtsCents)}',
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (final group in [
                    Liquidity.liquid,
                    Liquidity.medium,
                    Liquidity.illiquid,
                    null,
                  ])
                    _group(reading, group, desktop),
                  ExpansionTile(
                    key: const PageStorageKey('wealth-twelve-months'),
                    title: Text('Las doce fotos de $_year · sin suma anual'),
                    children: [
                      for (var i = 0; i < readings.length; i++)
                        TextButton(
                          onPressed: () => _select(_year, i + 1),
                          child: Text(
                            '${_monthName(i + 1)}: ${_status(readings[i].status)}${readings[i].totals == null ? '' : ' · Neto ${_money(readings[i].totals!.netWorthCents)}'}',
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
          if (widget.onReturn != null)
            TextButton(
              onPressed: widget.onReturn,
              child: const Text('Volver al origen'),
            ),
        ],
      );
      void select(Month month) => _select(
        int.parse(month.value.substring(0, 4)),
        int.parse(month.value.substring(5, 7)),
        publish: false,
      );
      if (widget.shell != null) {
        return widget.shell!(body, _scroll, _month, select, _refresh);
      }
      return AfShell(
        primaryItems: [
          for (final entry in widget.destinations.entries)
            AfNavItem(id: entry.key, label: entry.value, icon: AfIcons.account),
        ],
        utilityItems: const [],
        selectedId: '/patrimonio',
        onSelect: (path) async {
          widget.onNavigate(path, _month);
          return true;
        },
        scrollController: _scroll,
        periodControl:
            widget.periodControls?.call(_month, select) ??
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _yearInput,
                    keyboardType: TextInputType.number,
                    onSubmitted: (_) => _applyYear(),
                    decoration: InputDecoration(
                      labelText: 'Año',
                      errorText: _yearError,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _applyYear,
                  child: const Text('Aplicar año'),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey(_month.value),
                    initialValue: _number,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Mes'),
                    items: [
                      for (var i = 1; i <= 12; i++)
                        DropdownMenuItem(value: i, child: Text(_monthName(i))),
                    ],
                    onChanged: (number) {
                      if (number != null) {
                        _select(_year, number);
                      }
                    },
                  ),
                ),
              ],
            ),
        page: AfPageSlots(
          title: 'Patrimonio',
          actions: [widget.management(_month, _refresh)],
          body: body,
        ),
      );
    },
  );

  Widget _group(WealthReading reading, Liquidity? liquidity, bool desktop) {
    bool matches(AccountRecord account) => liquidity == null
        ? account.kind == AccountKind.debt
        : account.kind != AccountKind.debt && account.liquidity == liquidity;
    final accounts = [
      ...reading.values.map((v) => v.account),
      ...reading.pending,
    ].where(matches).toList()..sort((a, b) => a.name.compareTo(b.name));
    if (accounts.isEmpty) return const SizedBox.shrink();
    final amounts = {
      for (final value in reading.values) value.account.id: value.amountCents,
    };
    final title = liquidity == null
        ? 'Deudas'
        : 'Cuentas y carteras · ${liquidityLabel(liquidity)}';
    String value(AccountRecord account) => amounts[account.id] == null
        ? 'Pendiente'
        : _money(amounts[account.id]!);
    Widget name(AccountRecord account) => TextButton(
      focusNode: _node('account:${account.id}'),
      style: TextButton.styleFrom(alignment: Alignment.centerLeft),
      onPressed: () => _open(
        'account:${account.id}',
        () => widget.onAccount(account.id, _month),
      ),
      child: Text(account.name, style: TextStyle(fontSize: desktop ? 14 : 16)),
    );
    Widget amount(AccountRecord account) => TextButton(
      focusNode: _node('value:${account.id}'),
      style: TextButton.styleFrom(
        alignment: desktop ? Alignment.centerRight : Alignment.centerLeft,
      ),
      onPressed: () =>
          _open('value:${account.id}', () => widget.onPhoto(_month)),
      child: Semantics(
        label:
            'Valor manual de ${account.name}, $_period: ${value(account)}. Editar foto',
        child: Text(
          value(account),
          style: TextStyle(fontSize: desktop ? 14 : 16),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          if (desktop)
            Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(3),
              },
              children: [
                const TableRow(
                  children: [
                    Padding(
                      padding: EdgeInsets.all(10),
                      child: Text('Ficha', style: TextStyle(fontSize: 14)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(10),
                      child: Text('Tipo', style: TextStyle(fontSize: 14)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(10),
                      child: Text(
                        'Valor de foto · día 1',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
                for (final account in accounts)
                  TableRow(
                    children: [
                      name(account),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          accountKindLabel(account.kind),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      amount(account),
                    ],
                  ),
              ],
            )
          else
            for (final account in accounts)
              Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      name(account),
                      Text(accountKindLabel(account.kind)),
                      const Text('Valor de foto · día 1'),
                      amount(account),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
