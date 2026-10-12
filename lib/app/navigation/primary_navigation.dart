import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/autofinance_ui.dart';
import 'app_routes.dart';
import 'navigation_context.dart';
import 'navigation_session.dart';
import 'period_controls.dart';
import 'session_location.dart';

/// Única composición del shell. Los módulos entregan contenido y guards.
class PrimaryNavigation extends StatelessWidget {
  const PrimaryNavigation({
    super.key,
    required this.session,
    required this.title,
    required this.child,
    this.actions = const [],
    this.scrollController,
    this.wrapHeader = false,
    this.beforeNavigate,
    this.periodControl,
    this.contextTrail,
    this.detailAction,
    this.status,
    this.selectedDestination,
    this.onBack,
    this.navigationAvailable = true,
    this.backLabel = 'Volver',
  });

  final NavigationSession session;
  final String title;
  final Widget child;
  final List<Widget> actions;
  final ScrollController? scrollController;
  final bool wrapHeader;
  final NavigationLeaveGuard? beforeNavigate;
  final Widget? periodControl, contextTrail, detailAction, status;
  final SessionDestination? selectedDestination;
  final Future<bool> Function()? onBack;
  final bool navigationAvailable;
  final String backLabel;

  static const labels = {
    SessionDestination.home: 'Inicio',
    SessionDestination.status: 'Estado',
    SessionDestination.wealth: 'Patrimonio',
    SessionDestination.budget: 'Presupuesto',
    SessionDestination.movements: 'Movimientos',
    SessionDestination.analysis: 'Análisis',
    SessionDestination.more: 'Más',
    SessionDestination.management: 'Gestión',
    SessionDestination.actual: 'Real anual',
    SessionDestination.indicators: 'Indicadores',
    SessionDestination.diagnostics: 'Diagnóstico de coherencia',
  };

  static String selection(
    SessionDestination destination, {
    required bool desktop,
  }) => switch (destination) {
    SessionDestination.home || SessionDestination.status => 'home',
    SessionDestination.budget => 'budget',
    SessionDestination.movements => 'movements',
    SessionDestination.wealth => 'wealth',
    SessionDestination.more ||
    SessionDestination.management => desktop ? 'management' : 'more',
    _ => desktop ? 'analysis' : 'more',
  };

  Future<bool> _select(BuildContext context, String id) async {
    final destination = SessionDestination.values.byName(id);
    final route = ModalRoute.of(context);
    final path = Uri.tryParse(route?.settings.name ?? '')?.path;
    if (destination == session.context.destination &&
        AppRoutes.contentPath(path ?? '') == destination.path) {
      return true;
    }
    final revision = session.navigationRevision;
    try {
      if (beforeNavigate != null && !await beforeNavigate!()) return false;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo resolver la salida. Sigue en esta pantalla.',
            ),
          ),
        );
      }
      return false;
    }
    if (!context.mounted ||
        route?.isCurrent == false ||
        revision != session.navigationRevision) {
      return false;
    }
    final next = session.contextForDestination(destination);
    final navigator = Navigator.of(context);
    if (const {
      SessionDestination.analysis,
      SessionDestination.more,
      SessionDestination.management,
    }.contains(destination)) {
      navigator.pushNamed(SessionLocation.encode(next), arguments: next);
    } else {
      navigator.pushNamedAndRemoveUntil(
        SessionLocation.encode(next),
        (_) => false,
        arguments: next,
      );
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= AfTokens.wideMin;
        const common = [
          AfNavItem(id: 'home', label: 'Inicio', icon: AfIcons.home),
          AfNavItem(id: 'budget', label: 'Presupuesto', icon: AfIcons.calendar),
          AfNavItem(
            id: 'movements',
            label: 'Movimientos',
            icon: AfIcons.receipt,
          ),
          AfNavItem(id: 'wealth', label: 'Patrimonio', icon: AfIcons.account),
        ];
        Future<bool> back() async {
          if (onBack != null) return onBack!();
          if (beforeNavigate != null && !await beforeNavigate!()) return false;
          if (!context.mounted) return false;
          return Navigator.of(context).maybePop();
        }

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
                back,
            const SingleActivator(LogicalKeyboardKey.escape): back,
          },
          child: AfShell(
            primaryItems: navigationAvailable
                ? [
                    ...common,
                    if (desktop)
                      const AfNavItem(
                        id: 'analysis',
                        label: 'Análisis',
                        icon: AfIcons.analysis,
                      )
                    else
                      const AfNavItem(
                        id: 'more',
                        label: 'Más',
                        icon: AfIcons.more,
                      ),
                  ]
                : const [],
            utilityItems: navigationAvailable && desktop
                ? const [
                    AfNavItem(
                      id: 'management',
                      label: 'Gestión',
                      icon: AfIcons.management,
                    ),
                  ]
                : const [],
            selectedId: selection(
              selectedDestination ?? session.context.destination,
              desktop: desktop,
            ),
            onSelect: (id) => _select(context, id),
            onBack: onBack != null || Navigator.of(context).canPop()
                ? back
                : null,
            periodControl:
                periodControl ??
                PeriodControls(
                  session: session,
                  beforeChange: (_) async =>
                      beforeNavigate == null || await beforeNavigate!(),
                ),
            scrollController: scrollController,
            backLabel: backLabel,
            page: AfPageSlots(
              title: title,
              body: child,
              actions: actions,
              contextTrail: contextTrail,
              detailAction: detailAction,
              status: status,
            ),
          ),
        );
      },
    ),
  );
}
