import 'package:flutter/material.dart';

import 'modules.dart';

class AutofinanceApp extends StatelessWidget {
  const AutofinanceApp({super.key});

  /// Entradas técnicas disponibles para conectar las futuras funcionalidades.
  static const modules = applicationModules;

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Autofinance',
      home: Scaffold(
        body: SafeArea(
          child: Center(child: Text('Autofinance · Base técnica')),
        ),
      ),
    );
  }
}
