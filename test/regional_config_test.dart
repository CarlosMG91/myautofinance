import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/bootstrap.dart';
import 'package:myautofinance/app/regional.dart';
import 'package:myautofinance/core/config/app_config.dart';

void main() {
  test('Formato sintético EUR con separadores españoles y céntimos', () {
    expect(AppRegional.currency, 'EUR');
    expect(AppRegional.formatEuro(1234.56), '1.234,56\u00a0€');
    expect(AppRegional.formatEuro(-1234.56), '-1.234,56\u00a0€');
    expect(AppRegional.formatEuro(0), '0,00\u00a0€');
    expect(() => AppRegional.formatEuro(double.nan), throwsArgumentError);
    expect(() => AppRegional.formatEuro(double.infinity), throwsArgumentError);
  });

  test('Entornos públicos permitidos y valor predeterminado seguro', () {
    expect(AppConfig.fromEnvironment().environment, AppEnvironment.production);
    for (final environment in AppEnvironment.values) {
      expect(AppConfig.parse(environment.name).environment, environment);
    }
    for (final value in ['', 'Production', 'unknown']) {
      expect(() => AppConfig.parse(value), throwsFormatException);
    }
  });

  testWidgets('El arranque conserva la configuración y fuerza es-ES', (
    tester,
  ) async {
    final app = await initializeApp(
      initializeLocal: () async => null,
      initialize: () async => const AppConfig(environment: AppEnvironment.test),
    );
    expect((app as AutofinanceApp).config.environment, AppEnvironment.test);
    tester.binding.platformDispatcher.localeTestValue = const Locale(
      'en',
      'US',
    );
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Scaffold).first);
    expect(Localizations.localeOf(context), const Locale('es', 'ES'));
    expect(MaterialLocalizations.of(context).cancelButtonLabel, 'Cancelar');
    expect(tester.takeException(), isNull);
  });

  for (final asynchronous in [false, true]) {
    testWidgets('Fallo de inicialización controlado (async=$asynchronous)', (
      tester,
    ) async {
      final app = await initializeApp(
        initialize: () {
          if (asynchronous) {
            return Future<AppConfig>.error(StateError('detalle privado'));
          }
          throw StateError('detalle privado');
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      expect(find.text(StartupFailureApp.message), findsOneWidget);
      expect(find.textContaining('detalle privado'), findsNothing);
      expect(
        Localizations.localeOf(tester.element(find.byType(Scaffold))),
        const Locale('es', 'ES'),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Configuración inválida usa el mismo fallo técnico', (
    tester,
  ) async {
    await tester.pumpWidget(
      await initializeApp(initialize: () async => AppConfig.parse('invalid')),
    );
    await tester.pumpAndSettle();
    expect(find.text(StartupFailureApp.message), findsOneWidget);
  });
}
