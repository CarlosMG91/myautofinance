import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:myautofinance/features/wealth/presentation/wealth_photo_screen.dart';

void main() {
  late Directory directory;
  late LocalBackupSession session;
  late WealthManagement service;
  late String accountId, debtId;
  final month = Month(2026, 2);
  setUpAll(() => initializeDateFormatting('es_ES'));
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wealth-photo-screen-');
    session = LocalBackupSession(supportDirectory: () async => directory);
    expect(await session.open(), isTrue);
    service = await session.wealth();
    accountId = (await service.create(
      name: 'A Cuenta sintética',
      kind: AccountKind.account,
      activeFrom: Month(2026, 1),
      liquidity: Liquidity.liquid,
    )).account.id;
    debtId = (await service.create(
      name: 'Z Deuda sintética',
      kind: AccountKind.debt,
      activeFrom: Month(2026, 1),
    )).account.id;
  });
  tearDown(() async {
    await session.store.close();
    session.controller.dispose();
    await directory.delete(recursive: true);
  });
  Finder value(String id) => find.byKey(ValueKey('photo-value-$id'));
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump(const Duration(milliseconds: 30));
      if (i >= 15 && find.byType(LinearProgressIndicator).evaluate().isEmpty) {
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

  Widget form({
    WealthManagementLoader? loader,
    ValueChanged<WealthSnapshot>? saved,
    VoidCallback? returned,
    ValueChanged<String>? navigate,
  }) => MaterialApp(
    home: WealthPhotoScreen(
      controller: WealthController(loadManagement: loader ?? session.wealth),
      month: month,
      onSaved: saved ?? (_) {},
      onReturn: returned ?? () {},
      destinations: const {'/real': 'Real anual'},
      onNavigate: navigate,
    ),
  );

  testWidgets(
    'Carga manual, referencia fija y negativo enfocado sin perder campos',
    (tester) async {
      await tester.runAsync(
        () => service.photos.setValue(Month(2026, 1), accountId, 99999),
      );
      await tester.pumpWidget(form(saved: (_) => fail('No debe guardar')));
      await settle(tester);
      expect(find.text('Referencia fija: 2026-02-01'), findsOneWidget);
      expect(find.text('Valores del 1 de febrero de 2026'), findsOneWidget);
      expect(
        tester.widget<TextField>(value(accountId)).controller!.text,
        isEmpty,
      );
      await tester.enterText(value(accountId), '-1');
      await tester.enterText(value(debtId), '29,01');
      await tap(tester, 'Guardar foto');
      await tester.pumpAndSettle();
      expect(find.text('Introduce un valor de 0,00 € o más'), findsWidgets);
      expect(
        tester.widget<TextField>(value(accountId)).focusNode!.hasFocus,
        isTrue,
      );
      expect(tester.widget<TextField>(value(debtId)).controller!.text, '29,01');
      expect(
        (await tester.runAsync(() => service.photos.read(month)))!.values,
        isEmpty,
      );
      await tester.enterText(value(accountId), '0,001');
      await tap(tester, 'Guardar foto');
      expect(find.text('Introduce un valor de 0,00 € o más'), findsWidgets);
    },
  );

  testWidgets(
    'Guardado espera almacenamiento; parcial con cero registrado y vacío pendiente',
    (tester) async {
      final waiting = Completer<WealthManagement>();
      var writing = false;
      WealthSnapshot? saved;
      await tester.pumpWidget(
        form(
          loader: () => writing ? waiting.future : session.wealth(),
          saved: (photo) => saved = photo,
        ),
      );
      await settle(tester);
      await tester.enterText(value(accountId), '0');
      writing = true;
      await tap(tester, 'Guardar foto');
      expect(find.text('Guardando…'), findsOneWidget);
      expect(saved, isNull);
      expect(tester.widget<TextField>(value(accountId)).enabled, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(find.text('Hay cambios sin guardar'), findsNothing);
      await tester.runAsync(() async => waiting.complete(service));
      await settle(tester);
      expect(saved!.status, WealthSnapshotStatus.incomplete);
      expect(saved!.values.single.amountCents, 0);
      expect(saved!.pending.single.id, debtId);
    },
  );

  testWidgets('Fallo conserva borrador y foto previa; reintento no duplica', (
    tester,
  ) async {
    await tester.runAsync(
      () => service.savePhoto(month, {accountId: 123, debtId: 456}),
    );
    final before = (await tester.runAsync(() => service.photos.read(month)))!;
    await tester.runAsync(() async {
      final db = await session.store.open();
      await db.customStatement('''CREATE TEMP TRIGGER photo_ui_failure
        BEFORE UPDATE ON wealth_values WHEN NEW.account_id='$debtId'
        BEGIN SELECT RAISE(ABORT, 'fallo sintético'); END''');
    });
    WealthSnapshot? saved;
    await tester.pumpWidget(form(saved: (photo) => saved = photo));
    await settle(tester);
    await tester.enterText(value(accountId), '999,99');
    await tester.enterText(value(debtId), '888,88');
    await tap(tester, 'Guardar foto');
    await settle(tester);
    expect(saved, isNull);
    expect(
      find.textContaining('No se guardó la foto. Inténtalo de nuevo.'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(value(accountId)).controller!.text,
      '999,99',
    );
    expect(tester.widget<TextField>(value(debtId)).controller!.text, '888,88');
    final unchanged = (await tester.runAsync(
      () => service.photos.read(month),
    ))!;
    expect(
      unchanged.values.map((v) => v.amountCents),
      before.values.map((v) => v.amountCents),
    );
    await tester.runAsync(
      () async => (await session.store.open()).customStatement(
        'DROP TRIGGER photo_ui_failure',
      ),
    );
    await tap(tester, 'Guardar foto');
    await settle(tester);
    expect(saved!.values, hasLength(2));
    expect(saved!.values.map((v) => v.id), before.values.map((v) => v.id));
  });

  testWidgets('Error de carga permite reintentar sin inventar valores', (
    tester,
  ) async {
    var failing = true;
    await tester.pumpWidget(
      form(
        loader: () async {
          if (failing) throw const WealthFailure('causa sintética');
          return service;
        },
      ),
    );
    await settle(tester);
    expect(
      find.text('No se pudo cargar la foto. causa sintética'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    failing = false;
    await tap(tester, 'Reintentar');
    await settle(tester);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets(
    'Escape y cambio de destino ofrecen seguir o descartar, con foco de retorno',
    (tester) async {
      var returned = false;
      String? destination;
      await tester.pumpWidget(
        form(
          returned: () => returned = true,
          navigate: (path) => destination = path,
        ),
      );
      await settle(tester);
      await tester.enterText(value(accountId), '32,45');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Hay cambios sin guardar'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(returned, isFalse);
      expect(
        tester.widget<TextField>(value(accountId)).focusNode!.hasFocus,
        isTrue,
      );
      await tester.tap(find.byTooltip('Cambiar destino'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Real anual'));
      await tester.pumpAndSettle();
      await tap(tester, 'Seguir editando');
      await tester.pumpAndSettle();
      expect(destination, isNull);
      expect(
        tester.widget<TextField>(value(accountId)).controller!.text,
        '32,45',
      );
      await tester.tap(find.byTooltip('Cambiar destino'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Real anual'));
      await tester.pumpAndSettle();
      await tap(tester, 'Descartar cambios');
      await tester.pumpAndSettle();
      expect(destination, '/real');
      expect(
        (await tester.runAsync(() => service.photos.read(month)))!.values,
        isEmpty,
      );
    },
  );

  testWidgets(
    'Ruta conserva febrero, Atrás protegido y guardado actualiza origen con pendientes',
    (tester) async {
      await tester.pumpWidget(AutofinanceApp(localSession: session));
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.pushNamed('/patrimonio?a=2026&m=02', arguments: 'origen-sintético');
      await settle(tester);
      await tap(tester, 'Registrar / editar foto');
      await settle(tester);
      final context = tester.element(value(accountId));
      expect(
        ModalRoute.of(context)!.settings.name,
        '/patrimonio/foto?a=2026&m=02',
      );
      expect(ModalRoute.of(context)!.settings.arguments, 'origen-sintético');
      await tester.enterText(value(accountId), '29.01');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Hay cambios sin guardar'), findsOneWidget);
      await tap(tester, 'Seguir editando');
      await tester.pumpAndSettle();
      await tap(tester, 'Guardar foto');
      await settle(tester);
      expect(find.byType(WealthPhotoScreen), findsNothing);
      expect(find.textContaining('01/02/2026'), findsOneWidget);
      expect(find.text('Pendientes: Z Deuda sintética'), findsOneWidget);
      expect(
        find.textContaining('Foto guardada · 2026-02-01. Foto incompleta.'),
        findsOneWidget,
      );
      expect(
        ModalRoute.of(tester.element(find.textContaining('01/02/2026')))!
            .settings
            .name,
        '/patrimonio?a=2026&m=02',
      );
      await tap(tester, 'Registrar / editar foto');
      await settle(tester);
      expect(
        tester.widget<TextField>(value(accountId)).controller!.text,
        '29,01',
      );
      expect(tester.widget<TextField>(value(debtId)).controller!.text, isEmpty);
      await tester.enterText(value(debtId), '0');
      await tap(tester, 'Guardar foto');
      await settle(tester);
      expect(find.text('Foto completa'), findsOneWidget);
      expect(
        (await tester.runAsync(() => service.photos.read(month)))!.status,
        WealthSnapshotStatus.complete,
      );
    },
  );

  for (final width in [320, 360, 412, 839, 840, 1024, 1199, 1200, 1440]) {
    testWidgets('Foto sin recortes a $width px, texto 200 % y tabla/tarjetas', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width.toDouble(), 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (const bool.fromEnvironment('CAPTURE_PHOTO')) {
        await tester.runAsync(() async {
          final loader = FontLoader('PhotoCapture');
          final bytes = await File(
            width >= 840 ? 'C:/Windows/Fonts/segoeui.ttf' : '.tools/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
          ).readAsBytes();
          loader.addFont(Future.value(ByteData.sublistView(bytes)));
          await loader.load();
        });
      }
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            fontFamily: const bool.fromEnvironment('CAPTURE_PHOTO')
                ? 'PhotoCapture'
                : null,
            textTheme: const TextTheme(
              bodyMedium: TextStyle(fontSize: 16, height: 1.4),
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: captureKey,
            child: WealthPhotoScreen(
              controller: WealthController(loadManagement: session.wealth),
              month: month,
              onSaved: (_) {},
              onReturn: () {},
            ),
          ),
        ),
      );
      await settle(tester);
      expect(find.byType(Table), width >= 840 ? findsOneWidget : findsNothing);
      expect(find.byType(Card), width < 840 ? findsNWidgets(2) : findsNothing);
      await tester.ensureVisible(value(debtId));
      await tester.enterText(value(debtId), '0');
      await tap(tester, 'Guardar foto');
      await settle(tester);
      expect(
        (await tester.runAsync(() => service.photos.read(month)))!
            .values
            .single
            .amountCents,
        0,
      );
      if (const bool.fromEnvironment('CAPTURE_PHOTO') &&
          (width == 320 || width == 1440)) {
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final capture = (await tester.runAsync(
          () => boundary.toImage(pixelRatio: 1),
        ))!;
        final bytes = await tester.runAsync(
          () => capture.toByteData(format: ui.ImageByteFormat.png),
        );
        await tester.runAsync(
          () =>
              File('.tools/074-$width-foto.png')
                  .writeAsBytes(bytes!.buffer.asUint8List()),
        );
        capture.dispose();
      }
    });
  }
}
