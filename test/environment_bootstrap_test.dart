import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/bootstrap.dart';
import 'package:myautofinance/core/config/app_config.dart';
import 'package:myautofinance/main.dart' as entrypoint;

// Ejecutar este archivo por separado con cada --dart-define=APP_ENV.
// Los resultados esperados son el contrato público, sin usar el parser bajo prueba.
const _expected = <String, AppEnvironment>{
  'development': AppEnvironment.development,
  'test': AppEnvironment.test,
  'production': AppEnvironment.production,
};
const _environment = String.fromEnvironment(
  'APP_ENV',
  defaultValue: 'production',
);

void main() {
  testWidgets('APP_ENV compilado llega a main o al fallo seguro', (
    tester,
  ) async {
    await entrypoint.main();
    await tester.pumpAndSettle();

    final expected = _expected[_environment];
    if (expected != null) {
      expect(find.text('Autofinance · Base técnica'), findsOneWidget);
      expect(
        tester
            .widget<AutofinanceApp>(find.byType(AutofinanceApp))
            .config
            .environment,
        expected,
      );
      expect(find.byType(StartupFailureApp), findsNothing);
    } else {
      expect(find.text(StartupFailureApp.message), findsOneWidget);
      expect(find.byType(AutofinanceApp), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(find.textContaining(_environment), findsNothing);
    }
    final context = tester.element(find.byType(Scaffold));
    expect(Localizations.localeOf(context), const Locale('es', 'ES'));
    expect(MaterialLocalizations.of(context).cancelButtonLabel, 'Cancelar');
    expect(tester.takeException(), isNull);
  });
}
