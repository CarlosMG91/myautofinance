import 'package:flutter/material.dart';

import 'navigation_context.dart';
import 'session_location.dart';

class SessionNavigationError extends StatelessWidget {
  const SessionNavigationError({super.key, required this.origin});
  final NavigationContext origin;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Error de navegación')),
    body: SafeArea(
      child: SingleChildScrollView(
        child: Column(
          children: [
            const Text('Periodo o destino de navegación inválido.'),
            TextButton(
              onPressed: () {
                final navigator = Navigator.of(context);
                if (navigator.canPop()) {
                  navigator.pop();
                } else {
                  navigator.pushReplacementNamed(
                    SessionLocation.encode(origin),
                    arguments: origin,
                  );
                }
              },
              child: const Text('Volver al origen'),
            ),
          ],
        ),
      ),
    ),
  );
}
