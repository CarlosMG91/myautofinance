import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/main.dart';
import 'package:myautofinance/main.dart' as entrypoint;
import 'package:myautofinance/core/config/app_config.dart';

void main() {
  testWidgets('main permite probar el arranque con almacenamiento inyectado', (
    tester,
  ) async {
    await entrypoint.main(initializeLocal: () async => null);
    await tester.pumpAndSettle();

    expect(find.text('Marcador técnico · /estado'), findsOneWidget);
    expect(
      tester
          .widget<AutofinanceApp>(find.byType(AutofinanceApp))
          .config
          .environment,
      AppEnvironment.production,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arranca con Estado técnico de Autofinance', (tester) async {
    await tester.pumpWidget(const AutofinanceApp());

    expect(find.text('Marcador técnico · /estado'), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'Autofinance',
    );
    expect(tester.takeException(), isNull);
  });
}
