import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

/// Rutas de producto y SQLite en archivo, compartidas con los runners nativos.
/// La carpeta es siempre temporal y sintética, nunca la base de la instalación.
Future<void> wealthLifecycleJourney(
  WidgetTester tester,
  Directory directory, {
  Directory? captures,
}) async {
  var session = LocalBackupSession(supportDirectory: () async => directory);
  Future<T> io<T>(Future<T> Function() action) async {
    Object? error;
    StackTrace? trace;
    final result = await tester.runAsync(() async {
      try {
        return await action();
      } catch (caught, stack) {
        error = caught;
        trace = stack;
        return null;
      }
    });
    if (error != null) Error.throwWithStackTrace(error!, trace!);
    return result as T;
  }

  Future<void> settle() async {
    for (var turn = 0; turn < 300; turn++) {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump(const Duration(milliseconds: 100));
      if (turn >= 15 &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty) {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        return;
      }
    }
    fail('La operación patrimonial SQLite no terminó.');
  }

  Future<void> tap(String label) async {
    debugPrint('Recorrido patrimonio: $label');
    final buttons = find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    final target = buttons.evaluate().isEmpty
        ? find.text(label).last
        : buttons.last;
    await tester.ensureVisible(target);
    await tester.runAsync(() => tester.tap(target));
    await settle();
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> enter(Finder target, String text) async {
    await tester.ensureVisible(target);
    await tester.enterText(target, text);
    await tester.pump();
  }

  Future<void> choose<T>(String label) async {
    final dropdown = find.byType(DropdownButtonFormField<T>);
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await settle();
  }

  Future<Map<String, Object?>> image() => io(() async {
    final db = await session.store.open();
    return {
      for (final table in [
        'accounts',
        'account_liquidity_periods',
        'wealth_snapshots',
        'wealth_values',
        'database_state',
      ])
        table: (await db.customSelect('SELECT * FROM $table ORDER BY 1').get())
            .map((row) => row.data)
            .toList(),
    };
  });
  Future<void> sql(String statement) => io(() async {
    await (await session.store.open()).customStatement(statement);
  });
  Future<WealthReading> read(int month) =>
      io(() async => (await session.wealth()).readMonth(Month(2026, month)));
  Future<void> totals(int month, List<int> expected) async {
    final reading = await read(month);
    expect(reading.status, WealthSnapshotStatus.complete);
    final total = reading.totals!;
    expect([
      total.liquidAssetsCents,
      total.mediumAssetsCents,
      total.assetsCents,
      total.debtsCents,
      total.netWorthCents,
    ], expected);
    expect(reading.values.every((v) => v.amountCents >= 0), isTrue);
    expect(reading.month.value, '2026-${month.toString().padLeft(2, '0')}-01');
  }

  Future<void> capture(String stage) async {
    if (captures == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('wealth-journey-capture')),
    );
    await io(() async {
      await captures.create(recursive: true);
      final picture = await boundary.toImage();
      try {
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        await File('${captures.path}/$stage.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        picture.dispose();
      }
    });
  }

  Future<void> mount(int month) async {
    await io(session.store.open);
    expect(await io(session.open), isTrue);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('wealth-journey-capture'),
        child: AutofinanceApp(localSession: session),
      ),
    );
    await settle();
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .pushNamed('/patrimonio?a=2026&m=${month.toString().padLeft(2, '0')}');
    await settle();
  }

  Future<String> create(
    String name, {
    AccountKind kind = AccountKind.account,
    String liquidity = 'Líquida',
    String? from,
  }) async {
    await tap('Crear ficha');
    await enter(field('Nombre'), name);
    if (kind != AccountKind.account) {
      await choose<AccountKind>(
        kind == AccountKind.debt ? 'Deuda' : 'Cartera agregada',
      );
    }
    if (kind != AccountKind.debt) await choose<Liquidity>(liquidity);
    if (from != null) await enter(field('Mes de alta'), from);
    await tap('Guardar');
    return io(
      () async => (await (await session.wealth()).catalog())
          .singleWhere((a) => a.name == name)
          .id,
    );
  }

  Future<void> photo(Map<String, String> values) async {
    await tap('Registrar / editar foto');
    for (final entry in values.entries) {
      await enter(
        find.byKey(ValueKey('photo-value-${entry.key}')),
        entry.value,
      );
    }
    await tap('Guardar foto');
  }

  final january = [900000, 1000000, 1900000, 500000, 1400000];
  final february = [620000, 1050000, 1670000, 480000, 1190000];
  try {
    await mount(1);
    expect(find.text('Patrimonio neto: Sin dato'), findsOneWidget);
    await tap('Gestionar fichas');
    // Cancelar sin edición y descartar con cambios no crean una ficha.
    final empty = await image();
    await tap('Crear ficha');
    await tap('Cancelar');
    expect(await image(), empty);
    await tap('Crear ficha');
    await enter(field('Nombre'), 'Borrador sintético');
    await tap('Cancelar');
    expect(find.text('Hay cambios sin guardar'), findsOneWidget);
    await tap('Seguir editando');
    expect(
      tester.widget<TextField>(field('Nombre')).controller!.text,
      'Borrador sintético',
    );
    await tap('Cancelar');
    await tap('Descartar cambios');
    expect(await image(), empty);

    await tap('Crear ficha');
    await enter(field('Nombre'), 'Alta rechazada');
    await choose<Liquidity>('Líquida');
    await sql('''CREATE TEMP TRIGGER wealth_account_failure
      BEFORE INSERT ON accounts
      BEGIN SELECT RAISE(ABORT, 'fallo sintético de alta'); END''');
    await tap('Guardar');
    expect(find.textContaining('No se pudo guardar.'), findsOneWidget);
    expect(find.text('Ficha guardada'), findsNothing);
    expect(
      tester.widget<TextField>(field('Nombre')).controller!.text,
      'Alta rechazada',
    );
    expect(await image(), empty);
    await sql('DROP TRIGGER wealth_account_failure');
    await tap('Cancelar');
    await tap('Descartar cambios');

    final principal = await create('Cuenta principal');
    final saving = await create('Cuenta de ahorro');
    final portfolio = await create(
      'Cartera',
      kind: AccountKind.portfolio,
      liquidity: 'Media',
    );
    final debt = await create('Deuda familiar', kind: AccountKind.debt);
    expect(
      (await io(() async => (await session.wealth()).details(debt))).history,
      isEmpty,
    );
    await tap('Volver a Patrimonio, 2026-01');
    await photo({
      principal: '6000',
      saving: '3000',
      portfolio: '10000',
      debt: '5000',
    });
    await totals(1, january);
    expect(find.textContaining('Patrimonio neto: 14.000,00'), findsOneWidget);
    await capture('01-enero-completo');

    await choose<int>('febrero');
    final missing = await read(2);
    expect(missing.status, WealthSnapshotStatus.absent);
    expect(missing.totals, isNull);
    expect(missing.values, isEmpty);
    expect(find.text('Patrimonio neto: Sin dato'), findsOneWidget);
    await capture('02-febrero-ausente');
    await tap('Registrar / editar foto');
    await enter(find.byKey(ValueKey('photo-value-$debt')), '-4800');
    final beforeNegative = await image();
    await tap('Guardar foto');
    expect(find.text('Introduce un valor de 0,00 € o más'), findsWidgets);
    expect(await image(), beforeNegative);
    await tap('Cancelar');
    await tap('Descartar cambios');
    await photo({principal: '6200', debt: '4800'});
    final partial = await read(2);
    expect(partial.status, WealthSnapshotStatus.incomplete);
    expect(partial.totals, isNull);
    expect(partial.pending.map((a) => a.name).toSet(), {
      'Cuenta de ahorro',
      'Cartera',
    });
    for (final label in [
      'Activos líquidos',
      'Activos totales',
      'Deudas',
      'Patrimonio neto',
    ]) {
      expect(find.text('$label: Sin dato'), findsOneWidget);
    }
    await capture('03-febrero-parcial');
    await photo({saving: '0', portfolio: '10500'});
    await totals(2, february);
    expect(
      (await read(2)).values
          .singleWhere((v) => v.account.id == saving)
          .amountCents,
      0,
    );
    await capture('04-febrero-completo');

    // ABORT tras escribir una primera fila: la transacción revierte también
    // revisión, marcas de tiempo e identidades, no solo la última cantidad.
    final beforeFailure = await image();
    await sql('''CREATE TEMP TRIGGER wealth_journey_failure
      BEFORE UPDATE ON wealth_values WHEN NEW.account_id='$debt'
      BEGIN SELECT RAISE(ABORT, 'fallo sintético 077'); END''');
    await tap('Registrar / editar foto');
    await enter(find.byKey(ValueKey('photo-value-$principal')), '6300');
    await enter(find.byKey(ValueKey('photo-value-$debt')), '4700');
    await tap('Guardar foto');
    expect(find.textContaining('No se guardó la foto.'), findsOneWidget);
    expect(find.textContaining('Foto guardada'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(ValueKey('photo-value-$principal')))
          .controller!
          .text,
      '6300',
    );
    expect(await image(), beforeFailure);
    await capture('05-error-con-borrador');
    await sql('DROP TRIGGER wealth_journey_failure');
    // Cancelar el error conserva la foto previa. Reintentar luego la
    // corrección conserva el ID de foto y de cada valoración.
    await tap('Cancelar');
    await tap('Seguir editando');
    await tap('Cancelar');
    await tap('Descartar cambios');
    expect(await image(), beforeFailure);
    await photo({principal: '6300'});
    await totals(2, [630000, 1050000, 1680000, 480000, 1200000]);
    await totals(1, january);
    final corrected = await image();
    for (final table in ['wealth_snapshots', 'wealth_values']) {
      final old = (beforeFailure[table]! as List).cast<Map<String, Object?>>();
      final current = (corrected[table]! as List).cast<Map<String, Object?>>();
      expect(current.map((row) => row['id']), old.map((row) => row['id']));
    }

    // Variante independiente: volver a 6.200 antes de cambiar la liquidez.
    await photo({principal: '6200'});
    await tap('Cartera');
    await tap('Cambiar liquidez');
    expect(
      tester.widget<TextField>(field('Mes de aplicación')).controller!.text,
      '2026-02',
    );
    await choose<Liquidity>('Líquida');
    final beforeLiquidity = await image();
    await tap('Guardar liquidez');
    await tap('Cancelar');
    expect(await image(), beforeLiquidity);
    await sql('''CREATE TEMP TRIGGER wealth_liquidity_failure
      BEFORE INSERT ON account_liquidity_periods
      BEGIN SELECT RAISE(ABORT, 'fallo sintético de liquidez'); END''');
    await tap('Guardar liquidez');
    await tap('Aplicar cambio');
    expect(find.textContaining('No se pudo guardar.'), findsOneWidget);
    expect(find.text('Liquidez guardada'), findsNothing);
    expect(await image(), beforeLiquidity);
    await sql('DROP TRIGGER wealth_liquidity_failure');
    await tap('Guardar liquidez');
    await tap('Aplicar cambio');
    await tap('Volver a Patrimonio, 2026-02');
    await totals(1, january);
    await totals(2, [1670000, 0, 1670000, 480000, 1190000]);
    final afterLiquidity = await image();
    expect(afterLiquidity['wealth_values'], beforeLiquidity['wealth_values']);
    expect(
      afterLiquidity['wealth_snapshots'],
      beforeLiquidity['wealth_snapshots'],
    );
    expect(find.textContaining('Activos líquidos: 16.700,00'), findsOneWidget);
    await capture('06-liquidez-desde-febrero');
    await tap('Cartera');
    await tap('Corregir liquidez histórica');
    await enter(field('Mes de fin (excluido, opcional)'), '2026-03');
    await choose<Liquidity>('Media');
    await tap('Guardar liquidez');
    await tap('Corregir intervalo');
    await tap('Volver a Patrimonio, 2026-02');
    await totals(1, january);
    await totals(2, february);
    expect((await read(3)).totals, isNull);

    await choose<int>('marzo');
    await tap('Gestionar fichas');
    final extra = await create('Cuenta nueva');
    await tap('Volver a Patrimonio, 2026-03');
    await totals(1, january);
    await totals(2, february);
    await photo({
      principal: '6200',
      saving: '0',
      portfolio: '10500',
      debt: '4800',
    });
    expect((await read(3)).pending.single.id, extra);
    expect((await read(3)).totals, isNull);
    await photo({extra: '0'});
    expect((await read(3)).status, WealthSnapshotStatus.complete);
    await choose<int>('abril');
    await photo({
      principal: '6200',
      saving: '0',
      portfolio: '10500',
      debt: '4800',
    });
    expect((await read(4)).pending.single.id, extra);
    await photo({extra: '0'});
    await tap('Cuenta nueva');
    await tap('Editar ficha');
    await enter(field('Mes de baja (opcional)'), '2026-04');
    final beforeClose = await image();
    await tap('Guardar');
    await tap('Cancelar');
    expect(await image(), beforeClose);
    await sql('''CREATE TEMP TRIGGER wealth_close_failure
      BEFORE UPDATE ON accounts WHEN NEW.id='$extra'
      BEGIN SELECT RAISE(ABORT, 'fallo sintético de baja'); END''');
    await tap('Guardar');
    await tap('Guardar baja');
    expect(find.textContaining('No se pudo guardar.'), findsOneWidget);
    expect(find.text('Ficha guardada'), findsNothing);
    expect(
      tester
          .widget<TextField>(field('Mes de baja (opcional)'))
          .controller!
          .text,
      '2026-04',
    );
    expect(await image(), beforeClose);
    await sql('DROP TRIGGER wealth_close_failure');
    await tap('Guardar');
    await tap('Guardar baja');
    expect(find.textContaining('01/04/2026'), findsOneWidget);
    await capture('07-baja-abril');
    await choose<int>('mayo');
    final may = await read(5);
    expect(may.status, WealthSnapshotStatus.absent);
    expect(may.pending.any((a) => a.id == extra), isFalse);
    expect(may.values, isEmpty);
    await photo({
      principal: '6200',
      saving: '0',
      portfolio: '10500',
      debt: '4800',
    });
    expect((await read(5)).status, WealthSnapshotStatus.complete);
    expect((await read(6)).status, WealthSnapshotStatus.absent);
    for (final month in [3, 4]) {
      expect(
        (await read(month)).values
            .singleWhere((v) => v.account.id == extra)
            .amountCents,
        0,
      );
    }

    final durable = await image();
    await tester.pumpWidget(const SizedBox.shrink());
    await settle();
    await io(session.store.close);
    session.controller.dispose();
    session = LocalBackupSession(supportDirectory: () async => directory);
    await mount(1);
    expect(await image(), durable);
    await totals(1, january);
    await totals(2, february);
    expect((await read(6)).totals, isNull);
    await tap('Las doce fotos de 2026 · sin suma anual');
    await tap('marzo: Foto completa · Neto 11.900,00\u00a0€');
    expect(find.text('Cuenta nueva'), findsOneWidget);
    await capture('08-historico-tras-reapertura');
    // Navegar a otra vista transmite el periodo, sin escribir.
    await tap('Real');
    expect(
      ModalRoute.of(tester.element(find.textContaining('Marcador técnico')))!
          .settings
          .name,
      '/real?a=2026&m=03',
    );
    expect(await image(), durable);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle();
    await io(session.store.close);
    session.controller.dispose();
  }
}
