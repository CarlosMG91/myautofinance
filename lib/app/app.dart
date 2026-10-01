import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import 'regional.dart';

import 'modules.dart';
import 'navigation/app_router.dart';
import 'navigation/app_routes.dart';

class AutofinanceApp extends StatelessWidget {
  const AutofinanceApp({
    super.key,
    this.config = const AppConfig(environment: AppEnvironment.production),
  });

  final AppConfig config;

  /// Entradas técnicas disponibles para conectar las futuras funcionalidades.
  static const modules = applicationModules;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Autofinance',
      locale: AppRegional.locale,
      supportedLocales: AppRegional.supportedLocales,
      localizationsDelegates: AppRegional.delegates,
      initialRoute: AppRoutes.home,
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}
