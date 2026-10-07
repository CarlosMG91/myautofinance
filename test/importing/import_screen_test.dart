import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/import_factory.dart';
import 'package:myautofinance/app/navigation/app_router.dart';
import 'package:myautofinance/app/navigation/app_routes.dart';
import 'package:myautofinance/app/navigation/import_route.dart';
import 'package:myautofinance/app/regional.dart';
import 'package:myautofinance/core/config/app_config.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/importing/presentation/import_controller.dart';
import 'package:myautofinance/features/importing/presentation/import_review_screen.dart';
import 'package:myautofinance/features/importing/presentation/import_widgets.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

import '../support/import_ui_fixture.dart';
import 'import_controller_test.dart' show DelayedConfirmer;
import 'import_preview_test.dart' as fixture;

void main() {
  setUpAll(() async {
    // El motor de tests usa Ahem por defecto. Fuente real para comprobar ajuste.
    final file = File('C:/Windows/Fonts/segoeui.ttf');
    if (await file.exists()) {
      final loader = FontLoader('Segoe UI')
        ..addFont(file.readAsBytes().then((b) => ByteData.sublistView(b)));
      await loader.load();
    }
  });
  late LocalDatabase db;
  late ImportServices services;
  late ImportController c;
  late String accountId;
  final repaint = GlobalKey();
  setUp(() async {
    db = LocalDatabase(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys=ON'),
      ),
    );
    accountId = (await SqliteAccountRepository(db).create(
      name: 'Cuenta',
      kind: AccountKind.account,
      activeFrom: Month(2026, 1),
      liquidity: Liquidity.liquid,
    )).id;
    await SqliteCategoryRepository(db).create(name: 'Gastos', isIncome: false);
    services = createImportServices(db);
    c = ImportController(() async => services);
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(finder));
    await settle(tester);
  }

  Future<void> boot(
    WidgetTester tester, {
    double width = 1280,
    double scale = 1,
    VoidCallback? back,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: AppRegional.locale,
        supportedLocales: AppRegional.supportedLocales,
        localizationsDelegates: AppRegional.delegates,
        theme: ThemeData(
          fontFamily: 'Segoe UI',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff124b7a)),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: repaint,
          child: ImportReviewScreen(
            controller: c,
            onReturn: back ?? () {},
            onHistory: () {},
            onBatch: (_) {},
            onPeriod: (_, _) {},
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> start(
    List<InterpretedImportRow> rows, {
    List<int> bytes = const [1],
  }) async =>
      c.start(fixture.draft(rows, bytes: bytes).file, SyntheticUiAdapter(rows));
  Future<void> screenshot(WidgetTester tester, String name) async {
    final boundary =
        repaint.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final pixels = await boundary.toImage();
      final bytes = await pixels.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('build/ma-tsk-112');
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      pixels.dispose();
    });
  }

  testWidgets('PC tabla; signos, originales y consentimiento con Escape', (
    tester,
  ) async {
    await start([
      fixture.real(),
      fixture.real(ordinal: 3),
      fixture.budget(ordinal: 4),
    ]);
    await boot(tester);
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Sin clasificar'), findsNWidgets(2));
    expect(find.text('−10,00 €'), findsOneWidget);
    await screenshot(tester, 'windows-revision');
    await tap(tester, find.text('Originales 2'));
    expect(find.text('Campos originales · fila 2'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    await tap(tester, find.text('Confirmar lote completo'));
    expect(find.text('Importar todo'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect((await services.history.listBatches()).items, isEmpty);
    await tap(tester, find.text('Confirmar lote completo'));
    await tap(tester, find.text('Importar todo'));
    expect(find.text('Importado'), findsOneWidget);
    expect(
      find.textContaining('Lote guardado en la base local'),
      findsOneWidget,
    );
  });
  for (final width in [320.0, 390.0, 840.0, 1280.0]) {
    testWidgets('Tarjetas a texto 200% · ancho $width; accesibilidad', (
      tester,
    ) async {
      await start([fixture.real(), fixture.budget()]);
      await boot(tester, width: width, scale: 2);
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('Categoría: Sin clasificar'), findsOneWidget);
      final semantics = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantics.dispose();
      if (width == 390) await screenshot(tester, 'android-texto-200');
      await tap(tester, find.text('Confirmar lote completo'));
      expect(find.text('Importar todo'), findsOneWidget);
      await tap(tester, find.text('Seguir revisando'));
      expect(c.phase, ImportPhase.review);
    });
  }
  testWidgets('Resolver cuenta global y cancelar sesión sin escribir', (
    tester,
  ) async {
    var back = 0;
    await start([
      fixture.real(account: const ImportAccountReference.selectedAccount()),
    ]);
    final before = (await db.readState()).revision;
    await boot(tester, width: 390, back: () => back++);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Confirmar lote completo'),
          )
          .onPressed,
      isNull,
    );
    await tap(tester, find.text('Resolver cuenta: selección global'));
    await tap(tester, find.byType(DropdownButtonFormField<String>));
    await tap(tester, find.text('Cuenta · $accountId').last);
    await tap(tester, find.text('Aplicar a la revisión'));
    expect(c.canConfirm, isTrue);
    expect((await db.readState()).revision, before);
    await tap(tester, find.text('Volver al origen'));
    await tap(tester, find.text('Seguir revisando'));
    expect(c.session, isNotNull);
    await tap(tester, find.text('Volver al origen'));
    await tap(tester, find.text('Descartar sesión'));
    expect(back, 1);
    expect(c.hasSession, isFalse);
    expect((await services.history.listBatches()).items, isEmpty);
  });
  testWidgets('Confirmando bloquea acciones y Atrás; fallo conserva revisión', (
    tester,
  ) async {
    final delayed = DelayedConfirmer(services.confirmer);
    services = ImportServices(
      source: services.source,
      previewer: services.previewer,
      confirmer: delayed,
      history: services.history,
    );
    await start([fixture.real()]);
    await boot(tester);
    await tap(tester, find.text('Confirmar lote completo'));
    await tester.ensureVisible(find.text('Importar todo'));
    await tester.tap(find.text('Importar todo'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.text('Confirmando'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Volver al origen'),
          )
          .onPressed,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(c.phase, ImportPhase.confirming);
    final observer =
        tester.state(find.byType(ImportReviewScreen)) as WidgetsBindingObserver;
    expect(await observer.didRequestAppExit(), ui.AppExitResponse.cancel);
    await db.blockWritesForRestore();
    delayed.gate.complete();
    await settle(tester);
    expect(find.text('Error'), findsOneWidget);
    expect(c.session, isNotNull);
    expect(delayed.calls, 1);
  });
  testWidgets(
    'Origen/periodo, historial, paginación y retorno a sesión por rutas reales',
    (tester) async {
      final rows = [for (var i = 0; i < 51; i++) fixture.real(ordinal: i + 2)];
      final launch = ImportReviewLaunch(
        file: fixture.draft(rows).file,
        adapter: SyntheticUiAdapter(rows),
        origin: '/real?a=2026&m=01',
      );
      await tester.pumpWidget(
        MaterialApp(
          onGenerateInitialRoutes: (_) => [
            AppRouter.generateRoute(
              RouteSettings(name: AppRoutes.importReview, arguments: launch),
              imports: () async => services,
              allowTestImports: true,
            ),
          ],
          onGenerateRoute: (s) => AppRouter.generateRoute(
            s,
            imports: () async => services,
            allowTestImports: true,
          ),
        ),
      );
      await settle(tester);
      await tap(tester, find.text('Historial de lotes'));
      expect(find.text('Sin lotes confirmados.'), findsOneWidget);
      await tap(tester, find.text('Volver'));
      expect(find.text('Revisión'), findsOneWidget);
      await tap(tester, find.text('Confirmar lote completo'));
      await tap(tester, find.text('Importar todo'));
      await tap(tester, find.text('Real · 2026-01'));
      expect(find.text('Real anual'), findsOneWidget);
      await tap(tester, find.text('Volver'));
      await tap(tester, find.text('Consultar lote y origen'));
      await tap(tester, find.text('Página siguiente'));
      expect(find.text('Fila 52 · REAL'), findsOneWidget);
      await tap(tester, find.text('Fila 52 · REAL'));
      expect(find.text('Procedencia de fila'), findsOneWidget);
      expect(find.text('Registro actual'), findsOneWidget);
      expect(find.text('Abrir registro actual'), findsOneWidget);
      await tap(tester, find.text('Volver'));
      expect(find.text('Página 2'), findsOneWidget);
      await tap(tester, find.text('Volver'));
      expect(find.text('Importado'), findsOneWidget);
    },
  );
  testWidgets(
    'Producción ignora lanzamiento sintético y mantiene historial accesible',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        AutofinanceApp(
          config: const AppConfig(environment: AppEnvironment.production),
          imports: () async {
            calls++;
            return services;
          },
        ),
      );
      await settle(tester);
      final context = tester.element(find.byType(Scaffold));
      Navigator.of(context).pushNamed(
        AppRoutes.importReview,
        arguments: ImportReviewLaunch(
          file: fixture.draft([fixture.real()]).file,
          adapter: SyntheticUiAdapter([fixture.real()]),
        ),
      );
      await settle(tester);
      expect(find.text('Revisión'), findsNothing);
      expect(calls, 0);
      await tap(tester, find.text('Historial de lotes'));
      expect(find.text('Sin lotes confirmados.'), findsOneWidget);
    },
  );
  testWidgets('Solapamientos exigen revisión explícita sin quitar filas', (
    tester,
  ) async {
    await start([fixture.real()]);
    await c.confirm();
    c.discard();
    await start([fixture.real(), fixture.real(ordinal: 3)], bytes: [2]);
    await boot(tester, width: 390);
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    for (final tile in find.byType(CheckboxListTile).evaluate().toList()) {
      await tap(tester, find.byWidget(tile.widget));
    }
    expect(c.canConfirm, isTrue);
    expect(c.session!.interpretation.rows.length, 2);
    await tap(tester, find.text('Confirmar lote completo'));
    await tap(tester, find.text('Importar todo'));
    expect(c.phase, ImportPhase.imported);
  });
  test('Formato monetario exacto con signo e int64 mínimo', () {
    expect(importMoney(-9223372036854775808), '−92.233.720.368.547.758,08 €');
    expect(importMoney(BigInt.zero), '0,00 €');
    final parent = ImportCategoryReference(['Nombre original']);
    final child = ImportCategoryReference(['Nombre original', 'Hijo']);
    final bindings = ImportReferenceBindings(
      newCategories: {
        parent: const ImportNewCategory(
          name: 'Raíz elegida',
          parent: ImportCategoryTarget.existing('g'),
        ),
        child: ImportNewCategory(
          name: 'Hijo elegido',
          parent: ImportCategoryTarget.proposed(parent),
        ),
      },
    );
    expect(
      importPlannedCategoryPath(child, bindings, [fixture.node('g')]),
      'Gastos / Raíz elegida / Hijo elegido',
    );
  });

  testWidgets(
    'Crear raíz en revisión exige elegir ingreso y cancelar no da altas',
    (tester) async {
      final ref = ImportCategoryReference(['Nueva']);
      await start([fixture.budget(category: ref)]);
      await boot(tester, width: 320, scale: 2);
      await tap(tester, find.text('Resolver categoría: Nueva'));
      await tap(tester, find.byType(SwitchListTile));
      await tap(tester, find.text('Aplicar a la revisión'));
      expect(find.text('Elige la marca de ingreso.'), findsOneWidget);
      await tap(tester, find.byType(DropdownButtonFormField<bool>));
      await tap(tester, find.text('No ingreso').last);
      await tap(tester, find.text('Aplicar a la revisión'));
      expect(c.canConfirm, isTrue);
      expect((await SqliteCategoryRepository(db).list()).length, 1);
      await tap(tester, find.text('Volver al origen'));
      await tap(tester, find.text('Descartar sesión'));
      expect((await SqliteCategoryRepository(db).list()).length, 1);
    },
  );
  testWidgets('Procedencia distingue original, corrección y destino borrado', (
    tester,
  ) async {
    await start([fixture.real()]);
    await c.confirm();
    final batch = (c.result as ImportConfirmed).batch;
    final row = (await services.history.listRows(batch.id)).items.single;
    await db.customStatement(
      "UPDATE movements SET concept='Corregido', amount_cents=-500 WHERE id='${row.currentMovement!.id}'",
    );
    await tester.pumpWidget(
      MaterialApp(
        onGenerateInitialRoutes: (_) => [
          AppRouter.generateRoute(
            RouteSettings(name: '${AppRoutes.importRows}/${row.id}'),
            imports: () async => services,
          ),
        ],
        onGenerateRoute: (s) =>
            AppRouter.generateRoute(s, imports: () async => services),
      ),
    );
    await settle(tester);
    expect(find.text('Concepto:  Café '), findsOneWidget);
    expect(find.textContaining('Corregido · −5,00 €'), findsOneWidget);
    await db.customStatement('DELETE FROM movements');
    await tap(tester, find.text('Recargar contexto'));
    expect(find.textContaining('Registro borrado.'), findsOneWidget);
    expect(find.text('Abrir registro actual'), findsNothing);
    expect(find.text('Concepto:  Café '), findsOneWidget);
  });
}
