import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import 'app.dart';
import 'regional.dart';
import 'local_backup_session.dart';

typedef AppInitializer = Future<AppConfig> Function();
typedef LocalSessionInitializer = Future<LocalBackupSession?> Function();

/// Punto único para incorporar las futuras inicializaciones esperadas.
Future<Widget> initializeApp({
  AppInitializer? initialize,
  LocalSessionInitializer? initializeLocal,
}) async {
  try {
    final config = await (initialize ?? _initialize)();
    final session = await (initializeLocal ?? _initializeLocal)();
    return AutofinanceApp(config: config, localSession: session);
  } catch (_) {
    return const StartupFailureApp();
  }
}

Future<AppConfig> _initialize() async => AppConfig.fromEnvironment();

Future<LocalBackupSession> _initializeLocal() async {
  final session = LocalBackupSession();
  await session.open();
  return session;
}

class StartupLoadingApp extends StatelessWidget {
  const StartupLoadingApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Autofinance',
    locale: AppRegional.locale,
    supportedLocales: AppRegional.supportedLocales,
    localizationsDelegates: AppRegional.delegates,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: const Text(
                  'Comprobando recuperación y abriendo base local… No cierre la app.',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

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
