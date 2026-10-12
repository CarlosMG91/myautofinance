import 'package:flutter/material.dart';

import 'tokens.dart';
import 'values.dart';
import 'icons.dart';

enum AfCardTone { normal, real, budget }

class AfNumericText extends StatelessWidget {
  const AfNumericText(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodyLarge
        ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
  );
}

class AfCard extends StatelessWidget {
  const AfCard({super.key, required this.child, this.tone = AfCardTone.normal});
  final Widget child;
  final AfCardTone tone;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Container(
      padding: EdgeInsets.all(
        AfTokens.reflow(context, MediaQuery.sizeOf(context).width) ? 16 : 24,
      ),
      decoration: BoxDecoration(
        color: tone == AfCardTone.real ? AfTokens.accentTint : AfTokens.surface,
        borderRadius: BorderRadius.circular(AfTokens.cardRadius),
        border: Border.all(
          color: tone == AfCardTone.real
              ? AfTokens.accent
              : tone == AfCardTone.budget
              ? AfTokens.seriesBudget
              : AfTokens.border,
          width: tone == AfCardTone.budget ? 2 : 1,
        ),
      ),
      child: child,
    ),
  );
}

class AfMoneyText extends StatelessWidget {
  const AfMoneyText(
    this.amount, {
    super.key,
    this.signed = true,
    this.hero = false,
    this.semanticLabel,
  });
  final AfAmount amount;
  final bool signed;
  final bool hero;
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final reflow = MediaQuery.textScalerOf(context).scale(16) >= 24;
      final style =
          (hero && !reflow
                  ? Theme.of(context).textTheme.displaySmall
                  : Theme.of(context).textTheme.bodyLarge)!
              .copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              );
      final formatted = amount.format(signed: signed);
      // Moneda puede refluir, signo y número permanecen juntos, sin FittedBox.
      final parts = amount.cents == null ? [formatted] : formatted.split(' ');
      return Semantics(
        label: semanticLabel ?? formatted,
        excludeSemantics: true,
        child: Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [for (final part in parts) Text(part, style: style)],
        ),
      );
    },
  );
}

class AfSummaryCard extends StatelessWidget {
  const AfSummaryCard({
    super.key,
    required this.label,
    required this.amount,
    required this.contextLabel,
    this.tone = AfCardTone.normal,
    this.signed = true,
    this.comparison,
    this.onDetail,
  });
  final String label;
  final AfAmount amount;
  final String contextLabel;
  final AfCardTone tone;
  final bool signed;
  final AfComparisonState? comparison;
  final VoidCallback? onDetail;
  @override
  Widget build(BuildContext context) => AfCard(
    tone: tone,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        AfMoneyText(
          amount,
          signed: signed,
          hero: true,
          semanticLabel:
              '$label, ${amount.format(signed: signed)}, $contextLabel',
        ),
        Text(
          contextLabel,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: AfTokens.muted),
        ),
        if (comparison != null) AfComparisonBadge(comparison!),
        if (onDetail != null)
          AfAction(
            label: 'Ver detalle',
            onPressed: onDetail,
            variant: AfActionVariant.link,
          ),
      ],
    ),
  );
}

class AfComparisonBadge extends StatelessWidget {
  const AfComparisonBadge(this.state, {super.key});
  final AfComparisonState state;
  @override
  Widget build(BuildContext context) {
    final (label, color, background) = switch (state) {
      AfComparisonState.favorable => (
        'Favorable',
        AfTokens.favorable,
        AfTokens.favorableTint,
      ),
      AfComparisonState.unfavorable => (
        'Desfavorable',
        AfTokens.unfavorable,
        AfTokens.unfavorableTint,
      ),
      AfComparisonState.equal => (
        'Igual',
        AfTokens.muted,
        AfTokens.surfaceSubtle,
      ),
      AfComparisonState.unbudgeted => (
        'Sin presupuesto',
        AfTokens.warning,
        AfTokens.warningTint,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          if (state == AfComparisonState.favorable ||
              state == AfComparisonState.unfavorable)
            AfIcon(
              state == AfComparisonState.favorable
                  ? AfIcons.arrowUp
                  : AfIcons.arrowDown,
              size: 20,
              color: color,
            ),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

enum AfActionVariant { primary, secondary, link }

class AfAction extends StatelessWidget {
  const AfAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AfActionVariant.secondary,
    this.unavailableReason,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AfActionVariant variant;
  final String? unavailableReason;
  @override
  Widget build(BuildContext context) {
    final content = Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        if (icon != null)
          AfIcon(
            icon!,
            color: variant == AfActionVariant.primary && onPressed != null
                ? AfTokens.onAccent
                : AfTokens.accent,
          ),
        Text(
          label,
          style: variant == AfActionVariant.link
              ? const TextStyle(decoration: TextDecoration.underline)
              : null,
        ),
      ],
    );
    final button = switch (variant) {
      AfActionVariant.primary => FilledButton(
        style: ButtonStyle(animationDuration: AfTokens.duration(context)),
        onPressed: onPressed,
        child: content,
      ),
      AfActionVariant.secondary => OutlinedButton(
        style: ButtonStyle(animationDuration: AfTokens.duration(context)),
        onPressed: onPressed,
        child: content,
      ),
      AfActionVariant.link => TextButton(
        style: ButtonStyle(animationDuration: AfTokens.duration(context)),
        onPressed: onPressed,
        child: content,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        if (onPressed == null && unavailableReason != null)
          Text(
            unavailableReason!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

/// Fila sin cuadrícula dominante: cifra y contexto refluyen a una columna.
class AfValueRow extends StatelessWidget {
  const AfValueRow({
    super.key,
    required this.label,
    required this.value,
    this.contextLabel,
    this.onPressed,
    this.icon,
    this.selected = false,
  });
  final String label;
  final Widget value;
  final String? contextLabel;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool selected;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final leading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
          if (contextLabel != null)
            Text(
              contextLabel!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AfTokens.muted),
            ),
        ],
      );
      final content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child:
            constraints.maxWidth < 360 ||
                MediaQuery.textScalerOf(context).scale(16) >= 24
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [if (icon != null) AfIcon(icon!), leading, value],
              )
            : Row(
                spacing: 16,
                children: [
                  if (icon != null) AfIcon(icon!),
                  Expanded(child: leading),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: value,
                    ),
                  ),
                ],
              ),
      );
      return Semantics(
        container: true,
        selected: selected,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? AfTokens.accentTint : null,
            border: const Border(bottom: BorderSide(color: AfTokens.border)),
          ),
          child: onPressed == null
              ? content
              : TextButton(
                  onPressed: onPressed,
                  style: TextButton.styleFrom(alignment: Alignment.centerLeft)
                      .copyWith(animationDuration: AfTokens.duration(context)),
                  child: content,
                ),
        ),
      );
    },
  );
}

enum AfStatusKind {
  loading,
  empty,
  missing,
  pending,
  success,
  divergence,
  error,
}

class AfStatus extends StatelessWidget {
  const AfStatus({
    super.key,
    required this.kind,
    required this.message,
    this.action,
  });
  final AfStatusKind kind;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final label = switch (kind) {
      AfStatusKind.loading => 'Cargando',
      AfStatusKind.empty => 'Sin registros',
      AfStatusKind.missing => 'Sin dato',
      AfStatusKind.pending => 'Pendiente',
      AfStatusKind.success => 'Completado',
      AfStatusKind.divergence => 'Copias divergentes',
      AfStatusKind.error => 'Error',
    };
    final color = kind == AfStatusKind.error
        ? AfTokens.error
        : kind == AfStatusKind.pending || kind == AfStatusKind.divergence
        ? AfTokens.warning
        : AfTokens.muted;
    return Semantics(
      liveRegion: true,
      child: AfCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: color),
            ),
            Text(message),
            if (kind == AfStatusKind.loading) const Text('Operación en curso'),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// Etiqueta y ayuda persistentes. Validación y borrador pertenecen al consumidor.
class AfFormField extends StatelessWidget {
  const AfFormField({
    super.key,
    required this.label,
    required this.controller,
    this.help,
    this.required = false,
    this.validator,
    this.onChanged,
    this.focusNode,
    this.keyboardType,
    this.enabled = true,
  });
  final String label;
  final TextEditingController controller;
  final String? help;
  final bool required;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final bool enabled;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: AfTokens.formMax),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text(
          '$label${required ? ' · obligatorio' : ''}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        if (help != null)
          Text(help!, style: Theme.of(context).textTheme.bodySmall),
        Semantics(
          label: label,
          isRequired: required,
          child: TextFormField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: keyboardType,
            enabled: enabled,
            validator: validator,
            onChanged: onChanged,
            decoration: InputDecoration(
              semanticCounterText: label,
              hintText: null,
            ),
          ),
        ),
      ],
    ),
  );
}

class AfPeriodSelector extends StatelessWidget {
  const AfPeriodSelector({
    super.key,
    required this.label,
    required this.options,
    required this.selectedId,
    required this.onChanged,
  });
  final String label;
  final List<AfPeriodOption> options;
  final String selectedId;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 4,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      DropdownButtonFormField<String>(
        icon: const AfIcon(AfIcons.chevronDown),
        initialValue: selectedId,
        isExpanded: true,
        decoration: InputDecoration(semanticCounterText: label),
        items: [
          for (final option in options)
            DropdownMenuItem(value: option.id, child: Text(option.label)),
        ],
        onChanged: onChanged == null
            ? null
            : (value) {
                if (value != null) onChanged!(value);
              },
      ),
    ],
  );
}
