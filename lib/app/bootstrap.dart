import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import 'app.dart';
import 'regional.dart';

typedef AppInitializer = Future<AppConfig> Function();

/// Punto único para incorporar las futuras inicializaciones esperadas.
Future<Widget> initializeApp({AppInitializer? initialize}) async {
  try {
    final config = await (initialize ?? _initialize)();
    return AutofinanceApp(config: config);
  } catch (_) {
    return const StartupFailureApp();
  }
}

Future<AppConfig> _initialize() async => AppConfig.fromEnvironment();

class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key});

  static const message =
      'No se pudo iniciar Autofinance. Código técnico: INIT-001. '
      'Revisa la configuración y reinicia la aplicación.';

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Autofinance',
    locale: AppRegional.locale,
    supportedLocales: AppRegional.supportedLocales,
    localizationsDelegates: AppRegional.delegates,
    home: const Scaffold(body: Center(child: Text(message))),
  );
}
