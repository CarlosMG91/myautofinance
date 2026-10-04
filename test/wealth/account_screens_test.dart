import 'dart:async';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/local_database_store.dart';
import 'package:myautofinance/app/wealth_management_factory.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:myautofinance/features/wealth/presentation/account_catalog_screen.dart';
import 'package:myautofinance/features/wealth/presentation/account_form_screen.dart';

void main() {
  late LocalDatabase db;
  late WealthManagement service;
  late Directory directory;
  late LocalDatabaseStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('account-screens-');
    store = LocalDatabaseStore(supportDirectory: () async => directory);
    db = await store.open();
    service = createWealthManagement(database: db);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 150; i++) {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump(const Duration(milliseconds: 20));
      if (i >= 30 && find.byType(LinearProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final target = find.text(text).last;
    await tester.ensureVisible(target);
    await tester.runAsync(() => tester.tap(target));
    await tester.pump();
  }

  testWidgets(
    'Crear deuda valida mes, espera persistencia y descarta liquidez',
    (tester) async {
      final pending = Completer<WealthManagement>();
      AccountDetails? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: AccountFormScreen(
            loadManagement: () => pending.future,
            initialMonth: Month(2026, 1),
            onReturn: () {},
            onSaved: (result) => saved = result,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'Guardar');
      expect(
        tester.widget<TextField>(field('Nombre')).focusNode!.hasFocus,
        isTrue,
      );
      await tester.enterText(field('Nombre'), 'Deuda sintética');
      await tester.tap(find.byType(DropdownButtonFormField<AccountKind>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deuda').last);
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<Liquidity>), findsNothing);
      await tester.enterText(field('Mes de baja (opcional)'), '2025-12');
      await tap(tester, 'Guardar');
      expect(find.text('La baja no puede preceder al alta.'), findsWidgets);
      expect(
        tester
            .widget<TextField>(field('Mes de baja (opcional)'))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await tester.enterText(field('Mes de baja (opcional)'), '2026-01');
      await tap(tester, 'Guardar');
      expect(saved, isNull);
      expect(find.text('Guardando…'), findsOneWidget);
      await tester.runAsync(() async {
        pending.complete(service);
      });
      await settle(tester);
      expect(saved!.account.kind, AccountKind.debt);
      expect(saved!.history, isEmpty);
      expect(
        (await tester.runAsync(service.catalog))!.single.id,
        saved!.account.id,
      );
    },
  );
  testWidgets('Escape y cancelar conservador; descarte no escribe', (
    tester,
  ) async {
    var returned = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountFormScreen(
          loadManagement: () async => service,
          initialMonth: Month(2026, 1),
          onReturn: () => returned = true,
          onSaved: (_) => fail('No guardar'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(field('Nombre'), 'Borrador');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Hay cambios sin guardar'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(returned, isFalse);
    expect(
      tester.widget<TextField>(field('Nombre')).controller!.text,
      'Borrador',
    );
    await tap(tester, 'Cancelar');
    await tester.pumpAndSettle();
    await tap(tester, 'Descartar cambios');
    await settle(tester);
    expect(returned, isTrue);
    expect(await tester.runAsync(service.catalog), isEmpty);
  });
  testWidgets(
    'Gestión: baja incompatible conserva borrador y foto, éxito vuelve al catálogo',
    (tester) async {
      final account = (await tester.runAsync(
        () => service.create(
          name: 'Cuenta sintética',
          kind: AccountKind.account,
          activeFrom: Month(2026, 1),
          liquidity: Liquidity.liquid,
        ),
      ))!;
      await tester.runAsync(
        () => service.photos.setValue(Month(2026, 3), account.account.id, 100),
      );
      await tester.pumpWidget(AutofinanceApp(wealth: () async => service));
      await tap(tester, 'Gestión');
      await tester.pumpAndSettle();
      await tap(tester, 'Fichas');
      await settle(tester);
      await tap(tester, 'Cuenta sintética');
      await settle(tester);
      await tap(tester, 'Editar ficha');
      expect(find.byType(DropdownButtonFormField<AccountKind>), findsNothing);
      expect(tester.widget<TextField>(field('Mes de alta')).enabled, isFalse);
      await tester.enterText(field('Nombre'), 'Nuevo nombre');
      await tester.enterText(field('Mes de baja (opcional)'), '2026-02');
      await tap(tester, 'Guardar');
      await tester.pumpAndSettle();
      await tap(tester, 'Guardar baja');
      await settle(tester);
      expect(
        find.text('La baja dejaría fotos fuera de vigencia.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(field('Nombre')).controller!.text,
        'Nuevo nombre',
      );
      expect(
        (await tester.runAsync(() => service.details(account.account.id)))!
            .account
            .name,
        'Cuenta sintética',
      );
      await tester.enterText(field('Mes de baja (opcional)'), '2026-03');
      await tap(tester, 'Guardar');
      await tester.pumpAndSettle();
      await tap(tester, 'Guardar baja');
      await settle(tester);
      expect(find.byType(AccountCatalogScreen), findsOneWidget);
      expect(find.text('Ficha guardada'), findsOneWidget);
      await tap(tester, 'Nuevo nombre');
      await settle(tester);
      expect(find.text('Baja: 2026-03-01'), findsOneWidget);
    },
  );
  testWidgets(
    'Tarjetas/tablas y formulario operables a 320, 840 y 1440 con texto 200 %',
    (tester) async {
      await tester.runAsync(
        () => service.create(
          name: 'Cartera sintética de nombre largo',
          kind: AccountKind.portfolio,
          activeFrom: Month(2026, 1),
          liquidity: Liquidity.medium,
        ),
      );
      for (final width in [320.0, 840.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: AccountCatalogScreen(
              controller: WealthController(loadManagement: () async => service),
              onOpen: (_) async {},
              onReturn: () {},
            ),
          ),
        );
        await settle(tester);
        expect(
          find.byType(Table),
          width >= 840 ? findsOneWidget : findsNothing,
        );
        expect(find.byType(Card), width < 840 ? findsOneWidget : findsNothing);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: AccountFormScreen(
              loadManagement: () async => service,
              initialMonth: Month(2026, 1),
              onSaved: (_) {},
              onReturn: () {},
            ),
          ),
        );
        await settle(tester);
        await tester.ensureVisible(find.text('Guardar'));
        expect(tester.takeException(), isNull);
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
