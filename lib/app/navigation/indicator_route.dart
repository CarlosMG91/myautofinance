import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../features/indicators/presentation/indicator_screen.dart';
import '../../features/indicators/presentation/indicator_source.dart';
import 'app_routes.dart';
import 'indicator_origin.dart';
import 'navigation_context.dart';
import 'navigation_session.dart';
import 'primary_navigation.dart';
import 'session_location.dart';
import 'session_navigation_error.dart';

class IndicatorRoute extends StatefulWidget {
  const IndicatorRoute({
    super.key,
    required this.settings,
    required this.load,
    this.session,
    this.photosAvailable = false,
    this.budgetsAvailable = false,
  });
  final RouteSettings settings;
  final IndicatorLoader load;
  final NavigationSession? session;
  final bool photosAvailable, budgetsAvailable;
  @override
  State<IndicatorRoute> createState() => _IndicatorRouteState();
}

class _IndicatorRouteState extends State<IndicatorRoute> {
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
      final parsed = IndicatorOrigin(resolved.context).context;
      final argument = widget.settings.arguments;
      _initial =
          argument is NavigationContext &&
              argument.period == parsed.period &&
              argument.destination == parsed.destination &&
              argument.filters['detalle'] == parsed.filters['detalle']
          ? IndicatorOrigin(argument).context
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

  void _position(double offset, String? focus) {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _session.setContext(
      _display!.withPosition(offset, focus),
      deferNotification: true,
    );
  }

  Future<void> _open(String path, {int? month}) async {
    final saved = IndicatorOrigin(_session.context);
    final route = ModalRoute.of(context);
    await Navigator.of(context).pushNamed(
      Uri(
        path: path,
        queryParameters: {
          'a': saved.context.period.year.toString().padLeft(4, '0'),
          'm': (month ?? saved.context.period.month).toString().padLeft(2, '0'),
          'origen': saved.route,
        },
      ).toString(),
    );
    if (!mounted || route?.isCurrent != true) return;
    await _session.returnToOrigin(SecondaryNavigationContext(saved.context));
  }

  Future<void> _detail() async {
    final saved = _session.context;
    final detail = NavigationContext(
      destination: SessionDestination.indicators,
      period: saved.period,
      branchId: saved.branchId,
      scope: saved.scope,
      filters: {...saved.filters, 'detalle': '1'},
    );
    final route = ModalRoute.of(context);
    await Navigator.of(context)
        .pushNamed(IndicatorOrigin(detail).route, arguments: detail);
    if (mounted && route?.isCurrent == true) {
      await _session.returnToOrigin(SecondaryNavigationContext(saved));
    }
  }

  Future<bool> _back() async {
    if (Navigator.of(context).canPop()) return Navigator.of(context).maybePop();
    final saved = _session.context;
    final origin = NavigationContext(
      destination: SessionDestination.indicators,
      period: saved.period,
      branchId: saved.branchId,
      scope: saved.scope,
      filters: {
        for (final entry in saved.filters.entries)
          if (entry.key != 'detalle') entry.key: entry.value,
      },
    );
    Navigator.of(context)
        .pushReplacementNamed(IndicatorOrigin(origin).route, arguments: origin);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (_invalid) return SessionNavigationError(origin: _session.context);
    final initial = _initial!;
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        if (ModalRoute.of(context)?.isCurrent != false &&
            _session.context.destination == SessionDestination.indicators) {
          _display = _session.context;
        }
        final selected = _display!;
        final detail = selected.filters['detalle'] == '1';
        return PopScope(
          canPop: !detail || Navigator.of(context).canPop(),
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && detail) _back();
          },
          child: IndicatorScreen(
            load: widget.load,
            month: selected.period.civilMonth,
            detail: detail,
            initialOffset: initial.scrollOffset,
            initialFocus: initial.focus,
            onPosition: _position,
            onPhoto: widget.photosAvailable
                ? () => _open(AppRoutes.wealthPhoto)
                : null,
            onBudget: widget.budgetsAvailable
                ? (month) => _open(AppRoutes.monthlyBudget, month: month)
                : null,
            onDetail: _detail,
            shell: (body, scroll, detailAction) => PrimaryNavigation(
              session: _session,
              title: detail ? 'Cómo se calcula el colchón' : 'Indicadores',
              contextTrail: Text(
                'Foto del 1 de ${DateFormat('MMMM', 'es_ES').format(DateTime(selected.period.year, selected.period.month))} de ${selected.period.year} · presupuesto de ${selected.period.year}',
              ),
              detailAction: detailAction,
              scrollController: scroll,
              backLabel: detail ? 'Volver al resumen' : 'Volver',
              onBack: detail ? _back : null,
              child: body,
            ),
          ),
        );
      },
    );
  }
}
