import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/wealth_management_factory.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:myautofinance/features/wealth/presentation/wealth_screen.dart';

void main() {
  late LocalDatabase database;
  late WealthManagement management;
  late WealthController controller;
  late AccountRecord account, debt;
  final january = Month(2026, 1), february = Month(2026, 2);
  setUpAll(() => initializeDateFormatting('es_ES'));
  setUp(() async {
    database = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    management = createWealthManagement(database: database);
    controller = WealthController(loadManagement: () async => management);
    account = await management.accounts.create(
      name: 'Cuenta sintética',
      kind: AccountKind.account,
      activeFrom: january,
      liquidity: Liquidity.liquid,
    );
    debt = await management.accounts.create(
      name: 'Deuda sintética',
      kind: AccountKind.debt,
      activeFrom: january,
    );
    await management.photos.setValue(january, account.id, 600000);
    await management.photos.setValue(january, debt.id, 500000);
  });
  tearDown(() => database.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump(const Duration(milliseconds: 20));
      if (i > 3 && find.byType(LinearProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final target = find.text(text).last;
    await tester.ensureVisible(target);
    await tester.tap(target);
    await settle(tester);
  }

  Widget screen({
    double textScale = 1,
    WealthController? reading,
    Month? month,
    Future<void> Function(Month)? photo,
    Future<void> Function(Month)? catalog,
  }) => MaterialApp(
    theme: ThemeData(
      fontFamily: Platform.environment.containsKey('CAPTURE_WEALTH')
          ? 'WealthCapture'
          : null,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff124b7a)),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 16, height: 1.4),
      ),
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: WealthScreen(
      controller: reading ?? controller,
      initialMonth: month ?? january,
      onPhoto: photo ?? (_) async {},
      onCatalog: catalog ?? (_) async {},
      onAccount: (_, _) async {},
      management: (_, _) => const Text('Gestión'),
      destinations: const {
        '/estado': 'Estado',
        '/patrimonio': 'Patrimonio',
        '/presupuesto': 'Presupuesto',
        '/real': 'Real',
        '/indicadores': 'Indicadores',
      },
      onNavigate: (_, _) {},
    ),
  );

  testWidgets(
    'Doce fotos independientes, parcial sin totales y año recordado',
    (tester) async {
      await tester.runAsync(
        () => management.photos.setValue(february, account.id, 620000),
      );
      await tester.pumpWidget(screen());
      await settle(tester);
      expect(find.textContaining('Patrimonio neto: 1.000,00'), findsOneWidget);
      await tap(tester, 'Las doce fotos de 2026 · sin suma anual');
      expect(find.textContaining('diciembre: Sin dato'), findsOneWidget);
      await tap(tester, 'febrero: Sin dato: foto patrimonial incompleta');
      expect(find.text('Patrimonio neto: Sin dato'), findsOneWidget);
      expect(find.text('Activos líquidos: Sin dato'), findsOneWidget);
      expect(find.text('Pendientes: Deuda sintética'), findsOneWidget);
      final year = find.widgetWithText(TextField, 'Año');
      await tester.ensureVisible(year);
      await tester.enterText(year, '2027');
      await tap(tester, 'Aplicar año');
      expect(find.textContaining('01/01/2027'), findsOneWidget);
      await tester.enterText(year, '2026');
      await tap(tester, 'Aplicar año');
      expect(find.textContaining('01/02/2026'), findsOneWidget);
      await tester.enterText(year, '0');
      await tap(tester, 'Aplicar año');
      expect(find.text('Introduce un año entre 1 y 9999.'), findsOneWidget);
      expect(find.text('Patrimonio neto: Sin dato'), findsOneWidget);
    },
  );

  testWidgets(
    'La persistencia al volver refresca foto, altas, bajas y liquidez histórica',
    (tester) async {
      var step = 0;
      await tester.pumpWidget(
        screen(
          month: february,
          photo: (month) async {
            expect(month, february);
            await management.savePhoto(month, {account.id: 0, debt.id: 0});
          },
          catalog: (month) async {
            expect(month, february);
            if (step++ == 0) {
              await management.accounts.create(
                name: 'Cartera nueva',
                kind: AccountKind.portfolio,
                activeFrom: january,
                liquidity: Liquidity.medium,
              );
            } else {
              final newAccount = (await management.catalog()).singleWhere(
                (a) => a.name == 'Cartera nueva',
              );
              await management.accounts.close(newAccount.id, january);
              await management.accounts.changeLiquidity(
                account.id,
                month,
                Liquidity.illiquid,
              );
            }
          },
        ),
      );
      await settle(tester);
      await tap(tester, 'Registrar / editar foto');
      expect(find.textContaining('Patrimonio neto: 0,00'), findsOneWidget);
      await tap(tester, 'Gestionar fichas');
      expect(find.text('Patrimonio neto: Sin dato'), findsOneWidget);
      expect(find.text('Pendientes: Cartera nueva'), findsOneWidget);
      await tap(tester, 'Gestionar fichas');
      expect(find.textContaining('Patrimonio neto: 0,00'), findsOneWidget);
      expect(find.text('Cuentas y carteras · No líquida'), findsOneWidget);
      expect(
        (await tester.runAsync(() => controller.readMonth(january)))!.values
            .singleWhere((v) => v.account.id == account.id)
            .account
            .liquidity,
        Liquidity.liquid,
      );
    },
  );

  testWidgets('Carga, error recuperable y vacío válido se distinguen', (
    tester,
  ) async {
    final gate = Completer<WealthManagement>();
    var failed = true;
    final reader = WealthController(
      loadManagement: () async {
        if (failed) return gate.future;
        return management;
      },
    );
    await tester.pumpWidget(screen(reading: reader, month: Month(2025, 1)));
    expect(find.text('Cargando patrimonio…'), findsOneWidget);
    expect(find.textContaining('Patrimonio neto:'), findsNothing);
    gate.completeError(const WealthFailure('Lectura interrumpida.'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Lectura interrumpida.'), findsOneWidget);
    failed = false;
    await tap(tester, 'Reintentar');
    expect(find.textContaining('No hay fichas vigentes'), findsOneWidget);
    expect(find.text('Patrimonio neto: Sin dato'), findsOneWidget);
  });

  for (final width in [
    320.0,
    360.0,
    412.0,
    839.0,
    840.0,
    1024.0,
    1199.0,
    1200.0,
    1440.0,
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Tabla/tarjeta operable $width texto $scale', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: screen(textScale: scale),
          ),
        );
        await settle(tester);
        expect(find.byType(Table), width >= 840 ? findsWidgets : findsNothing);
        await tap(tester, 'Gestionar fichas');
        expect(find.text('Estado'), findsOneWidget);
        expect(find.text('Indicadores'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Rutas reales conservan mes y actualizan después de guardar', (
    tester,
  ) async {
    await tester.pumpWidget(AutofinanceApp(wealth: () async => management));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed('/patrimonio?a=2026&m=02');
    await settle(tester);
    await tap(tester, 'Registrar / editar foto');
    expect(find.text('Referencia fija: 2026-02-01'), findsOneWidget);
    await tester.enterText(
      find.byKey(ValueKey('photo-value-${account.id}')),
      '6300',
    );
    await tester.enterText(find.byKey(ValueKey('photo-value-${debt.id}')), '0');
    await tap(tester, 'Guardar foto');
    expect(find.textContaining('01/02/2026'), findsOneWidget);
    expect(find.textContaining('Patrimonio neto: 6.300,00'), findsOneWidget);
    await tap(tester, 'Gestionar fichas');
    await tap(tester, 'Crear ficha');
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Mes de alta'))
          .controller!
          .text,
      '2026-02',
    );
    await tap(tester, 'Cancelar');
    await tap(tester, 'Volver a Patrimonio, 2026-02');
    expect(find.textContaining('01/02/2026'), findsOneWidget);
    await tap(tester, 'Real');
    expect(
      ModalRoute.of(tester.element(find.textContaining('Marcador técnico')))!
          .settings
          .name,
      '/real?a=2026&m=02',
    );
  });

  testWidgets('Neto negativo y céntimos íntegros en valores grandes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await management.photos.setValue(january, account.id, 0);
      await management.photos.setValue(january, debt.id, 9223372036854775807);
    });
    await tester.pumpWidget(screen());
    await settle(tester);
    expect(
      find.text('Patrimonio neto: −92.233.720.368.547.758,07\u00a0€'),
      findsOneWidget,
    );
    expect(find.text('Activos totales: 0,00\u00a0€'), findsOneWidget);
  });

  testWidgets('Capturas sintéticas de la vista aprobada', (tester) async {
    if (!Platform.environment.containsKey('CAPTURE_WEALTH')) return;
    await tester.runAsync(() async {
      final fonts = FontLoader('WealthCapture');
      final bytes = await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes();
      fonts.addFont(Future.value(ByteData.sublistView(bytes)));
      await fonts.load();
    });
    for (final width in [320.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        RepaintBoundary(key: const ValueKey('capture'), child: screen()),
      );
      await settle(tester);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture')),
      );
      await tester.runAsync(() async {
        final picture = await boundary.toImage();
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        await File('.tools/076-${width.toInt()}-patrimonio.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
