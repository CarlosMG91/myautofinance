import 'package:flutter/material.dart';

import 'modules.dart';
import 'navigation/app_router.dart';
import 'navigation/app_routes.dart';

class AutofinanceApp extends StatelessWidget {
  const AutofinanceApp({super.key});

  /// Entradas técnicas disponibles para conectar las futuras funcionalidades.
  static const modules = applicationModules;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Autofinance',
      initialRoute: AppRoutes.home,
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}
