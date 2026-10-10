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
  });

  final NavigationSession session;
  final String title;
  final Widget child;
  final List<Widget> actions;
  final ScrollController? scrollController;

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
          appBar: AppBar(title: Text(title), actions: actions),
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
