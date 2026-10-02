import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';
import 'regional.dart';

import 'modules.dart';
import 'navigation/app_router.dart';
import 'navigation/app_routes.dart';
import 'local_backup_session.dart';
import '../features/synchronization/presentation/local_backup_controller.dart';

class AutofinanceApp extends StatelessWidget {
  const AutofinanceApp({
    super.key,
    this.config = const AppConfig(environment: AppEnvironment.production),
    this.localSession,
    this.localBackups,
  });

  final AppConfig config;
  final LocalBackupSession? localSession;

  /// Permite probar navegación sin abrir archivos ni servicios nativos.
  final LocalBackupController? localBackups;

  /// Entradas técnicas disponibles para conectar las futuras funcionalidades.
  static const modules = applicationModules;

  @override
  Widget build(BuildContext context) {
    final backups = localBackups ?? localSession?.controller;
    return MaterialApp(
      title: 'Autofinance',
      locale: AppRegional.locale,
      supportedLocales: AppRegional.supportedLocales,
      localizationsDelegates: AppRegional.delegates,
      theme: ThemeData(
        fontFamily: defaultTargetPlatform == TargetPlatform.windows
            ? 'Segoe UI'
            : 'Roboto',
        scaffoldBackgroundColor: const Color(0xfff5f7fa),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff124b7a))
            .copyWith(
              primary: const Color(0xff124b7a),
              surface: Colors.white,
              onSurface: const Color(0xff17212b),
              error: const Color(0xff9f2733),
            ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 16, height: 1.4),
          titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      // Evita una ruta de datos por debajo de la recuperación de arranque.
      onGenerateInitialRoutes: (_) => [
        AppRouter.generateRoute(
          RouteSettings(
            name: backups != null && !backups.activeAvailable
                ? AppRoutes.localBackups
                : AppRoutes.home,
          ),
          localBackups: backups,
        ),
      ],
      onGenerateRoute: (settings) =>
          AppRouter.generateRoute(settings, localBackups: backups),
    );
  }
}
