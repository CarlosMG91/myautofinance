import 'package:flutter/material.dart';

import '../../features/importing/importing.dart';
import '../../features/importing/presentation/import_controller.dart';
import '../../features/importing/presentation/import_history_screen.dart';
import '../../features/importing/presentation/import_review_screen.dart';
import 'app_routes.dart';
import 'pending_movement_route.dart';
import '../../features/movements/movements.dart';
import '../../features/movements/presentation/pending_movement_controller.dart';
import 'movement_list_route.dart';
import '../csv_import_factory.dart';

/// Entrada del recorrido de pruebas. Ningún selector de producción la genera.
class ImportReviewLaunch {
  const ImportReviewLaunch({
    required this.file,
    required this.adapter,
    this.origin = AppRoutes.monthlyStatus,
  });
  final ImportFile file;
  final ImportAdapter adapter;
  final String origin;
}

class CsvImportOrigin {
  const CsvImportOrigin(this.route, this.returnLabel);
  final String route, returnLabel;
}

class ImportRoute extends StatefulWidget {
  const ImportRoute({
    super.key,
    required this.settings,
    required this.load,
    this.allowTestLaunch = false,
    this.csvSelector,
    this.pendingMovements,
  });
  final RouteSettings settings;
  final ImportServicesLoader load;
  final bool allowTestLaunch;
  final LocalCsvSelector? csvSelector;
  final PendingMovementLoader? pendingMovements;
  @override
  State<ImportRoute> createState() => _ImportRouteState();
}

class _ImportRouteState extends State<ImportRoute> {
  ImportController? _controller;
  @override
  void initState() {
    super.initState();
    if (Uri.parse(widget.settings.name!).path == AppRoutes.importCsv) {
      _controller = createCsvImportController(
        widget.load,
        selector: widget.csvSelector,
      );
    }
    if (Uri.parse(widget.settings.name!).path == AppRoutes.importReview &&
        widget.allowTestLaunch &&
        widget.settings.arguments is ImportReviewLaunch) {
      final launch = widget.settings.arguments as ImportReviewLaunch;
      _controller = ImportController(widget.load)
        ..start(launch.file, launch.adapter);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _back() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uri = Uri.parse(widget.settings.name!);
    final navigator = Navigator.of(context);
    Future<void> batch(String id) async {
      await navigator.pushNamed(
        '${AppRoutes.importBatches}/${Uri.encodeComponent(id)}',
      );
    }

    Future<void> pending(String id) async {
      await navigator.pushNamed(
        Uri(
          path: AppRoutes.pendingMovements,
          queryParameters: {"lote": id},
        ).toString(),
        arguments: PendingMovementOrigin(
          route: widget.settings.name!,
          label: "Volver al ${_controller != null ? 'resultado' : 'lote'}",
        ),
      );
    }

    Future<int> count(String id) async {
      final source = await widget.pendingMovements!();
      final page = await source.management.readPage(
        query: PendingMovementQuery(batchId: id),
        limit: 1,
      );
      return page.totalCount;
    }

    if (_controller != null) {
      final args = widget.settings.arguments;
      final origin = args is ImportReviewLaunch
          ? args.origin
          : args is CsvImportOrigin
          ? args.route
          : AppRoutes.home;
      final returnLabel = args is CsvImportOrigin
          ? args.returnLabel
          : 'Volver a ${MovementListOrigin(origin).label}';
      return ImportReviewScreen(
        controller: _controller!,
        onReturn: () {
          if (navigator.canPop()) {
            navigator.pop();
          } else {
            navigator.pushReplacementNamed(origin);
          }
        },
        returnLabel: returnLabel,
        onHistory: () => navigator.pushNamed(AppRoutes.importHistory),
        onBatch: batch,
        onPending: widget.pendingMovements == null ? null : pending,
        pendingCount: widget.pendingMovements == null ? null : count,
        onPeriod: (label, period) => navigator.pushNamed(
          '${switch (label) {
            'Estado' => AppRoutes.monthlyStatus,
            'Presupuesto' => AppRoutes.budget,
            _ => AppRoutes.actualSpending,
          }}?a=${period.substring(0, 4)}&m=${period.substring(5, 7)}',
        ),
      );
    }
    final parts = uri.pathSegments;
    if (uri.path == AppRoutes.importHistory ||
        (parts.length == 3 &&
            parts.first == 'importaciones' &&
            (parts[1] == 'lotes' || parts[1] == 'origen'))) {
      return ImportHistoryScreen(
        load: widget.load,
        onReturn: _back,
        batchId: parts.length == 3 && parts[1] == 'lotes' ? parts.last : null,
        rowId: parts.length == 3 && parts[1] == 'origen' ? parts.last : null,
        onBatch: batch,
        onPending: widget.pendingMovements == null ? null : pending,
        pendingCount: widget.pendingMovements == null ? null : count,
        onRow: (id) => navigator.pushNamed(
          '${AppRoutes.importRows}/${Uri.encodeComponent(id)}',
        ),
        onRecord: (row) async {
          final path = row.currentMovement != null
              ? '${AppRoutes.movements}/${Uri.encodeComponent(row.currentMovement!.id)}?a=${row.currentMovement!.data.valueDate.value.substring(0, 4)}&m=${row.currentMovement!.data.valueDate.value.substring(5, 7)}'
              : '${AppRoutes.budget}/partidas/${Uri.encodeComponent(row.currentBudget!.id)}?a=${row.currentBudget!.data.month.value.substring(0, 4)}&m=${row.currentBudget!.data.month.value.substring(5, 7)}';
          await navigator.pushNamed(path);
        },
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Importación')),
      body: SafeArea(
        child: Column(
          children: [
            const Text(
              'La selección y lectura de CSV/XLS estará disponible cuando se integren sus lectores.',
            ),
            TextButton(
              onPressed: () => navigator.pushNamed(AppRoutes.importHistory),
              child: const Text('Historial de lotes'),
            ),
            TextButton(onPressed: _back, child: const Text('Volver')),
          ],
        ),
      ),
    );
  }
}
