import 'package:flutter/material.dart';

import '../../../ui/autofinance_ui.dart';

/// Lectura progresiva compartida por revisión, lotes y procedencia.
class ImportSection extends StatelessWidget {
  const ImportSection({
    super.key,
    required this.title,
    required this.children,
    this.tone = AfCardTone.normal,
  });
  final String title;
  final List<Widget> children;
  final AfCardTone tone;

  @override
  Widget build(BuildContext context) => AfCard(
    tone: tone,
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          ...children,
        ],
      ),
    ),
  );
}

class ImportSteps extends StatelessWidget {
  const ImportSteps({super.key, required this.current});
  final int current;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final entry in const [
        'Selección',
        'Revisión',
        'Asignación',
        'Confirmación',
        'Resultado',
      ].asMap().entries)
        Semantics(
          selected: entry.key == current,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: entry.key == current
                  ? AfTokens.accentTint
                  : AfTokens.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: entry.key == current ? AfTokens.accent : AfTokens.border,
                width: entry.key == current ? 2 : 1,
              ),
            ),
            child: Text('${entry.key + 1} · ${entry.value}'),
          ),
        ),
    ],
  );
}
