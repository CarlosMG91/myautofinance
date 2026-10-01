enum AppEnvironment { development, test, production }

/// Solo ajustes públicos. Los dart-defines quedan incluidos en el binario.
class AppConfig {
  const AppConfig({required this.environment});

  final AppEnvironment environment;

  factory AppConfig.fromEnvironment() => AppConfig.parse(
    const String.fromEnvironment('APP_ENV', defaultValue: 'production'),
  );

  factory AppConfig.parse(String value) {
    for (final environment in AppEnvironment.values) {
      if (environment.name == value) {
        return AppConfig(environment: environment);
      }
    }
    // No reproducir el valor recibido: puede contener información privada.
    throw const FormatException('APP_ENV no válido');
  }
}
