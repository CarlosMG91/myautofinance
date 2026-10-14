import 'package:flutter/material.dart';

import '../../features/movements/movements.dart';
import '../../features/movements/presentation/movement_list_controller.dart';
import '../../features/movements/presentation/movement_list_screen.dart';
import 'app_routes.dart';
import 'wealth_route.dart';
import 'movement_editor_route.dart';
import 'movement_links.dart';
import 'pending_movement_origin.dart';
import 'navigation_session.dart';
import 'navigation_context.dart';
import 'primary_navigation.dart';
import '../../ui/autofinance_ui.dart';
import 'monthly_status_origin.dart';
import 'annual_actual_origin.dart';
import '../category_selector_navigation.dart';
import '../../features/movements/presentation/category_tree_screen.dart';

class MovementListOrigin {
  const MovementListOrigin(this.route, {this.context});
  final String route;
  final NavigationContext? context;
  String get label {
    final uri = Uri.tryParse(route);
    if (const {
      AppRoutes.actualSpending,
      AppRoutes.actualDetail,
    }.contains(uri?.path)) {
      return 'Real anual, ${uri?.queryParameters['a']}';
    }
    for (final destination in AppRoutes.destinations) {
      if (destination.path == uri?.path) {
        final a = uri?.queryParameters['a'];
        final m = uri?.queryParameters['m'];
        return '${destination.label}${a == null ? '' : ', ${m == null ? a : '$m/$a'}'}';
      }
    }
    if (uri?.path == AppRoutes.start) {
      return 'Inicio, ${uri?.queryParameters['m']}/${uri?.queryParameters['a']}';
    }
    return 'Autofinance';
  }
}

/// Los informes pueden fijar c (UUID), alcance=direct/branch o sinClasificar=1.
class MovementListRoute extends StatefulWidget {
  const MovementListRoute({
    super.key,
    required this.settings,
    required this.load,
    this.categories,
    this.navigationSession,
  });
  final RouteSettings settings;
  final MovementListLoader load;
  final CategoryManagementLoader? categories;
  final NavigationSession? navigationSession;
  @override
  State<MovementListRoute> createState() => _MovementListRouteState();
}

class _MovementListRouteState extends State<MovementListRoute> {
  MovementListController? _controller;
  late bool _explicitPeriod;
  @override
  void initState() {
    super.initState();
    final p = Uri.tryParse(widget.settings.name ?? '')?.queryParameters;
    final saved = widget.settings.arguments;
    _explicitPeriod = saved is NavigationContext
        ? saved.filters['__range'] == 'custom'
        : p?.containsKey('desde') == true;
    widget.navigationSession?.addListener(_periodChanged);
  }

  void _periodChanged() {
    final session = widget.navigationSession;
    final controller = _controller;
    if (_explicitPeriod ||
        session == null ||
        controller == null ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final period = session.period;
    final until = period.next?.firstDay;
    if (controller.from.value != period.firstDay.value ||
        controller.until?.value != until?.value) {
      controller.changePeriod(period.firstDay, until);
    }
  }

  @override
  void dispose() {
    widget.navigationSession?.removeListener(_periodChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      final query = MovementLinks.parse(
        widget.settings.name!,
        defaultMonth:
            widget.navigationSession?.period.civilMonth ??
            madridMonth(DateTime.now()),
      );
      final firstBuild = _controller == null;
      final controller = _controller ??= MovementListController(
        load: widget.load,
        from: query.from,
        until: query.until,
        categoryId: query.categoryId,
        unclassified: query.unclassified,
        scope: query.scope,
        accountId: query.accountId,
        concept: query.concept,
      );
      final saved = widget.settings.arguments;
      if (firstBuild && saved is NavigationContext) {
        controller.scrollOffset = saved.scrollOffset;
        controller.focus = saved.focus;
      }
      final principal =
          widget.settings.arguments is! MovementListOrigin &&
          MovementLinks.origin(widget.settings.name!) == null;
      final origin = widget.settings.arguments is MovementListOrigin
          ? (widget.settings.arguments as MovementListOrigin).route
          : MovementLinks.origin(widget.settings.name!) ?? AppRoutes.start;
      String currentRoute() => MovementLinks.list(
        MovementListQuery(
          from: controller.from,
          until: controller.until,
          accountId: controller.accountId,
          categoryId: controller.categoryId,
          scope: controller.scope,
          unclassified: controller.unclassified,
          concept: controller.concept,
        ),
        origin: principal ? null : origin,
      );
      void capture(double offset, String? focus) {
        final session = widget.navigationSession;
        if (!principal ||
            session == null ||
            ModalRoute.of(context)?.isCurrent == false) {
          return;
        }
        session.setContext(
          NavigationContext(
            destination: SessionDestination.movements,
            period: session.period,
            branchId: controller.unclassified
                ? 'sin-clasificar'
                : controller.categoryId,
            scope: controller.scope,
            scrollOffset: offset,
            focus: focus,
            filters: {
              'desde': controller.from.value,
              if (controller.until != null) 'hasta': controller.until!.value,
              if (controller.accountId != null) 'cuenta': controller.accountId!,
              if (controller.concept.isNotEmpty) 'concepto': controller.concept,
              '__range': _explicitPeriod ? 'custom' : 'period',
            },
          ),
          deferNotification: true,
        );
      }

      return MovementListScreen(
        returnLabel: 'Volver a ${MovementListOrigin(origin).label}',
        shell: widget.navigationSession == null
            ? null
            : (body, scroll, canLeave) => PrimaryNavigation(
                session: widget.navigationSession!,
                title: 'Movimientos',
                backLabel: 'Volver a ${MovementListOrigin(origin).label}',
                scrollController: scroll,
                beforeNavigate: canLeave,
                contextTrail: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_explicitPeriod)
                      Text(
                        'Rango propio: ${controller.from.value} → ${controller.until?.value ?? 'fin del calendario'}',
                      ),
                    if (_explicitPeriod)
                      AfAction(
                        label: 'Usar mes seleccionado',
                        icon: AfIcons.calendar,
                        onPressed: () async {
                          if (!await canLeave() || !mounted) return;
                          setState(() => _explicitPeriod = false);
                          _periodChanged();
                          capture(0, null);
                        },
                      ),
                  ],
                ),
                onBack: principal
                    ? null
                    : () async {
                        if (!await canLeave() || !context.mounted) return false;
                        if (Navigator.of(context).canPop()) {
                          return Navigator.of(context).maybePop();
                        }
                        Navigator.of(context).pushReplacementNamed(origin);
                        return true;
                      },
                child: body,
              ),
        onOrigin: capture,
        controller: controller,
        onPending: () async {
          await Navigator.of(context).pushNamed(
            AppRoutes.pendingMovements,
            arguments: PendingMovementOrigin(
              route: currentRoute(),
              label: 'Volver a Movimientos',
            ),
          );
        },
        onFiltersApplied: () {
          _explicitPeriod = true;
          capture(0, null);
          setState(() {});
        },
        onReturn: () {
          final navigator = Navigator.of(context);
          if (navigator.canPop()) {
            navigator.pop();
          } else {
            final saved = widget.settings.arguments is MovementListOrigin
                ? (widget.settings.arguments as MovementListOrigin).context
                : null;
            final restored =
                saved ??
                (const {
                      AppRoutes.actualSpending,
                      AppRoutes.actualDetail,
                    }.contains(Uri.parse(origin).path)
                    ? AnnualActualOrigin.parse(origin).context
                    : null) ??
                (const {
                          AppRoutes.monthlyStatus,
                          AppRoutes.start,
                        }.contains(Uri.parse(origin).path) &&
                        Uri.parse(origin).hasQuery
                    ? MonthlyStatusOrigin.parse(origin).context
                    : null);
            navigator.pushReplacementNamed(origin, arguments: restored);
          }
        },
        selectCategory: widget.categories == null
            ? null
            : () => selectCategory(context, loadManagement: widget.categories!),
        onCreate: () async {
          await Navigator.of(context).pushNamed(
            '${AppRoutes.movements}/nuevo',
            arguments: MovementEditorOrigin(
              controller.context,
              listRoute: currentRoute(),
            ),
          );
        },
        onOpen: (id) async {
          await Navigator.of(context).pushNamed(
            '${AppRoutes.movements}/$id',
            arguments: MovementEditorOrigin(
              controller.context,
              listRoute: currentRoute(),
            ),
          );
        },
      );
    } catch (_) {
      return Scaffold(
        appBar: AppBar(title: const Text('No se pudo abrir este detalle')),
        body: TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Volver al origen'),
        ),
      );
    }
  }
}
