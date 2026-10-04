import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/local_backup_session.dart';
import 'package:myautofinance/app/navigation/app_routes.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Recorrido de interfaz con SQLite privado y sintético en Windows/Android.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Gestión nativa: alta, cancelación, traslado, archivo y reapertura',
    (tester) async {
      final support = await getApplicationSupportDirectory();
      final fixtures = await Directory(
        p.join(support.path, 'category-ui-tests'),
      ).create(recursive: true);
      final directory = await fixtures.createTemp('synthetic-');
      final session = LocalBackupSession(
        supportDirectory: () async => directory,
      );
      try {
        expect(await session.open(), true);
        var service = await session.categories();
        final income = await service.create(name: 'INGRESOS', isIncome: true);
        final expense = await service.create(name: 'GASTOS');
        await tester.pumpWidget(AutofinanceApp(localSession: session));
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        Future<void> wait() async {
          for (var i = 0; i < 8; i++) {
            await tester.pumpAndSettle();
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }

        Future<void> tap(String text) async {
          final buttons = find.ancestor(
            of: find.text(text),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is ButtonStyleButton ||
                  widget is PopupMenuItem ||
                  widget is PopupMenuButton,
            ),
          );
          final target = buttons.evaluate().isEmpty
              ? find.text(text).last
              : buttons.last;
          await tester.ensureVisible(target);
          await tester.tap(target);
          await wait();
        }

        Future<void> parent(CategoryDetails item) async {
          await tester.ensureVisible(find.byType(OutlinedButton).first);
          await tester.tap(find.byType(OutlinedButton).first);
          await wait();
          await tap('${item.path} · ${item.node.id}');
        }

        await tap('Gestión');
        await tap('Categorías');
        await tap('Crear categoría');
        await tester.enterText(find.byType(TextField), 'SALARIO');
        await parent(income);
        await tap('Crear categoría');
        final salary = (await service.list()).singleWhere(
          (item) => item.node.name == 'SALARIO',
        );
        expect(salary.path, 'INGRESOS / SALARIO');
        navigator.pushNamed('${AppRoutes.categories}/${salary.node.id}');
        await wait();
        await tester.enterText(find.byType(TextField), 'NO GUARDAR');
        await tap('Cancelar');
        await tap('Descartar cambios');
        expect((await service.get(salary.node.id)).node.name, 'SALARIO');
        navigator.pushNamed('${AppRoutes.categories}/${salary.node.id}');
        await wait();
        await parent(expense);
        await tap('Revisar y guardar');
        await tap('Trasladar rama');
        expect((await service.get(salary.node.id)).path, 'GASTOS / SALARIO');
        expect((await service.get(salary.node.id)).node.isIncome, false);
        navigator.pushNamed('${AppRoutes.categories}/${salary.node.id}');
        await wait();
        await tap('Archivar rama completa');
        await tap('Archivar rama');
        expect((await service.get(salary.node.id)).node.archived, true);
        await session.store.close();
        service = await session.categories();
        expect((await service.get(salary.node.id)).path, 'GASTOS / SALARIO');
        expect((await service.get(salary.node.id)).node.archived, true);
        expect((await (await session.store.open()).readState()).revision, 5);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        await session.store.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
