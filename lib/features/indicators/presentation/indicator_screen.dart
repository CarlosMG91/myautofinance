import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ui/autofinance_ui.dart';
import '../../wealth/wealth.dart' show Month;
import '../domain/indicator_definition.dart';
import '../domain/indicator_engine.dart';
import '../domain/indicator_inputs.dart';
import '../domain/indicator_result.dart';
import 'indicator_formatter.dart';
import 'indicator_source.dart';

/// Catálogo y resultados del motor, sin cálculos financieros desde texto.
class IndicatorScreen extends StatefulWidget {
  const IndicatorScreen({
    super.key,
    required this.load,
    required this.month,
    required this.shell,
    required this.onPosition,
    this.onPhoto,
    this.onBudget,
    this.onDetail,
    this.detail = false,
    this.initialOffset = 0,
    this.initialFocus,
  });

  final IndicatorLoader load;
  final Month month;
  final bool detail;
  final double initialOffset;
  final String? initialFocus;
  final Widget Function(
    Widget body,
    ScrollController scroll,
    Widget? detailAction,
  )
  shell;
  final void Function(double offset, String? focus) onPosition;
  final Future<void> Function()? onPhoto, onDetail;
  final Future<void> Function(int month)? onBudget;

  @override
  State<IndicatorScreen> createState() => _IndicatorScreenState();
}

class _IndicatorScreenState extends State<IndicatorScreen>
    with WidgetsBindingObserver {
  static const months = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];
  final _scroll = ScrollController();
  final _focuses = <String, FocusNode>{};
  final _heading = FocusNode();
  StreamSubscription<int>? _subscription;
  Stream<int>? _changes;
  List<IndicatorEvaluation>? _data;
  String? _error, _focusToken;
  bool _loading = true, _opening = false, _restoring = true;
  bool? _wasCurrent;
  int _request = 0;
  late double _offset;

  int get year => int.parse(widget.month.value.substring(0, 4));
  int get month => int.parse(widget.month.value.substring(5, 7));

  @override
  void initState() {
    super.initState();
    _offset = widget.initialOffset;
    _focusToken = widget.initialFocus;
    _scroll.addListener(_publish);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_read(restoreFocus: true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (_wasCurrent == true && !current) {
      // Ocultar una consulta la invalida: ni una respuesta tardía ni un retorno
      // desde Gestión pueden presentar como actual el snapshot anterior.
      _request++;
      _data = null;
      _loading = true;
    } else if (_wasCurrent == false && current && !_opening) {
      unawaited(_read(restoreFocus: true));
    }
    _wasCurrent = current;
  }

  @override
  void didUpdateWidget(IndicatorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month.value != widget.month.value) {
      _offset = 0;
      _focusToken = null;
      unawaited(_read());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _wasCurrent != false) {
      unawaited(_read());
    }
  }

  @override
  void dispose() {
    _request++;
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _scroll.dispose();
    _heading.dispose();
    for (final focus in _focuses.values) {
      focus.dispose();
    }
    super.dispose();
  }

  void _publish() {
    if (!mounted || _loading || _restoring || _wasCurrent == false) return;
    if (_scroll.hasClients) _offset = _scroll.offset;
    widget.onPosition(_offset, _focusToken);
  }

  Future<void> _read({bool restoreFocus = false}) async {
    final request = ++_request;
    final selected = widget.month;
    _restoring = true;
    setState(() {
      _loading = true;
      _data = null;
      _error = null;
    });
    try {
      // No retener motor/conexión: una restauración sustituye la base activa.
      final source = await widget.load();
      if (!mounted || request != _request) return;
      if (!identical(_changes, source.changes)) {
        await _subscription?.cancel();
        if (!mounted || request != _request) return;
        _changes = source.changes;
        _subscription = source.changes.listen((_) {
          if (_wasCurrent != false && !_opening) unawaited(_read());
        });
      }
      final results = <IndicatorEvaluation>[];
      for (final definition in source.engine.catalog.definitions) {
        results.add(await source.engine.evaluate(definition.id, selected));
        if (!mounted || request != _request) return;
      }
      setState(() => _data = List.unmodifiable(results));
    } catch (error) {
      if (!mounted || request != _request) return;
      final message = error is IndicatorReadFailure
          ? '${error.message}${error.cause == null ? '' : ' Causa: ${error.cause}'}'
          : 'No se pudieron consultar los indicadores. Causa: $error';
      setState(() => _error = message);
    } finally {
      if (mounted && request == _request) {
        setState(() => _loading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || request != _request) return;
          if (_scroll.hasClients) {
            _scroll.jumpTo(_offset.clamp(0, _scroll.position.maxScrollExtent));
          }
          if (restoreFocus && _wasCurrent != false && _focusToken != null) {
            final focus = _focuses[_focusToken];
            if (focus?.context != null) {
              focus!.requestFocus();
            } else {
              _heading.requestFocus();
            }
          }
          _restoring = false;
          _publish();
        });
      }
    }
  }

  Future<void> _open(Future<void> Function() action, String token) async {
    if (_opening || _loading) return;
    _focusToken = token;
    _publish();
    setState(() => _opening = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir el destino. Causa: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
        if (ModalRoute.of(context)?.isCurrent != false) {
          await _read(restoreFocus: true);
        }
      }
    }
  }

  Widget _action(String token, String label, Future<void> Function()? action) =>
      OutlinedButton(
        key: ValueKey('indicator-$token'),
        focusNode: _focuses.putIfAbsent(token, () => FocusNode()),
        onFocusChange: (focused) {
          if (focused) {
            _focusToken = token;
            _publish();
          }
        },
        onPressed: action == null || _opening
            ? null
            : () => _open(action, token),
        child: Text(label),
      );

  String _money(BigInt cents, {BigInt? divisor, bool signed = true}) {
    final formatted = formatCalculatedIndicator(
      CalculatedIndicator(
        value: IndicatorValue(
          cents,
          BigInt.from(100) * (divisor ?? BigInt.one),
        ),
        precision: 2,
        unit: '€',
      ),
    );
    return signed && cents > BigInt.zero ? '+$formatted' : formatted;
  }

  Widget _inputs(IndicatorEvaluation evaluation) {
    final inputs = evaluation.inputs;
    final income = inputs.annualIncome;
    final liquid = inputs.wealth?.liquidAssetsCents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        AfValueRow(
          label: 'Activos líquidos · foto día 1',
          value: AfNumericText(
            liquid == null
                ? 'Sin dato'
                : _money(BigInt.from(liquid), signed: false),
          ),
        ),
        AfValueRow(
          label: 'Ingresos presupuestados · $year',
          value: AfNumericText(
            income?.isComplete == true
                ? _money(income!.totalCents)
                : 'Sin dato · año incompleto',
          ),
        ),
        AfValueRow(
          label: 'Promedio mensual · anual / 12',
          value: AfNumericText(
            income?.isComplete == true
                ? _money(income!.totalCents, divisor: BigInt.from(12))
                : 'Sin dato',
          ),
        ),
        const Text(
          'Activos líquidos / (ingresos anuales presupuestados / 12).',
        ),
        const Text(
          'El promedio se muestra con dos decimales; el cálculo no lo redondea '
          'antes de dividir. No se restan deudas ni se usan movimientos reales.',
        ),
      ],
    );
  }

  Widget _missing(UnavailableIndicator result) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 12,
    children: [
      Text(result.text),
      Text('Código: ${result.code}'),
      if (result.detail.pendingAccounts.isNotEmpty) ...[
        Text('Fichas pendientes · ${months[month - 1]} de $year'),
        for (final account in result.detail.pendingAccounts)
          Text('• ${account.name}'),
      ],
      if (result.detail.pendingMonths.isNotEmpty) ...[
        Text('Meses pendientes · $year'),
        const Text(
          'Abre cada mes para registrar una partida de ingreso; un cero explícito cuenta.',
        ),
        for (final pending in result.detail.pendingMonths)
          _action(
            'budget-$pending',
            'Completar ${months[pending - 1]} $year',
            widget.onBudget == null ? null : () => widget.onBudget!(pending),
          ),
      ],
      if (result.code == 'foto_ausente' || result.code == 'foto_incompleta')
        _action(
          'photo',
          result.code == 'foto_ausente'
              ? 'Registrar foto del mes'
              : 'Corregir foto del mes',
          widget.onPhoto,
        ),
      if (result.code == 'ingresos_nulos')
        const Text(
          'El total anual es cero, aunque los doce meses tienen una partida explícita. No se puede dividir por cero.',
        ),
      if (result.code == 'ingresos_negativos')
        const Text(
          'El total anual firmado es negativo. El denominador debe ser positivo para calcular el indicador.',
        ),
      if (result.code == 'ingresos_nulos' ||
          result.code == 'ingresos_negativos')
        _action(
          'budget-review',
          'Revisar presupuesto de $year',
          widget.onBudget == null ? null : () => widget.onBudget!(month),
        ),
    ],
  );

  Widget _card(IndicatorEvaluation evaluation) {
    final definition = evaluation.definition, result = evaluation.result;
    final cushion = definition.id == 'colchon_emergencia';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 24,
      children: [
        AfCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 20,
            children: [
              Text('Definición v${definition.version}'),
              Focus(
                focusNode: identical(evaluation, _data?.first)
                    ? _heading
                    : null,
                child: Semantics(
                  header: true,
                  child: Text(
                    definition.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              Semantics(
                liveRegion: true,
                child: Text.rich(
                  TextSpan(
                    text: result is CalculatedIndicator
                        ? formatCalculatedIndicator(result, includeUnit: false)
                        : 'Sin dato',
                    children: [
                      if (result is CalculatedIndicator)
                        TextSpan(
                          text: ' ${result.unit}',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                  key: ValueKey('indicator-value-${definition.id}'),
                  style: MediaQuery.textScalerOf(context).scale(16) >= 24
                      ? Theme.of(context).textTheme.titleLarge
                      : Theme.of(context).textTheme.displaySmall,
                ),
              ),
              if (result is UnavailableIndicator) _missing(result),
              if (cushion &&
                  result is CalculatedIndicator &&
                  result.value.numerator == BigInt.zero)
                const Text(
                  'Cero calculable: la foto está completa y los ingresos anuales son positivos.',
                ),
              if (cushion) _inputs(evaluation),
              if (!cushion)
                for (final input in definition.requiredInputs)
                  Text(switch (input) {
                    IndicatorInput.monthlyWealth =>
                      'Foto patrimonial del mes seleccionado',
                    IndicatorInput.annualIncomeBudget =>
                      'Presupuesto anual de ingresos de $year',
                  }),
            ],
          ),
        ),
        if (widget.detail)
          AfCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 16,
              children: [
                Text(
                  'Entradas y ausencias',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (cushion) ...[
                  const Text(
                    'Ingresos: suma firmada de partidas bajo raíces marcadas como ingreso. Se requiere al menos una partida explícita en cada uno de los doce meses, incluido cero.',
                  ),
                  const Text(
                    'La foto debe estar completa para todas las fichas vigentes, incluso las no líquidas y las de deuda. No se arrastran fotos de otros meses.',
                  ),
                ],
                const Text('Precedencia de motivos'),
                for (final reason in definition.reasons) ...[
                  Text(reason.code),
                  Text(reason.text),
                ],
                if (definition.requiredInputs.contains(
                  IndicatorInput.monthlyWealth,
                ))
                  _action('detail-photo', 'Abrir foto del mes', widget.onPhoto),
                if (definition.requiredInputs.contains(
                  IndicatorInput.annualIncomeBudget,
                ))
                  _action(
                    'detail-budget',
                    'Revisar presupuesto',
                    widget.onBudget == null
                        ? null
                        : () => widget.onBudget!(month),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => widget.shell(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 24,
      children: [
        if (_loading)
          const AfStatus(
            kind: AfStatusKind.loading,
            message: 'Consultando el catálogo y las entradas del periodo seleccionado…',
          )
        else if (_error != null)
          AfStatus(
            kind: AfStatusKind.error,
            message: _error!,
            action: AfAction(
              label: 'Reintentar',
              onPressed: () => _read(restoreFocus: true),
            ),
          ),
        if (!_loading && _error == null) ...[
          for (final evaluation in _data ?? <IndicatorEvaluation>[])
            _card(evaluation),
        ],
      ],
    ),
    _scroll,
    !_loading && _error == null && !widget.detail
        ? _action('detail', 'Ver detalle', widget.onDetail)
        : null,
  );
}
