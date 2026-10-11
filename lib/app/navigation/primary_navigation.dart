import 'package:flutter/material.dart';

import 'navigation_context.dart';
import 'navigation_session.dart';
import 'session_location.dart';

/// Cambiar pestaña sustituye la navegación principal; los detalles siguen
/// usando push/pop. La composición adaptable conserva el mismo contenido.
class PrimaryNavigation extends StatelessWidget {
  const PrimaryNavigation({
    super.key,
    required this.session,
    required this.title,
    required this.child,
    this.actions = const [],
    this.scrollController,
    this.wrapHeader = false,
  });

  final NavigationSession session;
  final String title;
  final Widget child;
  final List<Widget> actions;
  final ScrollController? scrollController;
  final bool wrapHeader;

  static const labels = {
    SessionDestination.status: 'Estado',
    SessionDestination.wealth: 'Patrimonio',
    SessionDestination.budget: 'Presupuesto',
    SessionDestination.actual: 'Real',
    SessionDestination.indicators: 'Indicadores',
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final desktop = width >= 840;
        final expandedHeader =
            wrapHeader &&
            (!desktop || MediaQuery.textScalerOf(context).scale(24) > 32);
        final titleStyle = Theme.of(context).textTheme.titleLarge!;
        final titlePainter = TextPainter(
          text: TextSpan(text: title, style: titleStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: (width - 32).clamp(1, double.infinity));
        final headerHeight =
            titlePainter.height +
            (actions.isEmpty
                ? 0
                : 24 + MediaQuery.textScalerOf(context).scale(20) * 1.4) +
            16;
        titlePainter.dispose();
        Widget navigation(bool vertical) {
          final buttons = [
            for (final entry in labels.entries)
              SizedBox(
                width: vertical ? (width >= 1200 ? 216 : 200) : width / 2,
                child: Semantics(
                  selected: session.context.destination == entry.key,
                  child: TextButton(
                    key: ValueKey('destination-${entry.key.name}'),
                    onPressed: session.context.destination == entry.key
                        ? null
                        : () {
                            final next = NavigationContext(
                              destination: entry.key,
                              period: session.period,
                            );
                            Navigator.of(context).pushNamedAndRemoveUntil(
                              SessionLocation.encode(next),
                              (_) => false,
                              arguments: next,
                            );
                          },
                    child: Text(entry.value),
                  ),
                ),
              ),
          ];
          return vertical
              ? Column(children: buttons)
              : Wrap(alignment: WrapAlignment.center, children: buttons);
        }

        // El contenido conserva su posición en el árbol al cambiar de tamaño:
        // mantiene entradas, desplazamiento y foco.
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: !expandedHeader,
            toolbarHeight: expandedHeader ? headerHeight : null,
            title: expandedHeader
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: titleStyle,
                        overflow: TextOverflow.visible,
                      ),
                      if (actions.isNotEmpty) Wrap(children: actions),
                    ],
                  )
                : Text(title),
            actions: expandedHeader ? null : actions,
          ),
          bottomNavigationBar: desktop
              ? null
              : SafeArea(child: navigation(false)),
          body: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: desktop ? (width >= 1200 ? 216 : 200) : 0,
                  child: desktop
                      ? SingleChildScrollView(child: navigation(true))
                      : null,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: EdgeInsets.all(desktop ? 24 : 16),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
