import 'package:flutter/material.dart';

import 'app_routes.dart';

/// Navegación de desarrollo, sin pantallas ni operaciones financieras.
abstract final class AppRouter {
  static Route<void> generateRoute(RouteSettings settings) {
    Widget page;
    if (settings.name == AppRoutes.home) {
      page = const _TechnicalIndex();
    } else {
      TechnicalDestination? destination;
      for (final candidate in AppRoutes.destinations) {
        if (candidate.path == settings.name) {
          destination = candidate;
          break;
        }
      }
      page = _TechnicalPlaceholder(
        title: destination?.label ?? 'Error de navegación',
        message: destination == null
            ? 'Destino desconocido · ${settings.name ?? "(sin ruta)"}'
            : 'Marcador técnico · ${destination.path}',
      );
    }
    // Conserva nombre y argumentos, también en destinos desconocidos.
    return MaterialPageRoute<void>(settings: settings, builder: (_) => page);
  }
}

class _TechnicalIndex extends StatelessWidget {
  const _TechnicalIndex();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Autofinance · Base técnica')),
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
  const _TechnicalPlaceholder({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
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
