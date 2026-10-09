import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/app/navigation/app_routes.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  late Directory directory;
  late LocalBackupSession session;
  late String accountId;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wealth-navigation-');
    session = LocalBackupSession(supportDirectory: () async => directory);
    expect(await session.open(), isTrue);
    final management = await session.wealth();
    final account = await management.accounts.create(
      name: 'Cuenta cerrada sintética',
      kind: AccountKind.account,
      activeFrom: Month(2026, 1),
      liquidity: Liquidity.liquid,
    );
    accountId = account.id;
    await management.photos.setValue(Month(2026, 1), account.id, 0);
    await management.accounts.close(account.id, Month(2026, 1));
  });
  tearDown(() async {
    await session.store.close();
    session.controller.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'Gestión abre catálogo SQLite, detalle cerrado y devuelve al origen',
    (tester) async {
      await tester.pumpWidget(AutofinanceApp(localSession: session));
      await tester.tap(find.text('Gestión'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fichas'));
      await settle(tester);
      await tester.tap(find.text('Cuenta cerrada sintética'));
      await settle(tester);
      expect(find.text('Baja: 2026-01-01'), findsOneWidget);
      final context = tester.element(find.text('Baja: 2026-01-01'));
      expect(
        ModalRoute.of(context)!.settings.name,
        '${AppRoutes.accounts}/$accountId',
      );
      await tester.tap(find.text('Volver al origen'));
      await settle(tester);
      expect(find.text('Cuenta cerrada sintética'), findsOneWidget);
      await tester.tap(find.text('Volver al origen'));
      await tester.pumpAndSettle();
      expect(find.text('Marcador técnico · /estado'), findsOneWidget);
    },
  );

  testWidgets(
    'Foto y patrimonio leen el periodo; errores no escriben ni muestran ceros',
    (tester) async {
      await tester.pumpWidget(AutofinanceApp(localSession: session));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      final db = (await tester.runAsync(session.store.open))!;
      final revision = (await tester.runAsync(db.readState))!.revision;
      for (final path in [AppRoutes.wealth, AppRoutes.wealthPhoto]) {
        navigator.pushNamed('$path?a=2026&m=01');
        await settle(tester);
        expect(find.text('Foto completa'), findsOneWidget);
        await tester.tap(find.text('Volver al origen'));
        await tester.pumpAndSettle();
      }
      for (final path in [
        '/patrimonio/foto?a=2026&m=99',
        '/patrimonio/fichas/inexistente',
      ]) {
        navigator.pushNamed(path);
        await settle(tester);
        expect(find.text('No se pudo abrir este detalle'), findsOneWidget);
        expect(find.text('Foto completa'), findsNothing);
        await tester.tap(find.text('Volver al origen'));
        await tester.pumpAndSettle();
      }
      expect((await tester.runAsync(db.readState))!.revision, revision);
    },
  );
}
