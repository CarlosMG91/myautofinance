import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_routes.dart';
import '../../features/synchronization/presentation/local_backup_controller.dart';
import '../../features/synchronization/presentation/local_backup_screen.dart';

/// Navegación de desarrollo, sin pantallas ni operaciones financieras.
abstract final class AppRouter {
  static Route<void> generateRoute(
    RouteSettings settings, {
    LocalBackupController? localBackups,
  }) {
    Widget page;
    final uri = Uri.tryParse(settings.name ?? '');
    if (uri?.path == AppRoutes.localBackups ||
        uri?.path.startsWith('${AppRoutes.localBackups}/') == true) {
      page = localBackups == null
          ? const _TechnicalPlaceholder(
              title: 'Copias locales no disponibles',
              message: 'No se ha inicializado el almacenamiento local.',
            )
          : _BackupRoute(settings: settings, controller: localBackups);
    } else if (settings.name == AppRoutes.home) {
      page = _TechnicalIndex(showManagement: localBackups != null);
    } else {
      TechnicalDestination? destination;
      for (final candidate in AppRoutes.destinations) {
        if (candidate.path == uri?.path) {
          destination = candidate;
          break;
        }
      }
      page = _TechnicalPlaceholder(
        showManagement: localBackups != null,
        title: destination?.label ?? 'Error de navegación',
        message: destination == null
            ? 'Destino desconocido · ${settings.name ?? "(sin ruta)"}'
            : 'Marcador técnico · ${destination.path}',
      );
    }
    // Conserva nombre y argumentos, también en destinos desconocidos.
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (context) {
        if (page is _BackupRoute || localBackups == null) return page;
        return ListenableBuilder(
          listenable: localBackups,
          builder: (context, _) {
            if (!localBackups.activeAvailable) {
              return _BackupRoute(
                settings: const RouteSettings(name: AppRoutes.localBackups),
                controller: localBackups,
              );
            }
            return page;
          },
        );
      },
    );
  }
}

/// La ruta original queda en la pila: conserva periodo, scroll y foco.
class _BackupOrigin {
  const _BackupOrigin(this.route);
  final String route;
  String get label {
    final uri = Uri.tryParse(route);
    final path = uri?.path;
    for (final destination in AppRoutes.destinations) {
      if (destination.path == path) {
        final year = int.tryParse(uri?.queryParameters['a'] ?? '');
        final month = int.tryParse(uri?.queryParameters['m'] ?? '');
        if (year != null && year >= 1 && year <= 9999) {
          if (month != null && month >= 1 && month <= 12) {
            return '${destination.label}, ${DateFormat("MMMM 'de' yyyy", 'es_ES').format(DateTime(year, month))}';
          }
          return '${destination.label}, $year';
        }
        return destination.label;
      }
    }
    return 'Autofinance';
  }
}

class _BackupRoute extends StatelessWidget {
  const _BackupRoute({required this.settings, required this.controller});
  final RouteSettings settings;
  final LocalBackupController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final uri = Uri.tryParse(settings.name ?? '');
      final id = uri != null && uri.pathSegments.length == 2
          ? uri.pathSegments.last
          : null;
      final origin = settings.arguments is _BackupOrigin
          ? settings.arguments! as _BackupOrigin
          : const _BackupOrigin(AppRoutes.monthlyStatus);
      void returnToOrigin() {
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
        } else {
          navigator.pushReplacementNamed(origin.route);
        }
      }

      final width = MediaQuery.sizeOf(context).width;
      // Solo las rutas técnicas existentes; no se implementa contenido financiero.
      Widget destinationButton(TechnicalDestination destination) {
        final selected = Uri.tryParse(origin.route)?.path == destination.path;
        return Semantics(
          selected: selected,
          child: TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              backgroundColor: selected ? const Color(0xffeaf3fb) : null,
              side: selected
                  ? const BorderSide(color: Color(0xff124b7a), width: 2)
                  : null,
            ),
            onPressed: () =>
                Navigator.of(context)
                    .pushNamedAndRemoveUntil(destination.path, (_) => false),
            child: Text(
              _shortLabel(destination.path),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      }

      Widget navigation(bool vertical) {
        if (!vertical && width < 600) {
          final columns = MediaQuery.textScalerOf(context).scale(14) > 20
              ? 2
              : 3;
          return Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            children: [
              for (final destination in AppRoutes.destinations)
                SizedBox(
                  width: (width - 16) / columns,
                  child: destinationButton(destination),
                ),
            ],
          );
        }
        return Flex(
          direction: vertical ? Axis.vertical : Axis.horizontal,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final destination in AppRoutes.destinations)
              if (vertical)
                destinationButton(destination)
              else
                Expanded(child: destinationButton(destination)),
          ],
        );
      }

      return LocalBackupScreen(
        controller: controller,
        backupId: id,
        onOpenDetail: (id) =>
            Navigator.of(context)
                .pushNamed('${AppRoutes.localBackups}/$id', arguments: origin),
        onReturn: returnToOrigin,
        returnLabel: id == null
            ? 'Volver a ${origin.label}'
            : 'Volver a Copias locales',
        navigation: controller.activeAvailable && width >= 840
            ? Container(
                width: width >= 1200 ? 216 : 200,
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [const Text('Autofinance'), navigation(true)],
                ),
              )
            : null,
        bottomNavigation: controller.activeAvailable && width < 840
            ? SafeArea(
                child: Container(
                  color: Colors.white,
                  constraints: const BoxConstraints(minHeight: 64),
                  child: navigation(false),
                ),
              )
            : null,
      );
    },
  );

  String _shortLabel(String path) => switch (path) {
    AppRoutes.monthlyStatus => 'Estado',
    AppRoutes.wealth => 'Patrimonio',
    AppRoutes.budget => 'Presupuesto',
    AppRoutes.actualSpending => 'Real',
    _ => 'Indicadores',
  };
}

class _TechnicalIndex extends StatelessWidget {
  const _TechnicalIndex({this.showManagement = false});
  final bool showManagement;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Autofinance · Base técnica'),
        actions: [if (showManagement) const _ManagementMenu()],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Navegación de desarrollo · Diseño pendiente'),
              for (final destination in AppRoutes.destinations)
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pushNamed(destination.path),
                  child: Text('${destination.label} · ${destination.path}'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TechnicalPlaceholder extends StatelessWidget {
  const _TechnicalPlaceholder({
    required this.title,
    required this.message,
    this.showManagement = false,
  });
  final bool showManagement;

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [if (showManagement) const _ManagementMenu()],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const Text('Sin contenido de producto · Diseño pendiente'),
            TextButton(
              onPressed: () {
                final navigator = Navigator.of(context);
                if (navigator.canPop()) {
                  navigator.pop();
                } else {
                  navigator.pushReplacementNamed(AppRoutes.home);
                }
              },
              child: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManagementMenu extends StatelessWidget {
  const _ManagementMenu();
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Gestión',
    onSelected: (_) => Navigator.of(context).pushNamed(
      AppRoutes.localBackups,
      arguments: _BackupOrigin(
        ModalRoute.of(context)?.settings.name ?? AppRoutes.home,
      ),
    ),
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'local', child: Text('Copias locales')),
    ],
    child: const Padding(padding: EdgeInsets.all(12), child: Text('Gestión')),
  );
}
