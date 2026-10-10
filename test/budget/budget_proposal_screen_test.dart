import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myautofinance/app/budget_factory.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_movement_repository.dart';
import 'package:myautofinance/app/navigation/app_router.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/app/navigation/navigation_session_scope.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/regional.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/budget/presentation/budget_source.dart';
import 'package:myautofinance/features/budget/presentation/budget_proposal_screen.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

void main() {
  late LocalDatabase db;
  late CategoryReadInvalidation invalidation;
  late CategoryManagement categories;
  late String root, child, leaf, income, account;
  late BudgetSource source;
  late SqliteBudgetRepository budgets;
  late SqliteMovementRepository movements;
  late NavigationSession session;
  bool readFails = false;
  Future<void> Function()? beforeLoad;
  final jan = BudgetMonth(2027, 1);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
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

  Future<void> real(String? id, int cents) async {
    await movements.create(
      MovementInput(
        accountId: account,
        valueDate: ValueDate(2026, 1, 15),
        categoryId: id,
        concept: 'Sintético',
        amountCents: cents,
      ),
    );
  }

  Future<BudgetRecord> item(String id, int amount, {BudgetMonth? month}) =>
      budgets.create(
        BudgetInput(month: month ?? jan, categoryId: id, amountCents: amount),
      );

  setUp(() async {
    db = LocalDatabase(
      NativeDatabase.memory(
        setup: (sqlite) => sqlite.execute('PRAGMA foreign_keys=ON'),
      ),
    );
    invalidation = CategoryReadInvalidation();
    categories = createCategoryManagement(
      database: db,
      invalidation: invalidation,
    );
    root = (await categories.create(name: 'Alimentación')).node.id;
    child = (await categories.create(
      name: 'Supermercado',
      parentId: root,
    )).node.id;
    leaf = (await categories.create(
      name: 'Compra semanal',
      parentId: child,
    )).node.id;
    income = (await categories.create(
      name: 'Ingresos',
      isIncome: true,
    )).node.id;
    account = (await SqliteAccountRepository(db).create(
      name: 'Cuenta sintética',
      kind: AccountKind.account,
      activeFrom: Month(2026, 1),
      liquidity: Liquidity.liquid,
    )).id;
    source = createBudgetSource(db, invalidation);
    budgets = SqliteBudgetRepository(db);
    movements = SqliteMovementRepository(db);
    await real(child, -35025);
    await real(income, 310000);
    session = NavigationSession(clock: () => DateTime.utc(2026, 1, 15));
    readFails = false;
    beforeLoad = null;
  });
  tearDown(() async {
    session.dispose();
    await invalidation.close();
    await db.close();
  });

  Future<void> boot(
    WidgetTester tester, {
    double width = 1440,
    double height = 1200,
    double scale = 1,
    String route = '/presupuesto/propuesta?a=2026&m=04',
    TargetPlatform platform = TargetPlatform.windows,
  }) async {
    if (const bool.fromEnvironment('PROPOSAL_CAPTURE') && Platform.isWindows) {
      await tester.runAsync(() async {
        final font = FontLoader('ProposalCapture');
        font.addFont(
          File('C:/Windows/Fonts/segoeui.ttf')
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
        await font.load();
      });
    }
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    Future<BudgetSource> load() async {
      await beforeLoad?.call();
      if (readFails) throw const BudgetFailure('Lectura sintética fallida');
      return source;
    }

    await tester.pumpWidget(
      MaterialApp(
        locale: AppRegional.locale,
        supportedLocales: AppRegional.supportedLocales,
        localizationsDelegates: AppRegional.delegates,
        theme: ThemeData(
          platform: platform,
          fontFamily: const bool.fromEnvironment('PROPOSAL_CAPTURE')
              ? 'ProposalCapture'
              : null,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff124b7a)),
          textTheme: const TextTheme(
            bodyMedium: TextStyle(fontSize: 16, height: 1.4),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
          ),
        ),
        builder: (context, child) => RepaintBoundary(
          key: const ValueKey('proposal-capture'),
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
        navigatorObservers: [
          NavigationSessionObserver(session, monthlyBudget: true),
        ],
        onGenerateInitialRoutes: (_) => [
          AppRouter.generateRoute(
            RouteSettings(name: route),
            budgets: load,
            navigationSession: session,
          ),
        ],
        onGenerateRoute: (settings) => AppRouter.generateRoute(
          settings,
          budgets: load,
          navigationSession: session,
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> generate(WidgetTester tester) =>
      tap(tester, find.text('Generar propuesta'));
  Finder edit(String id) => find.byKey(ValueKey('edit-$id-${jan.value}'));
  Finder split(String id) => find.byKey(ValueKey('split-$id-${jan.value}'));
  Future<void> editAmount(WidgetTester tester, String id, String value) async {
    await tap(tester, edit(id));
    await tester.enterText(
      find.widgetWithText(TextField, 'Importe propuesto'),
      value,
    );
    await tap(tester, find.text('Aplicar importe'));
  }

  Future<void> review(WidgetTester tester) =>
      tap(tester, find.text('Revisar y guardar'));
  Future<void> confirm(WidgetTester tester, String action) async {
    await tap(
      tester,
      find.widgetWithText(
        CheckboxListTile,
        'He revisado la comparación y confirmo «$action»',
      ),
    );
    await tap(tester, find.widgetWithText(FilledButton, action));
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('PROPOSAL_CAPTURE')) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('proposal-capture')),
      );
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('.tools').create(recursive: true);
      await File('.tools/ma-tsk-154-$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'Windows: doce meses, reales/propuesta, cero y lectura sin escrituras',
    (tester) async {
      await boot(tester);
      await generate(tester);
      expect(find.text('Diciembre'), findsOneWidget);
      expect(find.text('Real fuente: −350,25 €'), findsOneWidget);
      expect(find.text('Propuesto inicial: −360,00 €'), findsOneWidget);
      expect(find.text('Sin reales · cero explícito'), findsNWidgets(22));
      await capture(tester, 'windows');
      expect(await tester.runAsync(() => budgets.readYear(2027)), isEmpty);
      await editAmount(tester, root, '-370');
      expect(find.text('Alimentación: −370,00 €'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('proposal-year')),
        '2025',
      );
      await review(tester);
      expect(find.text('Comparar propuesta 2027'), findsOneWidget);
      await tap(tester, find.text('Cancelar').last);
      await tap(tester, find.text('Regenerar propuesta'));
      await tap(tester, find.text('Conservar borrador'));
      expect(find.text('Alimentación: −370,00 €'), findsOneWidget);
      expect(find.text('Fuente: 2026 · Destino: 2027'), findsOneWidget);
    },
  );

  testWidgets(
    'Desglose nivel tres retira padre; comparación completa y cancelar conserva',
    (tester) async {
      await item(root, -40000);
      await boot(tester);
      await generate(tester);
      await editAmount(tester, root, '-370');
      await tap(tester, split(root));
      await tap(tester, find.byKey(ValueKey('split-option-$leaf')));
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Importe de Alimentación / Supermercado / Compra semanal',
        ),
        '-370',
      );
      await tap(tester, find.text('Aplicar desglose'));
      expect(edit(root), findsNothing);
      expect(edit(leaf), findsOneWidget);
      await review(tester);
      expect(find.textContaining('25 partidas · 24 ámbitos'), findsOneWidget);
      expect(find.textContaining('Alimentación · Retirada'), findsOneWidget);
      expect(find.textContaining('Compra semanal · Nueva'), findsOneWidget);
      await tap(tester, find.text('Cancelar').last);
      expect(edit(leaf), findsOneWidget);
      expect(
        (await tester.runAsync(() => budgets.list(jan)))!
            .single
            .data
            .categoryId,
        root,
      );
      await review(tester);
      await confirm(tester, 'Sustituir partidas');
      final saved = (await tester.runAsync(() => budgets.list(jan)))!;
      expect(saved.any((b) => b.data.categoryId == root), isFalse);
      expect(
        saved.singleWhere((b) => b.data.categoryId == leaf).data.amountCents,
        -37000,
      );
      expect(find.byType(BudgetProposalScreen), findsNothing);
      expect(session.period, NavigationPeriod(2027, 1));
      expect(find.text('Propuesta guardada en 2027'), findsOneWidget);
    },
  );

  testWidgets('Signos atípicos obligatorios y cada edición invalida revisión', (
    tester,
  ) async {
    await tester.runAsync(() => real(root, 40000));
    await boot(tester);
    await generate(tester);
    await review(tester);
    expect(
      find.textContaining('Marca «He revisado los signos señalados»'),
      findsOneWidget,
    );
    await tap(
      tester,
      find.widgetWithText(CheckboxListTile, 'He revisado los signos señalados'),
    );
    await editAmount(tester, root, '-100');
    final checkbox = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'He revisado los signos señalados'),
    );
    expect(checkbox.value, isFalse);
    await review(tester);
    expect(find.text('Comparar propuesta 2027'), findsNothing);
    expect(await tester.runAsync(() => budgets.readYear(2027)), isEmpty);
  });

  testWidgets(
    'Cambios concurrentes durante confirmación: no guarda y conserva ediciones',
    (tester) async {
      await boot(tester);
      await generate(tester);
      await editAmount(tester, root, '-370');
      await review(tester);
      await tester.runAsync(() => item(root, -80000));
      await confirm(tester, 'Guardar propuesta');
      expect(find.textContaining('Datos obsoletos.'), findsOneWidget);
      expect(find.text('Alimentación: −370,00 €'), findsOneWidget);
      expect(
        (await tester.runAsync(() => budgets.readYear(2027)))!
            .single
            .data
            .amountCents,
        -80000,
      );
      await tap(tester, find.text('Regenerar propuesta'));
      await tap(tester, find.text('Conservar borrador'));
      expect(find.text('Alimentación: −370,00 €'), findsOneWidget);
      await tap(tester, find.text('Regenerar propuesta'));
      await tap(tester, find.text('Regenerar y descartar ediciones'));
      expect(find.text('Alimentación: −360,00 €'), findsOneWidget);
      await review(tester);
      expect(find.text('Anterior: −800,00 €'), findsOneWidget);
    },
  );

  for (final afterReview in [false, true]) {
    testWidgets(
      'Base sustituida ${afterReview ? 'tras comparar' : 'antes de comparar'}: conserva borrador y no guarda',
      (tester) async {
        await boot(tester);
        await generate(tester);
        await editAmount(tester, root, '-370');
        if (afterReview) await review(tester);
        // Mismos datos financieros: solo cambia la identidad de la base activa.
        // El borrador conserva sus servicios originales para detectar el relevo.
        source = BudgetSource(
          query: source.query,
          management: source.management,
          categories: source.categories,
          identity: Object(),
          proposalCalculator: source.proposalCalculator,
          proposalSaver: source.proposalSaver,
        );
        if (afterReview) {
          await confirm(tester, 'Guardar propuesta');
        } else {
          await review(tester);
        }
        expect(
          find.textContaining('La base local se ha sustituido.'),
          findsOneWidget,
        );
        expect(find.text('Alimentación: −370,00 €'), findsOneWidget);
        expect(find.text('Propuesta guardada en 2027'), findsNothing);
        expect(await tester.runAsync(() => budgets.readYear(2027)), isEmpty);
        final save = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Revisar y guardar'),
        );
        expect(save.onPressed, isNull);
        await tap(tester, find.text('Regenerar propuesta'));
        await tap(tester, find.text('Conservar borrador'));
        expect(find.text('Alimentación: −370,00 €'), findsOneWidget);
      },
    );
  }
  testWidgets(
    'Fallo SQLite revierte sustitución, conserva borrador y permite reintentar',
    (tester) async {
      await item(root, -40000);
      await boot(tester);
      await generate(tester);
      await editAmount(tester, root, '-370');
      await tester.runAsync(
        () => db.customStatement(
          "CREATE TRIGGER fail_proposal BEFORE INSERT ON budgets BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
        ),
      );
      await review(tester);
      await confirm(tester, 'Sustituir partidas');
      expect(find.byType(BudgetProposalScreen), findsOneWidget);
      expect(find.text('Alimentación: −370,00 €'), findsOneWidget);
      expect(find.text('Propuesta guardada en 2027'), findsNothing);
      expect(
        (await tester.runAsync(() => budgets.readYear(2027)))!
            .single
            .data
            .amountCents,
        -40000,
      );
      await tester.runAsync(
        () => db.customStatement('DROP TRIGGER fail_proposal'),
      );
      await review(tester);
      await confirm(tester, 'Sustituir partidas');
      expect((await tester.runAsync(() => budgets.readYear(2027)))!.length, 24);
    },
  );

  testWidgets(
    'Lectura fallida evita falsos ceros y regeneración fallida conserva borrador',
    (tester) async {
      readFails = true;
      await boot(tester);
      await generate(tester);
      expect(find.text('Lectura sintética fallida'), findsOneWidget);
      expect(find.text('Fuente: 2026 · Destino: 2027'), findsNothing);
      readFails = false;
      await generate(tester);
      await editAmount(tester, root, '-370');
      readFails = true;
      await tap(tester, find.text('Regenerar propuesta'));
      await tap(tester, find.text('Regenerar y descartar ediciones'));
      expect(find.text('Alimentación: −370,00 €'), findsOneWidget);
      expect(await tester.runAsync(() => budgets.readYear(2027)), isEmpty);
    },
  );

  testWidgets(
    'Excluidos sin clasificar y raíz archivada visibles sin bloquear',
    (tester) async {
      final archived = (await categories.create(name: 'Antigua')).node.id;
      await real(archived, -100);
      await categories.archive(archived);
      await real(null, -200);
      await boot(tester);
      await generate(tester);
      await tap(
        tester,
        find.text('Reales excluidos (2) · aviso no bloqueante'),
      );
      expect(find.textContaining('Sin clasificar · −2,00 €'), findsOneWidget);
      expect(
        find.textContaining('Raíz archivada: Antigua · −1,00 €'),
        findsOneWidget,
      );
      await review(tester);
      await confirm(tester, 'Guardar propuesta');
      expect((await tester.runAsync(() => budgets.readYear(2027)))!.length, 24);
    },
  );

  testWidgets(
    '320 px/200% Android: tarjetas, diálogo, teclado y Back conservan',
    (tester) async {
      await boot(
        tester,
        width: 320,
        height: 800,
        scale: 2,
        platform: TargetPlatform.android,
      );
      await generate(tester);
      await tap(tester, find.text('Alimentación'));
      expect(find.text('Diciembre'), findsOneWidget);
      await tap(tester, find.text('Enero').first);
      await tap(tester, edit(root));
      await capture(tester, 'android-edit-200');
      await tester.enterText(
        find.widgetWithText(TextField, 'Importe propuesto'),
        '-370',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settle(tester);
      expect(find.text('Alimentación: −370,00 €'), findsOneWidget);
      await review(tester);
      await capture(tester, 'android-comparison-200');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Comparar propuesta 2027'), findsNothing);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Hay cambios sin guardar'), findsOneWidget);
      await tap(tester, find.text('Seguir editando'));
      expect(find.text('Alimentación: −370,00 €'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settle(tester);
      await tap(tester, find.text('Descartar cambios'));
      expect(find.text('Presupuesto mensual'), findsOneWidget);
      expect(session.period, NavigationPeriod(2026, 4));
    },
  );

  testWidgets(
    'Entrada mensual, Escape y retorno conservan periodo común y foco',
    (tester) async {
      await boot(tester, route: '/presupuesto?a=2026&m=04');
      await tap(tester, find.text('Proponer año siguiente'));
      expect(session.period, NavigationPeriod(2026, 4));
      await generate(tester);
      await tap(tester, edit(root));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.text('Editar importe'), findsNothing);
      await tap(tester, find.text('Cancelar propuesta'));
      await tap(tester, find.text('Descartar cambios'));
      expect(find.text('Presupuesto mensual'), findsOneWidget);
      expect(session.period, NavigationPeriod(2026, 4));
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Proponer año siguiente'),
            )
            .focusNode!
            .hasFocus,
        isTrue,
      );
    },
  );

  testWidgets('Año inválido no genera; año elegido determina retorno fuente', (
    tester,
  ) async {
    await boot(tester);
    await tester.enterText(find.byKey(const ValueKey('proposal-year')), '9999');
    await generate(tester);
    expect(find.text('Elige un año fuente entre 1 y 9998.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('proposal-year')), '2025');
    await generate(tester);
    expect(find.text('Fuente: 2025 · Destino: 2026'), findsOneWidget);
    await tap(tester, find.text('Cancelar propuesta'));
    await tap(tester, find.text('Descartar cambios'));
    expect(session.period.year, 2025);
  });

  testWidgets(
    'Desglose conserva padre al rechazar y admite nuevo total explícito',
    (tester) async {
      await boot(tester);
      await generate(tester);
      await tap(tester, split(root));
      await tap(tester, find.byKey(ValueKey('split-option-$child')));
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Importe de Alimentación / Supermercado',
        ),
        '-380',
      );
      await tap(tester, find.text('Aplicar desglose'));
      expect(
        find.text(
          'Conserva el total anterior o edita explícitamente el nuevo total.',
        ),
        findsOneWidget,
      );
      await tap(
        tester,
        find.widgetWithText(
          CheckboxListTile,
          'Editar expresamente el total de este mes',
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Nuevo total explícito'),
        '-380',
      );
      await tap(tester, find.text('Aplicar desglose'));
      expect(edit(root), findsNothing);
      expect(
        find.text('Alimentación / Supermercado: −380,00 €'),
        findsOneWidget,
      );
      expect(await tester.runAsync(() => budgets.readYear(2027)), isEmpty);
    },
  );

  testWidgets(
    'Doble envío y Back bloqueados durante comprobación; cancelar no escribe',
    (tester) async {
      await boot(tester);
      await generate(tester);
      final gate = Completer<void>();
      var reads = 0;
      beforeLoad = () async {
        reads++;
        await gate.future;
      };
      final button = find.widgetWithText(FilledButton, 'Revisar y guardar');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      await tester.tap(button);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(reads, 1);
      expect(find.text('Hay cambios sin guardar'), findsNothing);
      expect(find.byType(BudgetProposalScreen), findsOneWidget);
      gate.complete();
      await settle(tester);
      await tap(tester, find.text('Cancelar').last);
      expect(await tester.runAsync(() => budgets.readYear(2027)), isEmpty);
    },
  );

  testWidgets('Sin raíces activas: teclado no confirma un guardado vacío', (
    tester,
  ) async {
    await categories.archive(root);
    await categories.archive(income);
    await boot(tester);
    await generate(tester);
    expect(
      find.text(
        'No hay raíces activas para proponer. No se inventan partidas.',
      ),
      findsOneWidget,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
    expect(find.text('Comparar propuesta 2027'), findsNothing);
    expect(await tester.runAsync(() => budgets.readYear(2027)), isEmpty);
  });

  testWidgets(
    'Año sin mes EP-002, cero editado, destino recordado y ámbitos ajenos conservados',
    (tester) async {
      final archived = (await categories.create(name: 'Archivada')).node.id;
      // Histórico destino en rama excluida, insertado antes de archivarla.
      final unrelated = await item(archived, -99900);
      await categories.archive(archived);
      final original = await item(root, -12300, month: BudgetMonth(2026, 1));
      await session.selectPeriod(NavigationPeriod(2027, 5));
      await boot(tester, route: '/presupuesto/propuesta?a=2026');
      await generate(tester);
      await editAmount(tester, root, '0');
      await review(tester);
      await confirm(tester, 'Guardar propuesta');
      expect(session.period, NavigationPeriod(2027, 5));
      expect(
        (await tester.runAsync(() => budgets.get(original.id)))!
            .data
            .amountCents,
        -12300,
      );
      expect(
        (await tester.runAsync(() => budgets.get(unrelated.id)))!
            .data
            .amountCents,
        -99900,
      );
      expect(
        (await tester.runAsync(() => budgets.list(jan)))!
            .singleWhere((b) => b.data.categoryId == root)
            .data
            .amountCents,
        0,
      );
    },
  );
}
