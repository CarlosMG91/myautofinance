import 'package:flutter/material.dart';

import '../../features/actual_spending/presentation/annual_actual_screen.dart';
import 'annual_actual_navigation.dart';
import 'annual_actual_origin.dart';
import 'navigation_context.dart';
import 'navigation_session.dart';
import 'primary_navigation.dart';
import 'session_location.dart';
import 'session_navigation_error.dart';

/// Una sola interfaz de Real, con detalle real y contexto EP-016/178.
class AnnualActualRoute extends StatefulWidget {
  const AnnualActualRoute({
    super.key,
    required this.settings,
    required this.load,
    this.session,
    this.detail = false,
  });
  final RouteSettings settings;
  final AnnualActualLoader load;
  final NavigationSession? session;
  final bool detail;
  @override
  State<AnnualActualRoute> createState() => _AnnualActualRouteState();
}

class _AnnualActualRouteState extends State<AnnualActualRoute> {
  late final NavigationSession _session;
  late final bool _ownsSession;
  NavigationContext? _initial, _display;
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _ownsSession = widget.session == null;
    _session = widget.session ?? NavigationSession();
    try {
      final resolved = SessionLocation.resolve(widget.settings.name!, _session);
      if (resolved is! ValidSessionLocation) throw const FormatException();
      // Validar antes de cualquier loader, también enlaces sin instantánea.
      final parsed = AnnualActualOrigin(resolved.context).context;
      final argument = widget.settings.arguments;
      _initial =
          argument is NavigationContext && argument.period == parsed.period
          ? AnnualActualOrigin(argument).context
          : parsed;
      _display = _initial;
      _session.setContext(_initial!, deferNotification: true);
    } catch (_) {
      _invalid = true;
    }
  }

  @override
  void dispose() {
    if (_ownsSession) _session.dispose();
    super.dispose();
  }

  void _position(
    Set<String> expanded,
    Set<String> months,
    double offset,
    String? focus,
  ) {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    final current = _display!;
    _session.setContext(
      NavigationContext(
        destination: SessionDestination.actual,
        period: current.period,
        branchId: current.branchId,
        scope: current.scope,
        filters: {'abiertas': expanded.join(','), 'meses': months.join(',')},
        scrollOffset: offset,
        focus: focus,
      ),
      deferNotification: true,
    );
  }

  Future<void> _detail() async {
    final saved = _session.context;
    await Navigator.of(context).pushNamed(
      AnnualActualOrigin(saved.withPosition(0, null), detail: true).route,
      arguments: saved.withPosition(0, null),
    );
    if (mounted && ModalRoute.of(context)?.isCurrent != false) {
      await _session.returnToOrigin(SecondaryNavigationContext(saved));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_invalid) return SessionNavigationError(origin: _session.context);
    final saved = _initial!;
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        if (ModalRoute.of(context)?.isCurrent != false &&
            _session.context.destination == SessionDestination.actual) {
          _display = _session.context;
        }
        final navigation = AnnualActualNavigation(
          context: context,
          origin: () =>
              AnnualActualOrigin(_session.context, detail: widget.detail),
          session: _session,
        );
        return AnnualActualScreen(
          load: widget.load,
          year: _display!.period.year,
          focusedMonth: _display!.period.month,
          detail: widget.detail,
          initialExpanded: (saved.filters['abiertas'] ?? '')
              .split(',')
              .where((id) => id.isNotEmpty)
              .toSet(),
          initialExpandedMonths: (saved.filters['meses'] ?? '')
              .split(',')
              .where((id) => id.isNotEmpty)
              .toSet(),
          initialOffset: saved.scrollOffset,
          initialFocus: saved.focus,
          onPosition: _position,
          open: navigation.open,
          addMovement: navigation.addMovement,
          onDetail: _detail,
          shell: (body, scroll, refresh) => PrimaryNavigation(
            session: _session,
            title: widget.detail ? 'Detalle del real anual' : 'Real anual',
            contextTrail: Text(
              'Año ${_display!.period.year} · Todas las cuentas · Fecha de valor',
            ),
            scrollController: scroll,
            backLabel: widget.detail ? 'Volver al resumen' : 'Volver',
            onBack: widget.detail
                ? () async {
                    if (Navigator.of(context).canPop()) {
                      return Navigator.of(context).maybePop();
                    }
                    final origin = _session.context.withPosition(0, null);
                    Navigator.of(context).pushReplacementNamed(
                      AnnualActualOrigin(origin).route,
                      arguments: origin,
                    );
                    return true;
                  }
                : null,
            child: body,
          ),
        );
      },
    );
  }
}
