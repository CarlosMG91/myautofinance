import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/navigation/app_routes.dart';
import 'package:myautofinance/app/wealth_management_factory.dart';
import 'package:myautofinance/features/movements/presentation/category_selector.dart';
import 'package:myautofinance/features/wealth/wealth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final captures = <String, String>{};
  binding.reportData = {'catalogCaptures': captures};
  testWidgets('Catálogos nativos con SQLite sintético y reflujo 200 %', (
    tester,
  ) async {
    final db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    final categories = createCategoryManagement(database: db);
    final wealth = createWealthManagement(database: db);
    final root = await categories.create(
      name: 'Ingresos sintéticos',
      isIncome: true,
    );
    final child = await categories.create(
      name: 'Trabajo',
      parentId: root.node.id,
    );
    await categories.create(name: 'Nómina', parentId: child.node.id);
    final archived = await categories.create(
      name: 'Histórico',
      isIncome: false,
    );
    await categories.archive(archived.node.id);
    final account = await wealth.create(
      name: 'Cuenta sintética',
      kind: AccountKind.account,
      activeFrom: Month(2026, 1),
      liquidity: Liquidity.liquid,
    );
    await wealth.changeLiquidity(
      account.account.id,
      Month(2026, 3),
      Liquidity.medium,
    );
    await wealth.create(
      name: 'Cartera sintética',
      kind: AccountKind.portfolio,
      activeFrom: Month(2026, 1),
      liquidity: Liquidity.illiquid,
    );
    await wealth.create(
      name: 'Deuda histórica',
      kind: AccountKind.debt,
      activeFrom: Month(2025, 1),
      activeThrough: Month(2026, 2),
    );
    final captureKey = GlobalKey();
    final support = await getApplicationSupportDirectory();
    final destination = await Directory(
      p.join(support.path, 'catalog-redesign-synthetic-captures'),
    ).create(recursive: true);
    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    Future<void> press(String text) async {
      await tester.ensureVisible(find.text(text).last);
      await tester.tap(find.text(text).last);
      await settle();
    }

    Future<void> capture(String name) async {
      final boundary =
          captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = p.join(
        destination.path,
        '${Platform.operatingSystem}-$name.png',
      );
      await File(file).writeAsBytes(bytes!.buffer.asUint8List());
      captures['${Platform.operatingSystem}-$name.png'] = base64Encode(
        bytes.buffer.asUint8List(),
      );
      image.dispose();
      debugPrint('CATALOG_CAPTURE: $file');
    }

    try {
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: MediaQuery(
              data: MediaQueryData.fromView(tester.view)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: AutofinanceApp(
                categories: () async => categories,
                wealth: () async => wealth,
              ),
            ),
          ),
        );
        await settle();
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        navigator.pushNamed(AppRoutes.categories);
        await settle();
        await press('Mostrar también archivadas');
        expect(find.text('Archivada'), findsOneWidget);
        await capture('arbol-${scale.toInt()}');
        await press('Crear categoría');
        await press('Crear categoría');
        expect(find.text('El nombre no puede estar vacío.'), findsWidgets);
        await capture('categoria-${scale.toInt()}');
        await tester.binding.handlePopRoute();
        await settle();
        navigator.push(
          MaterialPageRoute<void>(
            builder: (context) => CategorySelector(
              loadManagement: () async => categories,
              selectedId: child.node.id,
              onReturn: (_) => Navigator.pop(context),
              onCreate: () async => null,
            ),
          ),
        );
        await settle();
        await capture('selector-${scale.toInt()}');
        await press('Cancelar');
        navigator.pop();
        await settle();
        navigator.pushNamed(AppRoutes.accounts);
        await settle();
        expect(find.text('Deuda histórica'), findsOneWidget);
        expect(
          MediaQuery.textScalerOf(tester.element(find.text('Fichas')))
              .scale(16),
          16 * scale,
        );
        await capture('fichas-${scale.toInt()}');
        await press('Cuenta sintética');
        await capture('detalle-${scale.toInt()}');
        await press('Corregir liquidez histórica');
        await capture('liquidez-${scale.toInt()}');
        await tester.binding.handlePopRoute();
        await settle();
        await tester.pumpWidget(const SizedBox.shrink());
        await settle();
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await categories.invalidation.close();
      await db.close();
    }
  });
}
