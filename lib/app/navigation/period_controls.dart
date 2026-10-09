import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'navigation_context.dart';
import 'navigation_period.dart';
import 'navigation_session.dart';

/// Un solo selector para las rutas principales. El consumidor autoriza el
/// cambio antes de publicar la sesión (por ejemplo, descartando un borrador).
class PeriodControls extends StatefulWidget {
  const PeriodControls({super.key, required this.session, this.beforeChange});

  final NavigationSession session;
  final Future<bool> Function(NavigationPeriod period)? beforeChange;

  @override
  State<PeriodControls> createState() => _PeriodControlsState();
}

class _PeriodControlsState extends State<PeriodControls> {
  final _year = TextEditingController();
  int? _month;
  NavigationPeriod? _shown;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _year.dispose();
    super.dispose();
  }

  Future<void> _select(NavigationPeriod period) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (period != widget.session.period) {
        await widget.session.selectPeriod(
          period,
          guard: () async =>
              widget.beforeChange == null || await widget.beforeChange!(period),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _shown = null;
        });
      }
    }
  }

  Future<void> _apply() async {
    final year = int.tryParse(_year.text.trim());
    if (year == null || year < 1 || year > 9999) {
      setState(() => _error = 'Introduce un año entre 1 y 9999.');
      return;
    }
    final value = widget.session.periodForYear(
      year,
      widget.session.context.view,
    );
    await _select(value);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final session = widget.session;
      final period = session.period;
      final annual = session.context.view == PeriodView.annual;
      if (_shown != period) {
        _shown = period;
        _year.text = period.year.toString().padLeft(4, '0');
        _month = period.month;
        _error = null;
      }
      final previous = annual
          ? (period.year == 1
                ? null
                : session.periodForYear(period.year - 1, PeriodView.annual))
          : period.previous;
      final next = annual
          ? (period.year == 9999
                ? null
                : session.periodForYear(period.year + 1, PeriodView.annual))
          : period.next;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 160,
                child: TextField(
                  key: const Key('period-year'),
                  controller: _year,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Año',
                    errorText: _error,
                    errorMaxLines: 3,
                  ),
                  onSubmitted: (_) => _apply(),
                ),
              ),
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<int>(
                  key: ValueKey('period-month-$_shown-$_month'),
                  initialValue: _month,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: annual ? 'Mes enfocado' : 'Mes',
                  ),
                  items: [
                    for (var m = 1; m <= 12; m++)
                      DropdownMenuItem(
                        value: m,
                        child: Text(
                          DateFormat.MMMM('es_ES').format(DateTime(2026, m)),
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (month) {
                          if (month == null) return;
                          setState(() => _month = month);
                          _select(NavigationPeriod(period.year, month));
                        },
                ),
              ),
              FilledButton(
                onPressed: _busy ? null : _apply,
                child: const Text('Ir al periodo'),
              ),
              TextButton(
                onPressed: _busy || previous == null
                    ? null
                    : () => _select(previous),
                child: Text(annual ? 'Año anterior' : 'Mes anterior'),
              ),
              TextButton(
                onPressed: _busy || next == null ? null : () => _select(next),
                child: Text(annual ? 'Año siguiente' : 'Mes siguiente'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _select(session.currentPeriod()),
                child: const Text('Mes actual'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              annual
                  ? 'Año de consulta: ${period.year.toString().padLeft(4, '0')} · Mes enfocado: $period'
                  : 'Periodo de consulta: $period',
            ),
          ),
        ],
      );
    },
  );
}
