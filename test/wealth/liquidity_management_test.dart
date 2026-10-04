import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/wealth_management_factory.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:myautofinance/features/wealth/presentation/account_form_screen.dart';

void main() {
  late LocalDatabase db;
  late WealthManagement service;
  setUp(() {
    db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    service = createWealthManagement(database: db);
  });
  tearDown(() => db.close());
  Future<AccountDetails> asset({Month? from, Month? through}) => service.create(
    name: 'Cartera sintética',
    kind: AccountKind.portfolio,
    activeFrom: from ?? Month(2026, 1),
    activeThrough: through,
    liquidity: Liquidity.medium,
  );
  Future<Liquidity?> classification(String id, Month month) async =>
      (await service.accounts.listForMonth(month))
          .where((a) => a.id == id)
          .single
          .liquidity;

  test(
    'Caso D por servicio: cambio y corrección conservan fotos y enero',
    () async {
      final items = <AccountDetails>[];
      for (final kind in [
        AccountKind.account,
        AccountKind.account,
        AccountKind.portfolio,
        AccountKind.debt,
      ]) {
        items.add(
          await service.create(
            name: 'Ficha ${items.length}',
            kind: kind,
            activeFrom: Month(2026, 1),
            liquidity: kind == AccountKind.debt
                ? null
                : kind == AccountKind.portfolio
                ? Liquidity.medium
                : Liquidity.liquid,
          ),
        );
      }
      for (var i = 0; i < 4; i++) {
        await service.photos.setValue(
          Month(2026, 1),
          items[i].account.id,
          [600000, 300000, 1000000, 500000][i],
        );
        await service.photos.setValue(
          Month(2026, 2),
          items[i].account.id,
          [620000, 0, 1050000, 480000][i],
        );
      }
      final before = await db
          .customSelect('SELECT * FROM wealth_values ORDER BY id')
          .get();
      final id = items[2].account.id;
      final saved = await service.changeLiquidity(
        id,
        Month(2026, 2),
        Liquidity.liquid,
      );
      expect(saved.history, hasLength(2));
      expect(
        (await service.readMonth(Month(2026, 2))).liquidAssetsCents,
        1670000,
      );
      expect(
        (await service.readMonth(Month(2026, 1))).liquidAssetsCents,
        900000,
      );
      expect(
        (await service.readMonth(Month(2026, 2))).totals!.netWorthCents,
        1190000,
      );
      await service.correctHistoricalLiquidity(
        id,
        Month(2026, 2),
        Month(2026, 3),
        Liquidity.medium,
      );
      expect(
        (await service.readMonth(Month(2026, 2))).liquidAssetsCents,
        620000,
      );
      expect(
        (await service.readMonth(Month(2026, 2))).totals!.netWorthCents,
        1190000,
      );
      expect(await classification(id, Month(2026, 3)), Liquidity.liquid);
      expect(
        (await db.customSelect('SELECT * FROM wealth_values ORDER BY id').get())
            .map((r) => r.data),
        before.map((r) => r.data),
      );
    },
  );

  test(
    'Límites, baja inclusiva, cambios posteriores y cobertura exacta',
    () async {
      final id = (await asset(
        from: Month(2025, 12),
        through: Month(2026, 4),
      )).account.id;
      await service.changeLiquidity(id, Month(2026, 3), Liquidity.illiquid);
      await service.changeLiquidity(id, Month(2026, 1), Liquidity.liquid);
      expect(await classification(id, Month(2025, 12)), Liquidity.medium);
      expect(await classification(id, Month(2026, 2)), Liquidity.liquid);
      expect(await classification(id, Month(2026, 3)), Liquidity.illiquid);
      await service.correctHistoricalLiquidity(
        id,
        Month(2026, 2),
        Month(2026, 3),
        Liquidity.medium,
      );
      expect(await classification(id, Month(2026, 1)), Liquidity.liquid);
      expect(await classification(id, Month(2026, 3)), Liquidity.illiquid);
      await service.correctHistoricalLiquidity(
        id,
        Month(2026, 4),
        null,
        Liquidity.liquid,
      );
      final history = (await service.details(id)).history;
      expect(history.first.from.value, '2025-12-01');
      expect(history.last.until!.value, '2026-05-01');
      for (var i = 1; i < history.length; i++) {
        expect(history[i - 1].until!.value, history[i].from.value);
      }
      final revision = (await db.readState()).revision;
      for (final action in <Future<Object?> Function()>[
        () => service.changeLiquidity(id, Month(2025, 11), Liquidity.medium),
        () => service.changeLiquidity(id, Month(2026, 5), Liquidity.medium),
        () => service.correctHistoricalLiquidity(
          id,
          Month(2026, 2),
          Month(2026, 2),
          Liquidity.medium,
        ),
        () => service.correctHistoricalLiquidity(
          id,
          Month(2026, 2),
          Month(2026, 6),
          Liquidity.medium,
        ),
      ]) {
        await expectLater(action(), throwsA(isA<AccountFailure>()));
      }
      expect((await db.readState()).revision, revision);
      expect(
        (await service.details(id)).history.map((p) => p.id),
        history.map((p) => p.id),
      );
      final last = (await asset(
        from: Month(9999, 12),
        through: Month(9999, 12),
      )).account.id;
      await service.correctHistoricalLiquidity(
        last,
        Month(9999, 12),
        null,
        Liquidity.liquid,
      );
      expect((await service.details(last)).history.single.until, isNull);
      final debt = await service.create(
        name: 'Deuda',
        kind: AccountKind.debt,
        activeFrom: Month(2026, 1),
      );
      await expectLater(
        service.changeLiquidity(
          debt.account.id,
          Month(2026, 1),
          Liquidity.liquid,
        ),
        throwsA(isA<AccountFailure>()),
      );
      await expectLater(
        service.correctHistoricalLiquidity(
          debt.account.id,
          Month(2026, 1),
          null,
          Liquidity.liquid,
        ),
        throwsA(isA<AccountFailure>()),
      );
      expect((await service.details(debt.account.id)).history, isEmpty);
    },
  );

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 35; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final target = find.text(text).last;
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
  }

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.byType(DropdownButtonFormField<Liquidity>));
    await tester.tap(find.byType(DropdownButtonFormField<Liquidity>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester tester,
    String id, {
    double width = 1000,
    double textScale = 1,
    WealthManagementLoader? loader,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: AccountFormScreen(
          accountId: id,
          loadManagement: loader ?? () async => service,
          initialMonth: Month(2026, 2),
          onReturn: () {},
          onSaved: (_) {},
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('Detalle PC: confirmación, cambio y corrección solo de febrero', (
    tester,
  ) async {
    final id = (await tester.runAsync(asset))!.account.id;
    await tester.runAsync(
      () => service.changeLiquidity(id, Month(2026, 4), Liquidity.illiquid),
    );
    await open(tester, id);
    expect(find.byType(Table), findsOneWidget);
    await tap(tester, 'Cambiar liquidez');
    await settle(tester);
    await choose(tester, 'Líquida');
    await tap(tester, 'Guardar liquidez');
    await tester.pumpAndSettle();
    expect(find.textContaining('hasta 2026-04 (excluido)'), findsOneWidget);
    await tap(tester, 'Aplicar cambio');
    await settle(tester);
    expect(find.text('Liquidez guardada'), findsOneWidget);
    expect(
      await tester.runAsync(() => classification(id, Month(2026, 2))),
      Liquidity.liquid,
    );
    await tap(tester, 'Corregir liquidez histórica');
    await settle(tester);
    await tester.enterText(field('Mes de fin (excluido, opcional)'), '2026-03');
    await choose(tester, 'Media');
    await tap(tester, 'Guardar liquidez');
    await tester.pumpAndSettle();
    await tap(tester, 'Corregir intervalo');
    await settle(tester);
    expect(
      await tester.runAsync(() => classification(id, Month(2026, 2))),
      Liquidity.medium,
    );
    expect(
      await tester.runAsync(() => classification(id, Month(2026, 3))),
      Liquidity.liquid,
    );
    expect(
      await tester.runAsync(() => classification(id, Month(2026, 4))),
      Liquidity.illiquid,
    );
  });

  testWidgets(
    'Móvil: validación, Escape, fallo conserva borrador y reintento',
    (tester) async {
      final id = (await tester.runAsync(asset))!.account.id;
      var failLoad = false;
      await open(
        tester,
        id,
        width: 360,
        textScale: 2,
        loader: () async {
          if (failLoad) throw StateError('Fallo sintético');
          return service;
        },
      );
      expect(find.byType(Card), findsOneWidget);
      await tap(tester, 'Corregir liquidez histórica');
      await settle(tester);
      await tester.enterText(field('Mes de aplicación'), '2026-13');
      await tap(tester, 'Guardar liquidez');
      expect(
        tester
            .widget<TextField>(field('Mes de aplicación'))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await tester.enterText(field('Mes de aplicación'), '2026-02');
      await tester.enterText(
        field('Mes de fin (excluido, opcional)'),
        '2026-02',
      );
      await tap(tester, 'Guardar liquidez');
      expect(
        tester
            .widget<TextField>(field('Mes de fin (excluido, opcional)'))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await tester.enterText(
        field('Mes de fin (excluido, opcional)'),
        '2026-03',
      );
      await choose(tester, 'Líquida');
      await tap(tester, 'Guardar liquidez');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(() => classification(id, Month(2026, 2))),
        Liquidity.medium,
      );
      failLoad = true;
      await tap(tester, 'Guardar liquidez');
      await tester.pumpAndSettle();
      await tap(tester, 'Corregir intervalo');
      await settle(tester);
      expect(find.textContaining('El borrador se conserva'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(field('Mes de fin (excluido, opcional)'))
            .controller!
            .text,
        '2026-03',
      );
      failLoad = false;
      await tap(tester, 'Guardar liquidez');
      await tester.pumpAndSettle();
      await tap(tester, 'Corregir intervalo');
      await settle(tester);
      expect(
        await tester.runAsync(() => classification(id, Month(2026, 2))),
        Liquidity.liquid,
      );
    },
  );

  testWidgets(
    'Atrás confirma descarte; escritura pendiente bloquea salida y éxito',
    (tester) async {
      final id = (await tester.runAsync(asset))!.account.id;
      final pending = Completer<WealthManagement>();
      var waitForSave = false;
      await open(
        tester,
        id,
        loader: () async => waitForSave ? pending.future : service,
      );
      await tap(tester, 'Cambiar liquidez');
      await settle(tester);
      await choose(tester, 'Líquida');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Hay cambios sin guardar'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Guardar liquidez'), findsOneWidget);
      final revision = (await tester.runAsync(db.readState))!.revision;
      await tap(tester, 'Cancelar');
      await tester.pumpAndSettle();
      await tap(tester, 'Descartar cambios');
      await settle(tester);
      expect((await tester.runAsync(db.readState))!.revision, revision);
      await tap(tester, 'Cambiar liquidez');
      await settle(tester);
      await choose(tester, 'Líquida');
      await tap(tester, 'Guardar liquidez');
      await tester.pumpAndSettle();
      waitForSave = true;
      await tap(tester, 'Aplicar cambio');
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Guardando…'), findsOneWidget);
      expect(find.text('Liquidez guardada'), findsNothing);
      expect(
        tester.widget<TextField>(field('Mes de aplicación')).enabled,
        isFalse,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(find.text('Hay cambios sin guardar'), findsNothing);
      pending.complete(service);
      await settle(tester);
      expect(find.text('Liquidez guardada'), findsOneWidget);
      expect((await tester.runAsync(db.readState))!.revision, revision + 1);
    },
  );

  testWidgets('Deuda sin acciones de liquidez', (tester) async {
    final debt = await tester.runAsync(
      () => service.create(
        name: 'Deuda',
        kind: AccountKind.debt,
        activeFrom: Month(2026, 1),
      ),
    );
    await open(tester, debt!.account.id);
    expect(find.text('Las deudas no tienen liquidez.'), findsOneWidget);
    expect(find.text('Cambiar liquidez'), findsNothing);
    expect(find.text('Corregir liquidez histórica'), findsNothing);
  });
}
