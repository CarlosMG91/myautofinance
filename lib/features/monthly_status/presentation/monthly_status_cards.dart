import 'package:flutter/material.dart';

import '../../../ui/autofinance_ui.dart';

/// Composición móvil de las mismas celdas y acciones que usa la tabla.
/// Recibe importes ya presentados: no agrega ni interpreta datos financieros.
class MonthlyStatusCards extends StatelessWidget {
  const MonthlyStatusCards({
    super.key,
    required this.entries,
    required this.period,
  });

  final List<List<Widget>> entries;
  final String period;

  static const labels = [
    'Previsto agregado',
    'Real directo',
    'Real agregado',
    'Diferencia real − previsto',
  ];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final entry in entries)
        Semantics(
          container: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: AfCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  entry.first,
                  Text('$period · Todas las cuentas'),
                  const SizedBox(height: 12),
                  for (var i = 1; i < entry.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [Text(labels[i - 1]), entry[i]],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}
