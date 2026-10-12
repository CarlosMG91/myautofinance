import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';
import 'values.dart';
import 'components.dart';

enum AfSeriesRole { real, budget, asset, debt }

Color _color(AfSeriesRole role) => switch (role) {
  AfSeriesRole.real => AfTokens.seriesReal,
  AfSeriesRole.budget => AfTokens.seriesBudget,
  AfSeriesRole.asset => AfTokens.seriesAsset,
  AfSeriesRole.debt => AfTokens.seriesDebt,
};

class AfBarDatum {
  const AfBarDatum({
    required this.label,
    required this.value,
    required this.role,
    this.onPressed,
  });
  final String label;
  final AfChartValue value;
  final AfSeriesRole role;
  final VoidCallback? onPressed;
}

class AfTimePoint {
  const AfTimePoint({
    required this.periodIndex,
    required this.label,
    required this.value,
    this.onPressed,
  });

  /// Índice mensual absoluto (p. ej. year * 12 + month - 1), nunca posición visual.
  final int periodIndex;
  final String label;
  final AfChartValue value;
  final VoidCallback? onPressed;
}

class AfTimeSeries {
  const AfTimeSeries({
    required this.label,
    required this.role,
    required this.points,
  });
  final String label;
  final AfSeriesRole role;
  final List<AfTimePoint> points;
}

/// Solo geometría: normaliza antes de restar para evitar overflow con doubles
/// finitos extremos. No transforma signos ni rellena muestras ausentes.
class AfChartScale {
  AfChartScale(Iterable<double?> values) {
    final present = values.whereType<double>().toList();
    if (present.any((value) => !value.isFinite)) {
      throw ArgumentError('Escala no finita');
    }
    divisor = present.fold<double>(
      1,
      (scale, value) => math.max(scale, value.abs()),
    );
    minimum = present.fold<double>(
      0,
      (low, value) => math.min(low, value / divisor),
    );
    maximum = present.fold<double>(
      0,
      (high, value) => math.max(high, value / divisor),
    );
    if (minimum == maximum) {
      minimum = -1;
      maximum = 1;
    }
  }
  late final double divisor;
  late double minimum;
  late double maximum;
  double position(double value) =>
      ((value / divisor - minimum) / (maximum - minimum)).clamp(0, 1);
}

void _checkUnit(Iterable<AfChartValue> values) {
  if (values.map((value) => value.unit).toSet().length > 1) {
    throw ArgumentError('No mezclar EUR y meses en un eje');
  }
}

class AfBarChart extends StatelessWidget {
  const AfBarChart({
    super.key,
    required this.title,
    required this.period,
    required this.data,
  });
  final String title;
  final String period;
  final List<AfBarDatum> data;
  @override
  Widget build(BuildContext context) {
    _checkUnit(data.map((datum) => datum.value));
    final unit = data.isEmpty ? AfChartUnit.eur : data.first.value.unit;
    final scale = AfChartScale(data.map((datum) => datum.value.plotValue));
    return _ChartFrame(
      title: title,
      period: period,
      unit: unit,
      roles: data.map((datum) => datum.role).toSet(),
      values: data.map((datum) => datum.value).toList(),
      plot: SizedBox(
        height: math.max(96, data.length * 40.0),
        child: CustomPaint(painter: _BarsPainter(data, scale)),
      ),
      children: [
        if (data.isEmpty)
          const AfStatus(
            kind: AfStatusKind.empty,
            message: 'No hay series para este periodo.',
          ),
        for (final datum in data)
          AfValueRow(
            label: datum.label,
            value: AfNumericText(datum.value.formatted),
            onPressed: datum.onPressed,
          ),
      ],
    );
  }
}

class AfTimeChart extends StatelessWidget {
  const AfTimeChart({
    super.key,
    required this.title,
    required this.period,
    required this.series,
  });
  final String title;
  final String period;
  final List<AfTimeSeries> series;
  @override
  Widget build(BuildContext context) {
    final points = series.expand((item) => item.points).toList();
    _checkUnit(points.map((point) => point.value));
    for (final item in series) {
      for (var i = 1; i < item.points.length; i++) {
        if (item.points[i].periodIndex <= item.points[i - 1].periodIndex) {
          throw ArgumentError(
            'Los periodos deben ser únicos y estar ordenados',
          );
        }
      }
    }
    final scale = AfChartScale(points.map((point) => point.value.plotValue));
    return _ChartFrame(
      title: title,
      period: period,
      unit: points.isEmpty ? AfChartUnit.eur : points.first.value.unit,
      roles: series.map((item) => item.role).toSet(),
      values: points.map((point) => point.value).toList(),
      plot: SizedBox(
        height: 180,
        child: CustomPaint(painter: _TimePainter(series, scale)),
      ),
      children: [
        const Text(
          'Meses en orden temporal. Los huecos no se unen.',
          style: TextStyle(fontSize: 14),
        ),
        if (points.isEmpty)
          const AfStatus(
            kind: AfStatusKind.empty,
            message: 'No hay muestras para este periodo.',
          ),
        for (final item in series) ...[
          Semantics(
            header: true,
            child: Text(
              item.label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final point in item.points)
            AfValueRow(
              label: point.label,
              contextLabel: item.label,
              value: AfNumericText(point.value.formatted),
              onPressed: point.onPressed,
            ),
        ],
      ],
    );
  }
}

class AfAssetDatum {
  const AfAssetDatum({
    required this.id,
    required this.label,
    required this.cents,
    this.onPressed,
  });
  final String id;
  final String label;
  final int cents;
  final VoidCallback? onPressed;
}

enum AfDistributionState { complete, missing, invalid }

class AfDistributionChart extends StatelessWidget {
  const AfDistributionChart({
    super.key,
    required this.title,
    required this.period,
    required this.state,
    required this.assets,
    required this.totalAssets,
    required this.debt,
    this.reason,
  });
  final String title;
  final String period;
  final AfDistributionState state;
  final List<AfAssetDatum> assets;

  /// Totales calculados por dominio, nunca calculados para mostrarlos por el kit.
  final AfAmount totalAssets;
  final AfAmount debt;
  final String? reason;
  @override
  Widget build(BuildContext context) {
    if (state != AfDistributionState.complete) {
      return AfStatus(
        kind: state == AfDistributionState.missing
            ? AfStatusKind.missing
            : AfStatusKind.error,
        message: '$title · $period. ${reason ?? 'Revisa la foto de origen.'}',
      );
    }
    final total = totalAssets.cents;
    // Validación estructural de geometría; no publica un subtotal alternativo.
    final valid =
        total != null &&
        total >= 0 &&
        debt.cents != null &&
        debt.cents! >= 0 &&
        assets.every((asset) => asset.cents >= 0) &&
        assets.map((asset) => asset.id).toSet().length == assets.length &&
        assets.fold<BigInt>(
              BigInt.zero,
              (sum, asset) => sum + BigInt.from(asset.cents),
            ) ==
            BigInt.from(total);
    if (!valid) {
      return const AfStatus(
        kind: AfStatusKind.error,
        message:
            'Datos de distribución incoherentes. Revisa la foto de origen.',
      );
    }
    return AfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          Text('$period · EUR · foto del día 1'),
          AfValueRow(
            label: 'Activos totales',
            value: AfMoneyText(totalAssets, signed: false),
          ),
          if (total == 0)
            const Text('Distribución no representable: activos totales cero.'),
          for (final asset in assets) ...[
            AfValueRow(
              label: asset.label,
              value: AfMoneyText(AfAmount(asset.cents), signed: false),
              onPressed: asset.onPressed,
            ),
            if (total > 0)
              ExcludeSemantics(
                child: SizedBox(
                  height: 12,
                  child: LayoutBuilder(
                    builder: (context, constraints) => Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: constraints.maxWidth * (asset.cents / total),
                        decoration: BoxDecoration(
                          color: AfTokens.seriesAsset,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
          AfValueRow(
            label: 'Deudas · magnitud separada',
            value: AfMoneyText(debt, signed: false),
          ),
        ],
      ),
    );
  }
}

class _ChartFrame extends StatelessWidget {
  const _ChartFrame({
    required this.title,
    required this.period,
    required this.unit,
    required this.roles,
    required this.values,
    required this.plot,
    required this.children,
  });
  final String title;
  final String period;
  final AfChartUnit unit;
  final Set<AfSeriesRole> roles;
  final List<AfChartValue> values;
  final Widget plot;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => AfCard(
    child: LayoutBuilder(
      builder: (context, constraints) {
        // A 200 % o en ancho muy estrecho conservar únicamente los datos equivalentes.
        final textOnly =
            MediaQuery.textScalerOf(context).scale(16) >= 32 ||
            constraints.maxWidth < 260;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            Text('$period · ${unit == AfChartUnit.eur ? 'EUR' : 'meses'}'),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                for (final role in roles)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [
                      ExcludeSemantics(
                        child: Container(
                          width: 14,
                          height: 14,
                          color: _color(role),
                        ),
                      ),
                      Flexible(
                        child: Text(switch (role) {
                          AfSeriesRole.real => 'Real · continuo',
                          AfSeriesRole.budget => 'Presupuesto · discontinuo',
                          AfSeriesRole.asset => 'Activos',
                          AfSeriesRole.debt => 'Deudas',
                        }, style: Theme.of(context).textTheme.bodySmall),
                      ),
                    ],
                  ),
              ],
            ),
            AfNumericText(_axisRange(values, unit)),
            if (!textOnly) ExcludeSemantics(child: plot),
            Text(
              '${textOnly ? 'Datos equivalentes' : 'Escala común, cero explícito'} · ${unit == AfChartUnit.eur ? 'importes firmados en EUR' : 'meses'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            ...children,
          ],
        );
      },
    ),
  );
}

String _axisRange(List<AfChartValue> values, AfChartUnit unit) {
  AfChartValue? minimum;
  AfChartValue? maximum;
  for (final value in values) {
    final plot = value.plotValue;
    if (plot == null) continue;
    if (plot < (minimum?.plotValue ?? 0)) minimum = value;
    if (plot > (maximum?.plotValue ?? 0)) maximum = value;
  }
  final zero = unit == AfChartUnit.eur ? '0,00 €' : '0,00 meses';
  return 'Eje: ${minimum?.formatted ?? zero} a ${maximum?.formatted ?? zero}';
}

abstract class _AfPainter extends CustomPainter {
  _AfPainter(this.scale);
  final AfChartScale scale;
  void dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    final length = (b - a).distance;
    if (length == 0) return;
    final step = (b - a) / length;
    for (var distance = 0.0; distance < length; distance += 10) {
      canvas.drawLine(
        a + step * distance,
        a + step * math.min(distance + 5, length),
        paint,
      );
    }
  }

  void text(Canvas canvas, String text, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontFamily: AfTokens.family,
          fontSize: 14,
          color: AfTokens.muted,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _BarsPainter extends _AfPainter {
  _BarsPainter(this.data, super.scale);
  final List<AfBarDatum> data;
  @override
  void paint(Canvas canvas, Size size) {
    final width = math.max(0.0, size.width - 24);
    final x0 = 12 + width * scale.position(0);
    final baseline = size.height - 24;
    canvas.drawLine(
      Offset(x0, 0),
      Offset(x0, baseline),
      Paint()
        ..color = AfTokens.controlBorder
        ..strokeWidth = 1.75,
    );
    canvas.drawLine(
      Offset(12, baseline),
      Offset(size.width - 12, baseline),
      Paint()..color = AfTokens.controlBorder,
    );
    text(
      canvas,
      '0',
      Offset(x0.clamp(0, math.max(0, size.width - 12)), baseline + 3),
    );
    for (var i = 0; i < data.length; i++) {
      final value = data[i].value.plotValue;
      if (value == null) continue;
      final y = 6 + i * (baseline - 12) / math.max(1, data.length);
      final end = 12 + width * scale.position(value);
      final paint = Paint()..color = _color(data[i].role);
      if (value == 0) {
        canvas.drawCircle(Offset(x0, y + 8), 3, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(math.min(x0, end), y, math.max(x0, end), y + 16),
            const Radius.circular(2),
          ),
          paint,
        );
      }
    }
  }
}

class _TimePainter extends _AfPainter {
  _TimePainter(this.series, super.scale);
  final List<AfTimeSeries> series;
  @override
  void paint(Canvas canvas, Size size) {
    final all = series.expand((item) => item.points).toList();
    if (all.isEmpty) return;
    final first = all.map((point) => point.periodIndex).reduce(math.min);
    final last = all.map((point) => point.periodIndex).reduce(math.max);
    final bottom = size.height - 28;
    final zero = bottom - (bottom - 12) * scale.position(0);
    canvas.drawLine(
      Offset(12, zero),
      Offset(size.width - 12, zero),
      Paint()
        ..color = AfTokens.controlBorder
        ..strokeWidth = 1.75,
    );
    text(canvas, '0', Offset(12, zero.clamp(0, bottom)));
    for (final item in series) {
      Offset? previous;
      int? previousPeriod;
      for (final point in item.points) {
        final value = point.value.plotValue;
        if (value == null) {
          previous = null;
          previousPeriod = null;
          continue;
        }
        final x = first == last
            ? size.width / 2
            : 24 +
                  (size.width - 48) *
                      (point.periodIndex - first) /
                      (last - first);
        final current = Offset(
          x,
          bottom - (bottom - 12) * scale.position(value),
        );
        final paint = Paint()
          ..color = _color(item.role)
          ..strokeWidth = 2;
        if (previous != null && point.periodIndex == previousPeriod! + 1) {
          if (item.role == AfSeriesRole.budget) {
            dashed(canvas, previous, current, paint);
          } else {
            canvas.drawLine(previous, current, paint);
          }
        }
        canvas.drawCircle(current, 4, paint);
        previous = current;
        previousPeriod = point.periodIndex;
      }
    }
    // Extremos temporales; cada periodo y valor exactos están en las filas.
    text(canvas, all.first.label, Offset(12, bottom + 7));
    if (first != last) {
      final painter = TextPainter(
        text: TextSpan(
          text: all.last.label,
          style: const TextStyle(
            fontFamily: AfTokens.family,
            fontSize: 14,
            color: AfTokens.muted,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(math.max(12, size.width - painter.width - 12), bottom + 7),
      );
    }
  }
}
