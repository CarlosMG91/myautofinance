import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/import_factory.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:myautofinance/features/importing/presentation/import_review_screen.dart';

import 'openbank_reader_test.dart' show bankFixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('AfRoboto')..addFont(
          File('assets/fonts/roboto-regular.ttf')
              .readAsBytes()
              .then(ByteData.sublistView),
        ))
        .load();
  });
  for (final width in [412.0, 1440.0]) {
    testWidgets(
      'Gestión → selector Openbank → cuenta → confirmación → SQLite, $width',
      (t) async {
        t.view.physicalSize = Size(width, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final db = LocalDatabase(
          NativeDatabase.memory(setup: configureConnection),
        );
        addTearDown(db.close);
        final services = createImportServices(db);
        await t.runAsync(
          () => SqliteAccountRepository(db).create(
            name: 'Cuenta sintética',
            kind: AccountKind.account,
            activeFrom: Month(2026, 1),
            liquidity: Liquidity.liquid,
          ),
        );
        const channel = MethodChannel('autofinance/local_csv');
        var selected = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              expect(call.method, 'select');
              expect(call.arguments, {'extension': 'xls'});
              selected++;
              return {
                'name': 'sintético.xls',
                'bytes': Uint8List.fromList(bankFixture()),
              };
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        Future<void> settle() async {
          for (var i = 0; i < 150; i++) {
            await t.runAsync(() async {
              await t.pump();
              await Future<void>.delayed(const Duration(milliseconds: 10));
            });
            await t.pump(const Duration(milliseconds: 40));
            if (i >= 5 && find.byType(AlertDialog).evaluate().isNotEmpty) {
              await t.pump(const Duration(milliseconds: 300));
              expect(t.takeException(), isNull);
              return;
            }
            if (i >= 5 &&
                find.byType(LinearProgressIndicator).evaluate().isEmpty &&
                find.text('Leyendo').evaluate().isEmpty) {
              await t.pumpAndSettle();
              expect(t.takeException(), isNull);
              return;
            }
          }
          final controller = t
              .widget<ImportReviewScreen>(find.byType(ImportReviewScreen))
              .controller;
          fail(
            'No terminó la operación Openbank: ${controller.phase}, selecting=${controller.selecting}, message=${controller.message}, result=${controller.result.runtimeType}, rows=${controller.session?.interpretation.rows.length}',
          );
        }

        Future<void> tap(String label) async {
          final f = find.text(label).last;
          await t.ensureVisible(f);
          await t.pump(const Duration(milliseconds: 150));
          await t.runAsync(() => t.tap(f));
          await settle();
        }

        final capture = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: AutofinanceApp(imports: () async => services),
          ),
        );
        await settle();
        final nav = Navigator.of(t.element(find.byType(Scaffold)));
        nav.pushNamed('/real?a=2026&m=02');
        await settle();
        await tap('Gestión');
        await tap('Importar Openbank');
        expect(find.text('Seleccionar Openbank'), findsOneWidget);
        expect(
          find.textContaining('Volver a Real anual, febrero de 2026'),
          findsOneWidget,
        );
        await tap('Seleccionar Openbank');
        expect(selected, 1);
        expect(find.text('Revisión'), findsOneWidget);
        expect(find.textContaining('pendientes de categorizar'), findsWidgets);
        expect(
          (await t.runAsync(
            () => db.customSelect('SELECT * FROM movements').get(),
          ))!,
          isEmpty,
        );
        await tap('Resolver cuenta: selección global');
        await t.tap(find.byType(DropdownButtonFormField<String>).first);
        await settle();
        await t.tap(find.textContaining('Cuenta sintética ·').last);
        await settle();
        await tap('Aplicar a la revisión');
        await tap('Ver detalle de filas');
        expect(find.textContaining('Café & té sintético'), findsWidgets);
        await t.runAsync(() async {
          final image =
              await (capture.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('.tools/openbank-review-$width.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tap('Confirmar lote completo');
        await tap('Importar todo');
        expect(find.text('Importado'), findsOneWidget);
        final moves = (await t.runAsync(
          () => db.customSelect('SELECT * FROM movements').get(),
        ))!;
        expect(moves, hasLength(4));
        expect(moves.every((r) => r.data['category_id'] == null), isTrue);
        await tap('Volver a cargar Openbank');
        await tap('Descartar y cargar');
        expect(find.text('Ya importado'), findsOneWidget);
        expect(
          (await t.runAsync(
            () => db.customSelect('SELECT * FROM movements').get(),
          ))!,
          hasLength(4),
        );
        await tap('Volver a Real anual, febrero de 2026');
        expect(
          ModalRoute.of(t.element(find.byType(Scaffold)))!.settings.name,
          '/real?a=2026&m=02',
        );
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
