import 'package:flutter/material.dart';

import '../../features/monthly_status/monthly_status.dart';
import '../../features/monthly_status/presentation/monthly_status_screen.dart';
import 'monthly_status_detail_navigation.dart';
import 'monthly_status_origin.dart';
import 'movement_links.dart';
import 'navigation_context.dart';
import 'navigation_session.dart';
import 'period_controls.dart';
import 'primary_navigation.dart';
import 'session_location.dart';
import 'session_navigation_error.dart';

/// Composición de Estado: sesión/links en app; lectura y widgets en su módulo.
class MonthlyStatusRoute extends StatefulWidget {
  const MonthlyStatusRoute({
    super.key,
    required this.settings,
    required this.load,
    required this.management,
    this.session,
  });
  final RouteSettings settings;
  final MonthlyStatusLoader load;
  final NavigationSession? session;
  final Widget Function(
    String Function() origin,
    Future<void> Function() refresh,
  )
  management;
  @override
  State<MonthlyStatusRoute> createState() => _MonthlyStatusRouteState();
}

class _MonthlyStatusRouteState extends State<MonthlyStatusRoute> {
  late final NavigationSession _session;
  late final bool _ownsSession;
  NavigationContext? _initial;
  NavigationContext? _displayContext;
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _ownsSession = widget.session == null;
    _session = widget.session ?? NavigationSession();
    try {
      final resolved = SessionLocation.resolve(widget.settings.name!, _session);
      if (resolved is! ValidSessionLocation) throw const FormatException();
      final uri = Uri.parse(widget.settings.name!);
      final route = uri.queryParameters.containsKey('m')
          ? widget.settings.name!
          : SessionLocation.encode(resolved.context);
      final parsed = MonthlyStatusOrigin.parse(route).context;
      final argument = widget.settings.arguments;
      _initial =
          argument is NavigationContext &&
              argument.destination == parsed.destination &&
              argument.period == parsed.period
          ? MonthlyStatusOrigin(argument).context
          : parsed;
      _displayContext = _initial;
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

  void _position(MonthlyStatusPosition position) {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    final current = _session.context;
    _session.setContext(
      NavigationContext(
        destination: SessionDestination.status,
        period: current.period,
        branchId: position.categoryId,
        scope: position.scope,
        filters: {
          if (current.filters['concepto'] != null)
            'concepto': current.filters['concepto']!,
          'abiertas': position.expanded.join(','),
        },
        scrollOffset: position.offset,
        focus: position.focus,
      ),
      deferNotification: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_invalid) return SessionNavigationError(origin: _session.context);
    final saved = _initial!;
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        // Otra vista puede cambiar el periodo compartido mientras Estado queda
        // bajo ella en la pila. Aplicarlo al volver evita consultas ocultas.
        if (ModalRoute.of(context)?.isCurrent != false) {
          _displayContext = _session.context;
        }
        final month = _displayContext!.period.budgetMonth;
        String origin() => MonthlyStatusOrigin(_session.context).route;
        return MonthlyStatusScreen(
          load: widget.load,
          month: month,
          initialPosition: MonthlyStatusPosition(
            expanded: (saved.filters['abiertas'] ?? '')
                .split(',')
                .where((id) => id.isNotEmpty)
                .toSet(),
            offset: saved.scrollOffset,
            focus: saved.focus,
            categoryId: saved.branchId,
            scope: saved.scope,
          ),
          onPosition: _position,
          details: createMonthlyStatusDetailCallbacks(
            context: context,
            origin: () => _session.context,
            session: _session,
          ),
          onAdd: () async {
            final saved = _session.context;
            await Navigator.of(context).pushNamed(
              MovementLinks.create(
                MonthlyFigureDetail(month: month).movements,
                origin: origin(),
              ),
            );
            if (!context.mounted) return;
            // «Ver mes» tras guardar fuera del origen conserva su selección explícita.
            if (_session.period == saved.period) {
              await _session.returnToOrigin(SecondaryNavigationContext(saved));
            }
          },
          periodControls: PeriodControls(session: _session),
          shell: (body, scroll, refresh) => PrimaryNavigation(
            session: _session,
            title: 'Estado del mes',
            scrollController: scroll,
            actions: [widget.management(origin, refresh)],
            child: body,
          ),
        );
      },
    );
  }
}
