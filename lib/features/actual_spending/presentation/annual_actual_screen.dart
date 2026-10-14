import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/autofinance_ui.dart';
import '../../movements/movements.dart' show MovementCategoryScope;
import '../domain/annual_actual_query.dart';
import '../domain/annual_actual_detail.dart';

typedef AnnualActualLoader = Future<AnnualActualQuery> Function();

/// Presentación de la consulta EP-022. App aporta periodo, shell y enlaces.
class AnnualActualScreen extends StatefulWidget {
  const AnnualActualScreen({
    super.key,
    required this.load,
    required this.year,
    required this.focusedMonth,
    required this.shell,
    required this.open,
    required this.addMovement,
    required this.onPosition,
    this.onDetail,
    this.detail = false,
    this.initialExpanded = const {},
    this.initialExpandedMonths = const {},
    this.initialOffset = 0,
    this.initialFocus,
  });

  final AnnualActualLoader load;
  final int year, focusedMonth;
  final bool detail;
  final Widget Function(
    Widget body,
    ScrollController scroll,
    Future<void> Function() refresh,
  )
  shell;
  final Future<void> Function(AnnualActualDetail detail) open;
  final Future<void> Function() addMovement;
  final Future<void> Function()? onDetail;
  final void Function(
    Set<String> expanded,
    Set<String> months,
    double offset,
    String? focus,
  )
  onPosition;
  final Set<String> initialExpanded, initialExpandedMonths;
  final double initialOffset;
  final String? initialFocus;

  @override
  State<AnnualActualScreen> createState() => _AnnualActualScreenState();
}

class _AnnualActualScreenState extends State<AnnualActualScreen> {
  static const months = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];
  final _scroll = ScrollController();
  final _horizontal = ScrollController(), _vertical = ScrollController();
  final _matrixFocus = FocusNode();
  final _focuses = <String, FocusNode>{};
  late final _expanded = {...widget.initialExpanded};
  late final _expandedMonths = {...widget.initialExpandedMonths};
  StreamSubscription<int>? _subscription;
  Object? _invalidation;
  AnnualActual? _data;
  String? _error, _focusToken;
  bool _loading = true, _opening = false, _initial = true;
  bool _restoringPosition = true;
  int _request = 0;
  double _outerOffset = 0, _horizontalOffset = 0, _verticalOffset = 0;

  @override
  void initState() {
    super.initState();
    _outerOffset = widget.initialOffset;
    _focusToken = widget.initialFocus;
    final position = RegExp(r'^(.*)\|matrix=([0-9.]+),([0-9.]+)$')
        .firstMatch(_focusToken ?? '');
    if (position != null) {
      _focusToken = position[1];
      final x = double.tryParse(position[2]!);
      final y = double.tryParse(position[3]!);
      if (x != null && y != null && x.isFinite && y.isFinite) {
        _horizontalOffset = x;
        _verticalOffset = y;
      }
    }
    for (final controller in [_scroll, _horizontal, _vertical]) {
      controller.addListener(_publish);
    }
    _read();
  }

  @override
  void didUpdateWidget(AnnualActualScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.year != widget.year ||
        oldWidget.focusedMonth != widget.focusedMonth) {
      _focusToken = null;
      _outerOffset = _horizontalOffset = _verticalOffset = 0;
      _initial = false;
      FocusManager.instance.primaryFocus?.unfocus();
      if (oldWidget.year != widget.year) {
        unawaited(_read(resetPosition: true));
      } else {
        _restorePosition(_request);
      }
    }
  }

  @override
  void dispose() {
    _request++;
    _subscription?.cancel();
    for (final controller in [_scroll, _horizontal, _vertical]) {
      controller.dispose();
    }
    for (final focus in _focuses.values) {
      focus.dispose();
    }
    _matrixFocus.dispose();
    super.dispose();
  }

  void _capturePosition() {
    if (_scroll.hasClients) _outerOffset = _scroll.offset;
    if (_horizontal.hasClients) _horizontalOffset = _horizontal.offset;
    if (_vertical.hasClients) _verticalOffset = _vertical.offset;
  }

  void _publish() {
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent == false ||
        _loading ||
        _restoringPosition) {
      return;
    }
    _capturePosition();
    widget.onPosition(
      {..._expanded},
      {..._expandedMonths},
      _outerOffset,
      widget.detail
          ? '${_focusToken ?? 'matrix'}|matrix=${_horizontalOffset.toStringAsFixed(3)},${_verticalOffset.toStringAsFixed(3)}'
          : _focusToken,
    );
  }

  FocusNode _focus(String token) =>
      _focuses.putIfAbsent(token, () => FocusNode());

  void _restorePosition(int request, {bool focus = false}) {
    _restoringPosition = true;
    final offsets = [
      (_scroll, _outerOffset),
      (_horizontal, _horizontalOffset),
      (_vertical, _verticalOffset),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || request != _request) return;
      for (final (controller, offset) in offsets) {
        if (controller.hasClients) {
          controller.jumpTo(
            offset.clamp(0, controller.position.maxScrollExtent),
          );
        }
      }
      if (focus && ModalRoute.of(context)?.isCurrent != false) {
        final node = _focuses[_focusToken];
        if (node?.context != null) {
          node!.requestFocus();
        } else if (widget.detail && _matrixFocus.context != null) {
          _matrixFocus.requestFocus();
        }
      }
      _restoringPosition = false;
      _publish();
    });
  }

  Future<void> _read({
    bool resetPosition = false,
    bool restoreFocus = false,
  }) async {
    if (!_initial && !resetPosition) _capturePosition();
    final request = ++_request, year = widget.year;
    _restoringPosition = true;
    setState(() {
      _data = null;
      _error = null;
      _loading = true;
    });
    try {
      // Siempre resolver el loader: la restauración puede cambiar la conexión.
      final query = await widget.load();
      if (!mounted || request != _request) return;
      if (!identical(_invalidation, query.invalidation)) {
        await _subscription?.cancel();
        if (!mounted || request != _request) return;
        _invalidation = query.invalidation;
        _subscription = query.invalidation.changes.listen((_) => _read());
      }
      final data = await query.read(year);
      if (!mounted || request != _request || year != widget.year) return;
      setState(() => _data = data);
    } catch (error) {
      if (mounted && request == _request) {
        setState(
          () => _error = error is AnnualActualFailure
              ? error.message
              : 'No se pudo consultar el real anual. Inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted && request == _request) {
        setState(() => _loading = false);
        _restorePosition(request, focus: _initial || restoreFocus);
        _initial = false;
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir el destino. Inténtalo de nuevo.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
        await _read(restoreFocus: true);
      }
    }
  }

  String _id(AnnualActualRow row) => row.categoryId ?? 'sin-clasificar';
  String _label(AnnualActualRow? row) =>
      row == null ? 'Total general' : row.category?.path ?? 'Sin clasificar';
  bool _children(AnnualActualRow row) =>
      row.categoryId != null &&
      _data!.rows.any((r) => r.category!.node.parentId == row.categoryId);
  List<AnnualActualRow> get _visible {
    final byId = {for (final row in _data!.rows) row.categoryId: row};
    return [
      ..._data!.rows.where((row) {
        var parent = row.category!.node.parentId;
        while (parent != null) {
          if (!_expanded.contains(parent)) return false;
          parent = byId[parent]?.category!.node.parentId;
        }
        return true;
      }),
      _data!.unclassified,
    ];
  }

  void _expand(AnnualActualRow row) {
    setState(() {
      if (!_expanded.remove(_id(row))) _expanded.add(_id(row));
    });
    _publish();
  }

  Widget _toggle(
    String token,
    String label,
    bool expanded,
    VoidCallback action,
  ) => Semantics(
    expanded: expanded,
    child: TextButton(
      key: ValueKey('actual-$token'),
      focusNode: _focus(token),
      onFocusChange: (focused) {
        if (focused) {
          _focusToken = token;
          _publish();
        }
      },
      onPressed: _opening ? null : action,
      child: Text(label),
    ),
  );

  Widget _amount(
    AnnualActualTotal total,
    AnnualActualRow? row,
    int? month, {
    String prefix = '',
    bool direct = false,
  }) {
    final token =
        '$prefix${row == null ? 'all' : _id(row)}:${month ?? 'year'}${direct ? ':direct' : ''}';
    final period = month == null
        ? 'Año ${widget.year}'
        : '${months[month - 1]} ${widget.year}';
    final label =
        '${_label(row)}, $period${direct ? ', solo directos' : ', rama'}, '
        '${AfAmount(total.amountCents).format()}, ${total.movementCount} movimientos. Ver registros';
    return Semantics(
      label: label,
      child: Tooltip(
        message: label,
        child: TextButton(
          key: ValueKey('actual-$token'),
          focusNode: _focus(token),
          onFocusChange: (focused) {
            if (focused) {
              _focusToken = token;
              _publish();
            }
          },
          style: TextButton.styleFrom(alignment: Alignment.centerRight),
          onPressed: _opening
              ? null
              : () => _open(
                  () => widget.open(
                    AnnualActualDetail(
                      year: widget.year,
                      month: month,
                      categoryId: row?.categoryId,
                      unclassified: row != null && row.categoryId == null,
                      scope: direct
                          ? MovementCategoryScope.direct
                          : MovementCategoryScope.branch,
                    ),
                  ),
                  token,
                ),
          child: AfMoneyText(
            AfAmount(total.amountCents),
            hero: prefix == 'summary-',
          ),
        ),
      ),
    );
  }

  Widget _summary() {
    final roots = [
      ..._data!.rows.where((r) => r.category!.node.depth == 1),
      _data!.unclassified,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 24,
      children: [
        AfResponsiveGrid(
          children: [
            AfCard(
              tone: AfCardTone.real,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  const Text('Resultado real del año'),
                  _amount(_data!.annualTotal, null, null, prefix: 'summary-'),
                  Text(
                    '${widget.year} · ${_data!.annualTotal.movementCount} movimientos · Suma de doce meses',
                  ),
                ],
              ),
            ),
            AfCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  const Text('Mes enfocado'),
                  _amount(
                    _data!.months[widget.focusedMonth - 1],
                    null,
                    widget.focusedMonth,
                    prefix: 'summary-',
                  ),
                  Text(
                    '${months[widget.focusedMonth - 1]} ${widget.year} · Todas las cuentas',
                  ),
                ],
              ),
            ),
          ],
        ),
        AfPageHeader(
          title: 'Real de enero a diciembre',
          actions: [
            OutlinedButton(
              key: const Key('actual-show-detail'),
              focusNode: _focus('detail'),
              onPressed: _opening || widget.onDetail == null
                  ? null
                  : () => _open(widget.onDetail!, 'detail'),
              child: const Text('Ver detalle'),
            ),
          ],
        ),
        AfTimeChart(
          title: 'Evolución mensual del real',
          period: 'Año ${widget.year}',
          series: [
            AfTimeSeries(
              label: 'Real · Todas las cuentas',
              role: AfSeriesRole.real,
              points: [
                for (var m = 1; m <= 12; m++)
                  AfTimePoint(
                    periodIndex: widget.year * 12 + m - 1,
                    label: months[m - 1],
                    focusNode: _focus('series-$m'),
                    value: AfChartValue.euros(_data!.months[m - 1].amountCents),
                    onPressed: _opening
                        ? null
                        : () => _open(
                            () => widget.open(
                              AnnualActualDetail(year: widget.year, month: m),
                            ),
                            'series-$m',
                          ),
                  ),
              ],
            ),
          ],
        ),
        AfBarChart(
          title: 'Real anual por categoría',
          period: 'Año ${widget.year}',
          data: [
            for (final row in roots)
              AfBarDatum(
                label: _label(row),
                value: AfChartValue.euros(row.annualTotal.amountCents),
                focusNode: _focus('summary-${_id(row)}:year'),
                role: AfSeriesRole.real,
                onPressed: _opening
                    ? null
                    : () => _open(
                        () => widget.open(
                          AnnualActualDetail(
                            year: widget.year,
                            categoryId: row.categoryId,
                            unclassified: row.categoryId == null,
                          ),
                        ),
                        'summary-${_id(row)}:year',
                      ),
              ),
          ],
        ),
      ],
    );
  }

  void _moveHorizontal(double delta) {
    if (_horizontal.hasClients) {
      _horizontal.jumpTo(
        (_horizontal.offset + delta).clamp(
          0,
          _horizontal.position.maxScrollExtent,
        ),
      );
    }
  }

  Widget _matrix() => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
          _moveHorizontal(160),
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
          _moveHorizontal(-160),
    },
    child: Focus(
      key: const Key('actual-matrix-region'),
      focusNode: _matrixFocus,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          const Text(
            'Enfoca la matriz y usa las flechas izquierda/derecha o la barra horizontal. Cabecera y categoría permanecen visibles.',
          ),
          AfDetailTable(
            key: const Key('actual-matrix'),
            caption: 'Real anual ${widget.year} · Todas las cuentas',
            horizontalController: _horizontal,
            verticalController: _vertical,
            labelWidth: 240,
            cellWidth: 170,
            columns: [
              for (var m = 1; m <= 12; m++)
                '${months[m - 1]}${m == widget.focusedMonth ? ' · Enfocado' : ''}',
              'Total anual',
            ],
            rows: [
              for (final row in _visible)
                AfDetailRow(
                  label:
                      '${_label(row)}${row.category?.node.archived == true ? ' · Archivada' : ''}',
                  depth: (row.category?.node.depth ?? 1) - 1,
                  expanded: _expanded.contains(_id(row)),
                  onExpand: _children(row) ? () => _expand(row) : null,
                  values: [
                    for (final cell in row.months)
                      _amount(cell.total, row, cell.month),
                    _amount(row.annualTotal, row, null),
                  ],
                ),
              AfDetailRow(
                label: 'Total general · raíces + Sin clasificar',
                total: true,
                values: [
                  for (var m = 1; m <= 12; m++)
                    _amount(_data!.months[m - 1], null, m),
                  _amount(_data!.annualTotal, null, null),
                ],
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _cards() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 16,
    children: [
      for (final row in _visible)
        AfCard(
          key: ValueKey('actual-card-${_id(row)}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(
                    '${_label(row)}${row.category?.node.archived == true ? ' · Archivada' : ''}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (row.category != null)
                    Text('Nivel ${row.category!.node.depth} de 3'),
                  if (_children(row))
                    _toggle(
                      'branch-${_id(row)}',
                      '${_expanded.contains(_id(row)) ? 'Contraer' : 'Expandir'} rama',
                      _expanded.contains(_id(row)),
                      () => _expand(row),
                    ),
                ],
              ),
              AfValueRow(
                label: 'Total anual',
                value: _amount(row.annualTotal, row, null),
              ),
              AfValueRow(
                label: '${months[widget.focusedMonth - 1]} · Enfocado',
                selected: true,
                value: _amount(
                  row.months[widget.focusedMonth - 1].total,
                  row,
                  widget.focusedMonth,
                  prefix: 'focused-',
                ),
              ),
              _toggle(
                'months-${_id(row)}',
                _expandedMonths.contains(_id(row))
                    ? 'Ocultar doce meses'
                    : 'Ver doce meses',
                _expandedMonths.contains(_id(row)),
                () {
                  setState(() {
                    if (!_expandedMonths.remove(_id(row))) {
                      _expandedMonths.add(_id(row));
                    }
                  });
                  _publish();
                },
              ),
              if (_expandedMonths.contains(_id(row)))
                for (final cell in row.months)
                  AfValueRow(
                    label:
                        '${months[cell.month - 1]}${cell.month == widget.focusedMonth ? ' · Enfocado' : ''}',
                    selected: cell.month == widget.focusedMonth,
                    value: _amount(cell.total, row, cell.month),
                  ),
            ],
          ),
        ),
      AfCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            const Text('Total general · raíces + Sin clasificar'),
            AfValueRow(
              label: 'Total anual',
              value: _amount(_data!.annualTotal, null, null),
            ),
            AfValueRow(
              label: '${months[widget.focusedMonth - 1]} · Enfocado',
              selected: true,
              value: _amount(
                _data!.months[widget.focusedMonth - 1],
                null,
                widget.focusedMonth,
                prefix: 'focused-',
              ),
            ),
            _toggle(
              'months-total-general',
              _expandedMonths.contains('total-general')
                  ? 'Ocultar doce meses'
                  : 'Ver doce meses',
              _expandedMonths.contains('total-general'),
              () {
                setState(() {
                  if (!_expandedMonths.remove('total-general')) {
                    _expandedMonths.add('total-general');
                  }
                });
                _publish();
              },
            ),
            if (_expandedMonths.contains('total-general'))
              for (var m = 1; m <= 12; m++)
                AfValueRow(
                  label:
                      '${months[m - 1]}${m == widget.focusedMonth ? ' · Enfocado' : ''}',
                  selected: m == widget.focusedMonth,
                  value: _amount(_data!.months[m - 1], null, m),
                ),
          ],
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => widget.shell(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 24,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              focusNode: _focus('add'),
              onPressed: _loading || _opening
                  ? null
                  : () => _open(widget.addMovement, 'add'),
              child: const Text('Añadir movimiento'),
            ),
            TextButton(
              onPressed: _opening ? null : _read,
              child: const Text('Actualizar año'),
            ),
          ],
        ),
        if (_loading)
          const AfStatus(
            kind: AfStatusKind.loading,
            message: 'Cargando real anual…',
          ),
        if (_error != null)
          AfStatus(
            kind: AfStatusKind.error,
            message: _error!,
            action: AfAction(label: 'Reintentar', onPressed: _read),
          ),
        if (_data != null) ...[
          if (!_data!.annualTotal.hasMovements)
            const AfStatus(
              kind: AfStatusKind.empty,
              message: 'Este año no tiene movimientos. Todos los meses y el total anual son cero.',
            ),
          if (!widget.detail)
            _summary()
          else ...[
            const Text(
              'Importes de solo lectura · Cada cifra abre sus registros de origen.',
            ),
            LayoutBuilder(
              builder: (context, constraints) =>
                  Theme.of(context).platform == TargetPlatform.android ||
                      MediaQuery.sizeOf(context).width < AfTokens.wideMin ||
                      constraints.maxWidth < 600 ||
                      MediaQuery.textScalerOf(context).scale(14) > 21
                  ? _cards()
                  : _matrix(),
            ),
          ],
        ],
      ],
    ),
    _scroll,
    _read,
  );
}
