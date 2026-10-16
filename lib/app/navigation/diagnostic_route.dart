import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/diagnostics/diagnostics.dart';
import '../../features/diagnostics/presentation/diagnostic_controller.dart';
import '../../features/diagnostics/presentation/diagnostic_screen.dart';
import '../../features/wealth/wealth.dart' show Month;
import 'app_routes.dart';
import 'navigation_context.dart';
import 'navigation_session.dart';
import 'pending_movement_origin.dart';
import 'primary_navigation.dart';
import 'session_location.dart';
import 'session_navigation_error.dart';

typedef DiagnosticReferenceExists = Future<bool> Function(
  DiagnosticEntity,
  String,
);

class DiagnosticRoute extends StatefulWidget {
  const DiagnosticRoute({
    super.key,
    required this.settings,
    required this.executor,
    this.session,
    this.changes,
    this.exists,
    this.selectedDestination,
  });
  final RouteSettings settings;
  final DiagnosticExecutor? executor;
  final NavigationSession? session;
  final Stream<int>? changes;
  final DiagnosticReferenceExists? exists;
  final SessionDestination? selectedDestination;
  @override
  State<DiagnosticRoute> createState() => _DiagnosticRouteState();
}

class _DiagnosticRouteState extends State<DiagnosticRoute>
    with WidgetsBindingObserver {
  late final _session = widget.session ?? NavigationSession();
  DiagnosticController? _controller;
  final _scroll = ScrollController();
  NavigationContext? _display;
  bool _invalid = false, _opening = false;
  bool? _wasCurrent;
  int _openRequest = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final result = SessionLocation.resolve(widget.settings.name!, _session);
    if (result is! ValidSessionLocation ||
        result.context.destination != SessionDestination.diagnostics) {
      _invalid = true;
    } else {
      _display = result.context;
      _session.setContext(_display!, deferNotification: true);
    }
    if (widget.executor case final executor?) {
      _controller = DiagnosticController(executor, changes: widget.changes);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (_wasCurrent == true && !current) {
      // No publicar como vigente mientras no se haya comprobado el retorno.
      if (_controller?.report != null && !_controller!.obsolete) {
        _controller!.checking = true;
      }
    } else if (_wasCurrent == false &&
        current &&
        !_opening &&
        _display != null) {
      unawaited(_controller?.validate(_display!.period.civilMonth));
    }
    _wasCurrent = current;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _controller?.cancel();
    }
    if (state == AppLifecycleState.resumed && _display != null) {
      unawaited(_controller?.validate(_display!.period.civilMonth));
    }
  }

  @override
  void dispose() {
    _openRequest++;
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _scroll.dispose();
    if (widget.session == null) _session.dispose();
    super.dispose();
  }

  String _period(String path, Month month) => Uri(
    path: path,
    queryParameters: {
      'a': month.value.substring(0, 4),
      'm': month.value.substring(5, 7),
    },
  ).toString();

  String _catalog(DiagnosticEntity entity) => switch (entity) {
    DiagnosticEntity.category => AppRoutes.categories,
    DiagnosticEntity.account ||
    DiagnosticEntity.wealthValue ||
    DiagnosticEntity.wealthSnapshot ||
    DiagnosticEntity.liquidityPeriod => AppRoutes.accounts,
    DiagnosticEntity.budget => _period(
      '${AppRoutes.budget}/partidas',
      _display!.period.civilMonth,
    ),
    DiagnosticEntity.movement => _period(
      AppRoutes.movements,
      _display!.period.civilMonth,
    ),
    DiagnosticEntity.importBatch ||
    DiagnosticEntity.importRow => AppRoutes.importHistory,
  };

  Future<void> _open(
    String path, {
    DiagnosticEntity? entity,
    String? id,
    bool pending = false,
  }) async {
    if (_opening || _controller?.busy == true) return;
    _opening = true;
    final request = ++_openRequest;
    final navigationRevision = _session.navigationRevision;
    final saved = _display!;
    final focus = FocusManager.instance.primaryFocus;
    final route = ModalRoute.of(context);
    try {
      if (entity != null && id != null) {
        if (widget.exists == null) {
          path = _catalog(entity);
          pending = false;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'No se pudo comprobar la referencia. Revisa el catálogo.',
                ),
              ),
            );
          }
        } else if (!await widget.exists!(entity, id)) {
          path = _catalog(entity);
          pending = false;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'El registro ya no existe. Se abrirá el catálogo para revisar los datos.',
                ),
              ),
            );
          }
        }
      }
      if (!mounted ||
          request != _openRequest ||
          route?.isCurrent == false ||
          navigationRevision != _session.navigationRevision) {
        return;
      }
      await Navigator.of(context).pushNamed(
        path,
        arguments: pending
            ? PendingMovementOrigin(
                route: SessionLocation.encode(saved),
                label: 'Volver a Diagnóstico',
              )
            : null,
      );
      if (!mounted || request != _openRequest || route?.isCurrent != true) {
        return;
      }
      await _session.returnToOrigin(SecondaryNavigationContext(saved));
      await _controller?.validate(saved.period.civilMonth);
      if (focus?.context != null) focus!.requestFocus();
    } catch (_) {
      if (mounted && route?.isCurrent == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'No se pudo leer la referencia. Revisa Recuperación local.',
            ),
            action: SnackBarAction(
              label: 'Recuperación',
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRoutes.localBackups),
            ),
          ),
        );
      }
    } finally {
      _opening = false;
    }
  }

  Future<void> _record(DiagnosticEntity entity, String id, Month month) =>
      id.isEmpty && entity == DiagnosticEntity.budget
      ? _open(_period(AppRoutes.monthlyBudget, month))
      : _open(
          _period(switch (entity) {
            DiagnosticEntity.movement =>
              '${AppRoutes.movements}/${Uri.encodeComponent(id)}',
            DiagnosticEntity.budget =>
              '${AppRoutes.budget}/partidas/${Uri.encodeComponent(id)}',
            DiagnosticEntity.importRow =>
              '${AppRoutes.importRows}/${Uri.encodeComponent(id)}',
            _ => '${AppRoutes.accounts}/${Uri.encodeComponent(id)}',
          }, month),
          entity: entity,
          id: id,
        );

  Future<void> _action(DiagnosticAction action) => switch (action) {
    OpenLocalRecovery() => _open(AppRoutes.localBackups),
    OpenDiagnosticCatalog(:final entity) => _open(_catalog(entity)),
    OpenBudgetMonth(:final month, :final budgetId) => _record(
      DiagnosticEntity.budget,
      budgetId,
      month,
    ),
    // El ordinal se conserva en el detalle; el lote existente muestra sus filas.
    OpenImportBatch(:final batchId) => _open(
      '${AppRoutes.importBatches}/${Uri.encodeComponent(batchId)}',
      entity: DiagnosticEntity.importBatch,
      id: batchId,
    ),
    OpenPendingMovement(:final movementId) => _open(
      AppRoutes.pendingMovements,
      entity: DiagnosticEntity.movement,
      id: movementId,
      pending: true,
    ),
    OpenWealthPhoto(:final month) => _open(
      _period(AppRoutes.wealthPhoto, month),
    ),
    OpenIncomeBudget(:final year) => _open(
      _period(AppRoutes.monthlyBudget, Month(year, _display!.period.month)),
    ),
  };

  @override
  Widget build(BuildContext context) {
    if (_invalid) return SessionNavigationError(origin: _session.context);
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        if (ModalRoute.of(context)?.isCurrent != false &&
            _session.context.destination == SessionDestination.diagnostics) {
          if (_display!.period != _session.period) {
            _controller?.invalidate(notify: false);
          }
          _display = _session.context;
        }
        final c = _controller;
        Widget shell(Widget body) => PrimaryNavigation(
          session: _session,
          title: 'Diagnóstico de coherencia',
          selectedDestination: widget.selectedDestination,
          scrollController: _scroll,
          contextTrail: Text(
            'Toda la base local · fotos e indicador: ${_display!.period}',
          ),
          beforeNavigate: () async {
            c?.cancel();
            return true;
          },
          child: body,
        );
        if (c == null) {
          return shell(
            const Text(
              'Diagnóstico no disponible. No se ha inicializado el almacenamiento local.',
            ),
          );
        }
        return ListenableBuilder(
          listenable: c,
          builder: (context, _) => shell(
            DiagnosticScreen(
              controller: c,
              month: _display!.period.civilMonth,
              onAction: _action,
              onRecord: _record,
            ),
          ),
        );
      },
    );
  }
}
