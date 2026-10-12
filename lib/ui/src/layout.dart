import 'package:flutter/material.dart';

import 'tokens.dart';
import 'icons.dart';
import 'components.dart';

typedef AfSelectDestination = Future<bool> Function(String destinationId);

class AfNavItem {
  const AfNavItem({
    required this.id,
    required this.label,
    required this.icon,
    this.unavailableReason,
  });
  final String id;
  final String label;
  final IconData icon;
  final String? unavailableReason;
}

class AfPageSlots {
  const AfPageSlots({
    required this.title,
    required this.body,
    this.contextTrail,
    this.actions = const [],
    this.status,
    this.detailAction,
  });
  final String title;
  final Widget body;
  final Widget? contextTrail;
  final List<Widget> actions;
  final Widget? status;
  final Widget? detailAction;
}

/// Solo composición visual. La selección, guards, Back y rutas pertenecen a app.
class AfShell extends StatefulWidget {
  const AfShell({
    super.key,
    required this.primaryItems,
    required this.utilityItems,
    required this.selectedId,
    required this.onSelect,
    required this.periodControl,
    required this.page,
    this.onBack,
    this.scrollController,
    this.backLabel = 'Volver',
  });
  final List<AfNavItem> primaryItems;
  final List<AfNavItem> utilityItems;
  final String selectedId;
  final AfSelectDestination onSelect;
  final Widget periodControl;
  final AfPageSlots page;
  final Future<bool> Function()? onBack;

  /// T06 conecta la posición que conserva el propietario del contenido.
  final ScrollController? scrollController;
  final String backLabel;
  @override
  State<AfShell> createState() => _AfShellState();
}

class _AfShellState extends State<AfShell> {
  bool _selecting = false;
  Future<void> _select(AfNavItem item) async {
    if (_selecting || item.unavailableReason != null) return;
    setState(() => _selecting = true);
    try {
      await widget.onSelect(item.id);
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  Widget _item(AfNavItem item, {bool compact = false}) => Tooltip(
    message: item.label,
    child: Semantics(
      key: ValueKey('destination-${item.id}'),
      selected: item.id == widget.selectedId,
      child: Container(
        decoration: BoxDecoration(
          color: item.id == widget.selectedId ? AfTokens.accentTint : null,
          border: item.id == widget.selectedId
              ? Border.all(
                  color: MediaQuery.highContrastOf(context)
                      ? AfTokens.text
                      : AfTokens.accent,
                  width: 2,
                )
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: TextButton(
          style: ButtonStyle(
            animationDuration: AfTokens.duration(context),
            padding: compact
                ? const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                  )
                : null,
          ),
          onPressed: _selecting || item.unavailableReason != null
              ? null
              : () => _select(item),
          child: compact
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AfIcon(item.icon, color: AfTokens.accent),
                    Text(
                      item.label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(letterSpacing: 0),
                    ),
                  ],
                )
              : Row(
                  spacing: 12,
                  children: [
                    AfIcon(item.icon, color: AfTokens.accent),
                    Expanded(child: Text(item.label)),
                    if (item.unavailableReason != null)
                      Expanded(
                        child: Text(
                          item.unavailableReason!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide =
          constraints.maxWidth >= AfTokens.wideMin &&
          !AfTokens.reflow(context, constraints.maxWidth);
      final reflow = MediaQuery.textScalerOf(context).scale(16) >= 24;
      final navigation = wide
          ? SizedBox(
              width: 232,
              child: ColoredBox(
                color: AfTokens.surface,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8,
                    children: [
                      const Text(
                        'autofinance.',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Text('Tus cifras, con contexto.'),
                      const SizedBox(height: 24),
                      for (final item in widget.primaryItems) _item(item),
                      const SizedBox(height: 24),
                      for (final item in widget.utilityItems) _item(item),
                    ],
                  ),
                ),
              ),
            )
          : null;
      final header = ColoredBox(
        color: AfTokens.surface,
        child: Padding(
          padding: EdgeInsets.all(wide ? 24 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              if (widget.onBack != null)
                Tooltip(
                  message: widget.backLabel,
                  child: AfAction(
                    label: widget.backLabel,
                    icon: AfIcons.back,
                    onPressed: () async {
                      await widget.onBack!();
                    },
                  ),
                ),
              FocusTraversalOrder(
                order: const NumericFocusOrder(1),
                child: widget.periodControl,
              ),
              if (!wide)
                FocusTraversalOrder(
                  order: const NumericFocusOrder(0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in widget.utilityItems)
                        SizedBox(
                          width: reflow ? constraints.maxWidth - 32 : 200,
                          child: _item(item),
                        ),
                    ],
                  ),
                ),
              if (!wide && reflow)
                FocusTraversalOrder(
                  order: const NumericFocusOrder(0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in widget.primaryItems)
                        SizedBox(
                          width: constraints.maxWidth - 32,
                          child: _item(item),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
      final main = Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: widget.scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(2),
                      child: AfPageLayout(page: widget.page),
                    ),
                  ],
                ),
              ),
            ),
            if (!wide && !reflow)
              ColoredBox(
                color: AfTokens.surface,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: FocusTraversalOrder(
                    order: const NumericFocusOrder(0),
                    child: LayoutBuilder(
                      builder: (context, navConstraints) {
                        final widths = [
                          for (final item in widget.primaryItems)
                            _navWidth(item.label),
                        ];
                        final total = widths.fold<double>(
                          0,
                          (sum, width) => sum + width,
                        );
                        final base = 48.0 * widths.length;
                        final flexible = (total - base).clamp(
                          1.0,
                          double.infinity,
                        );
                        final remaining = (navConstraints.maxWidth - base - .5)
                            .clamp(0.0, navConstraints.maxWidth);
                        return Wrap(
                          children: [
                            for (var i = 0; i < widget.primaryItems.length; i++)
                              SizedBox(
                                width:
                                    (48 +
                                            remaining *
                                                (widths[i] - 48) /
                                                flexible)
                                        .clamp(48.0, navConstraints.maxWidth),
                                child: _item(
                                  widget.primaryItems[i],
                                  compact: true,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
      return Scaffold(
        body: SafeArea(
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Mantener el índice y tipo del contenido al cruzar 840 px.
                FocusTraversalOrder(
                  order: const NumericFocusOrder(0),
                  child: SizedBox(width: wide ? 232 : 0, child: navigation),
                ),
                main,
              ],
            ),
          ),
        ),
      );
    },
  );
}

double _navWidth(String label) {
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: const TextStyle(
        fontFamily: AfTokens.family,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  return (painter.width + 8).clamp(48, double.infinity);
}

class AfPageHeader extends StatelessWidget {
  const AfPageHeader({
    super.key,
    required this.title,
    this.contextTrail,
    this.actions = const [],
  });
  final String title;
  final Widget? contextTrail;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          ?contextTrail,
        ],
      );
      final controls = Wrap(spacing: 12, runSpacing: 8, children: actions);
      return AfTokens.reflow(context, constraints.maxWidth) ||
              constraints.maxWidth < 760
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 16,
              children: [heading, if (actions.isNotEmpty) controls],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 24,
              children: [
                Expanded(child: heading),
                Flexible(
                  child: Align(alignment: Alignment.topRight, child: controls),
                ),
              ],
            );
    },
  );
}

class AfPageLayout extends StatelessWidget {
  const AfPageLayout({super.key, required this.page});
  final AfPageSlots page;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AfTokens.contentMax),
      child: Padding(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width <= AfTokens.compactMax ? 16 : 32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 24,
          children: [
            AfPageHeader(
              title: page.title,
              contextTrail: page.contextTrail,
              actions: [
                ...page.actions,
                if (page.detailAction != null) page.detailAction!,
              ],
            ),
            if (page.status != null) page.status!,
            page.body,
          ],
        ),
      ),
    ),
  );
}

class AfResponsiveGrid extends StatelessWidget {
  const AfResponsiveGrid({
    super.key,
    required this.children,
    this.columns = 3,
    this.minimumWidth = 280,
  });
  final List<Widget> children;
  final int columns;
  final double minimumWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final count = AfTokens.reflow(context, constraints.maxWidth)
          ? 1
          : ((constraints.maxWidth + 16) / (minimumWidth + 16)).floor().clamp(
              1,
              columns,
            );
      final width = (constraints.maxWidth - 16 * (count - 1)) / count;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class AfDetailRow {
  const AfDetailRow({
    required this.label,
    required this.values,
    this.onExpand,
    this.expanded = false,
    this.depth = 0,
    this.total = false,
  });
  final String label;
  final List<Widget> values;
  final VoidCallback? onExpand;
  final bool expanded;
  final int depth;
  final bool total;
}

/// Matriz íntegra: cabecera y primera columna fijas, scroll interno compartido.
/// Cada celda es un slot: el consumidor aporta cifra, enlace y semántica.
class AfDetailTable extends StatefulWidget {
  const AfDetailTable({
    super.key,
    required this.caption,
    required this.columns,
    required this.rows,
    this.height = 420,
    this.labelWidth = 200,
    this.cellWidth = 160,
  });
  final String caption;
  final List<String> columns;
  final List<AfDetailRow> rows;
  final double height;
  final double labelWidth;
  final double cellWidth;
  @override
  State<AfDetailTable> createState() => _AfDetailTableState();
}

class _AfDetailTableState extends State<AfDetailTable> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      if (widget.rows.any(
        (row) =>
            row.values.length != widget.columns.length ||
            row.depth < 0 ||
            row.depth > 2,
      )) {
        throw ArgumentError(
          'La matriz exige una celda por columna y profundidad entre 0 y 2',
        );
      }
      final labelWidth = widget.labelWidth.clamp(
        100.0,
        constraints.maxWidth * .48,
      );
      final cellWidth = widget.cellWidth * scale;
      // Medir etiquetas mantiene las mismas alturas en ambas mitades, sin elipsis.
      double rowHeight(String label, int depth) {
        final painter =
            TextPainter(
              text: TextSpan(
                text: label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout(
              maxWidth: (labelWidth - 24 - depth * 12 - 48).clamp(
                20,
                labelWidth,
              ),
            );
        return (painter.height + 24).clamp(48 * scale, double.infinity);
      }

      final heights = [
        for (final row in widget.rows) rowHeight(row.label, row.depth),
      ];
      final headerHeight = widget.columns.fold<double>(48, (height, label) {
        final painter = TextPainter(
          text: TextSpan(
            text: label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: cellWidth - 24);
        return height > painter.height + 24 ? height : painter.height + 24;
      });
      Widget cell(
        Widget child,
        double width,
        double height, {
        bool header = false,
      }) => Container(
        width: width,
        height: height,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: header ? AfTokens.surfaceSubtle : AfTokens.surface,
          border: const Border(bottom: BorderSide(color: AfTokens.border)),
        ),
        child: child,
      );
      final tableWidth = labelWidth + cellWidth * widget.columns.length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Semantics(header: true, child: Text(widget.caption)),
          const Text(
            'Desplaza la matriz para consultar todas las columnas.',
            style: TextStyle(fontSize: 14),
          ),
          SizedBox(
            height: widget.height,
            child: Scrollbar(
              controller: _horizontal,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _horizontal,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: AnimatedBuilder(
                    animation: _horizontal,
                    builder: (context, _) {
                      final offset = _horizontal.hasClients
                          ? _horizontal.offset
                          : 0.0;
                      Widget labelCell(
                        String label,
                        double height, {
                        AfDetailRow? row,
                      }) => Transform.translate(
                        offset: Offset(offset, 0),
                        child: cell(
                          Row(
                            children: [
                              if (row?.onExpand != null)
                                Semantics(
                                  expanded: row!.expanded,
                                  child: IconButton(
                                    tooltip: row.expanded
                                        ? 'Contraer $label'
                                        : 'Expandir $label',
                                    onPressed: row.onExpand,
                                    icon: AfIcon(
                                      row.expanded
                                          ? AfIcons.close
                                          : AfIcons.more,
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    left: (row?.depth ?? 0) * 12,
                                  ),
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: row?.total == true
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          labelWidth,
                          height,
                          header: row == null,
                        ),
                      );
                      Widget line(
                        Widget label,
                        List<Widget> values,
                        double height, {
                        bool header = false,
                      }) => Stack(
                        children: [
                          Row(
                            children: [
                              SizedBox(width: labelWidth),
                              for (final value in values)
                                cell(value, cellWidth, height, header: header),
                            ],
                          ),
                          label,
                        ],
                      );
                      return Column(
                        children: [
                          line(
                            labelCell('Concepto', headerHeight),
                            [
                              for (final title in widget.columns)
                                Semantics(
                                  header: true,
                                  child: Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                            headerHeight,
                            header: true,
                          ),
                          Expanded(
                            child: Scrollbar(
                              controller: _vertical,
                              thumbVisibility: true,
                              child: ListView.builder(
                                controller: _vertical,
                                itemCount: widget.rows.length,
                                itemBuilder: (context, index) {
                                  final row = widget.rows[index];
                                  return line(
                                    labelCell(
                                      row.label,
                                      heights[index],
                                      row: row,
                                    ),
                                    row.values,
                                    heights[index],
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
