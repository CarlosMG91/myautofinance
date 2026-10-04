import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/account_repository.dart';
import '../domain/wealth_management.dart';
import 'account_catalog_screen.dart';
import 'wealth_controller.dart';

/// Editor de una operación explícita; la ficha permanece en la ruta de origen.
class LiquidityFormScreen extends StatefulWidget {
  const LiquidityFormScreen({
    super.key,
    required this.details,
    required this.initialMonth,
    required this.loadManagement,
    required this.historical,
  });
  final AccountDetails details;
  final Month initialMonth;
  final WealthManagementLoader loadManagement;
  final bool historical;

  @override
  State<LiquidityFormScreen> createState() => _LiquidityFormScreenState();
}

class _LiquidityFormScreenState extends State<LiquidityFormScreen> {
  final _from = TextEditingController(), _until = TextEditingController();
  final _fromFocus = FocusNode(), _untilFocus = FocusNode();
  final _liquidityFocus = FocusNode();
  late Liquidity _liquidity, _initialLiquidity;
  late String _initialFrom;
  bool _busy = false, _confirming = false, _allowPop = false;
  String? _error, _errorField;
  bool get _locked => _busy || _confirming;
  bool get _dirty =>
      _from.text != _initialFrom ||
      _until.text.isNotEmpty ||
      _liquidity != _initialLiquidity;

  @override
  void initState() {
    super.initState();
    final account = widget.details.account;
    var month = widget.initialMonth;
    if (month.compareTo(account.activeFrom) < 0) month = account.activeFrom;
    if (account.activeThrough != null &&
        month.compareTo(account.activeThrough!) > 0) {
      month = account.activeThrough!;
    }
    _initialFrom = month.value.substring(0, 7);
    _from.text = _initialFrom;
    _initialLiquidity = _period(month)!.liquidity;
    _liquidity = _initialLiquidity;
  }

  @override
  void dispose() {
    _from.dispose();
    _until.dispose();
    _fromFocus.dispose();
    _untilFocus.dispose();
    _liquidityFocus.dispose();
    super.dispose();
  }

  LiquidityPeriod? _period(Month month) {
    for (final period in widget.details.history) {
      if (period.from.compareTo(month) <= 0 &&
          (period.until == null || month.compareTo(period.until!) < 0)) {
        return period;
      }
    }
    return null;
  }

  Month? _parse(String text) {
    if (!RegExp(r'^[0-9]{4}-[0-9]{2}$').hasMatch(text)) return null;
    try {
      return Month.parse('$text-01');
    } on AccountFailure {
      return null;
    }
  }

  String _range(Month from, Month? until) =>
      'Desde ${from.value.substring(0, 7)} (incluido) '
      '${until == null ? 'hasta el fin de vigencia' : 'hasta ${until.value.substring(0, 7)} (excluido)'}. '
      'Clasificación: ${liquidityLabel(_liquidity)}.';

  void _invalid(String field, String message, FocusNode focus) {
    setState(() {
      _errorField = field;
      _error = message;
    });
    focus.requestFocus();
  }

  Future<bool> _ask(String title, String message, String action) async {
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
            child: const Text('Cancelar'),
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
          'El borrador de liquidez se descartará al volver.',
          'Descartar cambios',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _save() async {
    if (_locked) return;
    final from = _parse(_from.text);
    if (from == null) {
      _invalid(
        'from',
        'Introduce un mes válido con formato AAAA-MM.',
        _fromFocus,
      );
      return;
    }
    final account = widget.details.account;
    final period = _period(from);
    if (period == null) {
      _invalid(
        'from',
        'El mes debe estar dentro de la vigencia del activo.',
        _fromFocus,
      );
      return;
    }
    final until = widget.historical && _until.text.isNotEmpty
        ? _parse(_until.text)
        : null;
    if (widget.historical && _until.text.isNotEmpty && until == null) {
      _invalid(
        'until',
        'Introduce un mes válido con formato AAAA-MM.',
        _untilFocus,
      );
      return;
    }
    if (until != null &&
        (until.compareTo(from) <= 0 ||
            (account.activeThrough?.next != null &&
                until.compareTo(account.activeThrough!.next!) > 0))) {
      _invalid(
        'until',
        'El fin debe ser posterior al inicio y no superar el mes siguiente a la baja.',
        _untilFocus,
      );
      return;
    }
    final effectiveUntil = widget.historical
        ? until ?? account.activeThrough?.next
        : period.until;
    if (!await _ask(
      widget.historical
          ? 'Confirmar corrección histórica'
          : 'Confirmar cambio de liquidez',
      '${account.name}. ${_range(from, effectiveUntil)} '
      '${widget.historical ? 'Se sustituirán las clasificaciones dentro de este intervalo; las exteriores se conservarán.' : 'Se conservarán los meses anteriores y los cambios posteriores existentes.'} '
      'Los valores manuales de las fotos se conservarán.',
      widget.historical ? 'Corregir intervalo' : 'Aplicar cambio',
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
      final saved = widget.historical
          ? await service.correctHistoricalLiquidity(
              account.id,
              from,
              until,
              _liquidity,
            )
          : await service.changeLiquidity(account.id, from, _liquidity);
      if (!mounted) return;
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, saved);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is AccountFailure ? e.message : 'No se pudo guardar. El borrador se conserva; inténtalo de nuevo.';
      });
      _fromFocus.requestFocus();
    }
  }

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
          automaticallyImplyLeading: false,
          title: Text(
            widget.historical
                ? 'Corregir liquidez histórica'
                : 'Cambiar liquidez',
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: FocusTraversalGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextButton(
                        onPressed: _locked ? null : _leave,
                        child: const Text('Volver a la ficha'),
                      ),
                      Text(widget.details.account.name),
                      Text(
                        widget.historical
                            ? 'Corrige solo el intervalo elegido. El fin es exclusivo; vacío alcanza el fin de vigencia y sustituye también los cambios posteriores dentro del intervalo.'
                            : 'Elige el mes de aplicación. El cambio termina en el siguiente periodo existente o al fin de vigencia.',
                      ),
                      const Text('Las fotos conservan sus valores manuales.'),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _from,
                        focusNode: _fromFocus,
                        autofocus: true,
                        enabled: !_locked,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Mes de aplicación',
                          helperText: 'AAAA-MM · inicio incluido',
                          errorText: _errorField == 'from' ? _error : null,
                        ),
                      ),
                      if (widget.historical)
                        TextField(
                          controller: _until,
                          focusNode: _untilFocus,
                          enabled: !_locked,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Mes de fin (excluido, opcional)',
                            helperText: 'AAAA-MM · vacío: fin de vigencia',
                            errorText: _errorField == 'until' ? _error : null,
                          ),
                        ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<Liquidity>(
                        initialValue: _liquidity,
                        focusNode: _liquidityFocus,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Liquidez',
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
                            : (value) => setState(() => _liquidity = value!),
                      ),
                      if (_error != null)
                        Semantics(liveRegion: true, child: Text(_error!)),
                      if (_busy)
                        const LinearProgressIndicator(
                          semanticsLabel: 'Guardando liquidez',
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
                            onPressed: _locked ? null : _save,
                            child: Text(
                              _busy ? 'Guardando…' : 'Guardar liquidez',
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
  );
}
