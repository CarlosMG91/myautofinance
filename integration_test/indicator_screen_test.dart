import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_budget_repository.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/features/budget/budget.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

import '../test/support/indicator_journey.dart';
import '../test/support/recovery_reference.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  final captures = <String, String>{};
  final boundary = GlobalKey();
  binding.reportData = {
    'indicatorCaptures': captures,
    'runtime': {
      'platform': Platform.operatingSystem,
      'syntheticDataOnly': true,
      'origin': 'Native Flutter RenderRepaintBoundary',
      'surfaceSizeForced': true,
      'compactCapturesScrollToCard': true,
      'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
    },
  };

  Future<Directory> temporary() async {
    final support = await getApplicationSupportDirectory();
    final root = await Directory('${support.path}/synthetic-indicator-tests')
        .create(recursive: true);
    final temp = await root.createTemp('run-');
    return Directory(await temp.resolveSymbolicLinks());
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final shell = tester.widget<AfShell>(find.byType(AfShell));
    final offset = shell.scrollController?.offset ?? 0;
    shell.scrollController?.jumpTo(0);
    if (name.startsWith('320-200-')) {
      await tester.ensureVisible(find.byType(AfCard).first);
    }
    await tester.pumpAndSettle();
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await render.toImage();
    final bytes = (await picture.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    picture.dispose();
    captures['${Platform.operatingSystem}-$name.png'] = base64Encode(bytes);
    shell.scrollController?.jumpTo(offset);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'MA-TSK-186 recorrido real, foto y presupuesto, importación/restauración',
    (tester) async {
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      final directory = await temporary();
      try {
        await binding.setSurfaceSize(
          Platform.isWindows ? const Size(1440, 1000) : const Size(412, 1000),
        );
        await indicatorJourney(
          tester,
          directory,
          desktop: Platform.isWindows,
          captureKey: boundary,
          externalAndroidBack:
              Platform.isAndroid &&
              const bool.fromEnvironment('INDICATOR_ANDROID_BACK'),
          capture: (name) => capture(tester, name),
        );
      } finally {
        await binding.setSurfaceSize(null);
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets('MA-TSK-186 siete estados nativos a 320px y texto 200%', (
    tester,
  ) async {
    final directory = await temporary();
    final local = LocalBackupSession(supportDirectory: () async => directory);
    final navigation = NavigationSession(
      initialContext: NavigationContext(
        destination: SessionDestination.indicators,
        period: NavigationPeriod(2026, 1),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() async {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 15));
        });
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    try {
      expect(await local.open(), isTrue);
      final db = await local.store.open();
      await seedRecoveryReference(db);
      await binding.setSurfaceSize(const Size(320, 1000));
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 1000),
              textScaler: TextScaler.linear(2),
            ),
            child: AutofinanceApp(
              localSession: local,
              navigationSession: navigation,
            ),
          ),
        ),
      );
      await settle();
      expect(find.text('3,00 meses'), findsOneWidget);
      expect(
        MediaQuery.textScalerOf(tester.element(find.byType(AfCard).first))
            .scale(16),
        32,
      );
      await capture(tester, '320-200-calculable');
      final wealth = await local.wealth();
      final accounts = await wealth.catalog();
      await wealth.photos.deleteSnapshot(Month(2026, 1));
      local.categoryInvalidation.invalidate();
      await settle();
      expect(find.text('Código: foto_ausente'), findsOneWidget);
      await capture(tester, '320-200-foto-ausente');
      await wealth.photos.setValue(Month(2026, 1), accounts.first.id, 0);
      local.categoryInvalidation.invalidate();
      await settle();
      expect(find.text('Código: foto_incompleta'), findsOneWidget);
      await capture(tester, '320-200-foto-incompleta');
      for (final account in accounts) {
        await wealth.photos.setValue(Month(2026, 1), account.id, 0);
      }
      local.categoryInvalidation.invalidate();
      await settle();
      expect(find.text('0,00 meses'), findsOneWidget);
      await capture(tester, '320-200-cero');
      final repo = SqliteBudgetRepository(db);
      final budgets = await repo.readYear(2026, incomeOnly: true);
      for (final budget in budgets) {
        await repo.edit(
          budget.id,
          BudgetInput(
            month: budget.data.month,
            categoryId: budget.data.categoryId,
            amountCents: 0,
          ),
        );
      }
      local.categoryInvalidation.invalidate();
      await settle();
      expect(find.text('Código: ingresos_nulos'), findsOneWidget);
      await capture(tester, '320-200-ingresos-nulos');
      await repo.edit(
        budgets.first.id,
        BudgetInput(
          month: budgets.first.data.month,
          categoryId: budgets.first.data.categoryId,
          amountCents: -1,
        ),
      );
      local.categoryInvalidation.invalidate();
      await settle();
      expect(find.text('Código: ingresos_negativos'), findsOneWidget);
      await capture(tester, '320-200-ingresos-negativos');
      await repo.delete(budgets[2].id);
      local.categoryInvalidation.invalidate();
      await settle();
      expect(find.text('Código: ingresos_incompletos'), findsOneWidget);
      expect(find.text('Completar marzo 2026'), findsOneWidget);
      await capture(tester, '320-200-ingresos-incompletos');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await local.store.close();
      local.controller.dispose();
      await local.categoryInvalidation.close();
      navigation.dispose();
      await binding.setSurfaceSize(null);
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
