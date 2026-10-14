import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/annual_actual_query_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/movement_list_factory.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/ui/autofinance_ui.dart';

import '../test/support/recovery_reference.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  final captures = <String, String>{};
  binding.reportData = {
    'actualCaptures': captures,
    'syntheticDataOnly': true,
    'origin': 'Native Flutter RenderRepaintBoundary',
    'platform': Platform.operatingSystem,
  };
  testWidgets('MA-TSK-176 resumen, detalle y retorno nativos con caso F', (
    tester,
  ) async {
    final db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
    final invalidation = CategoryReadInvalidation();
    final session = NavigationSession(
      initialContext: NavigationContext(
        destination: SessionDestination.actual,
        period: NavigationPeriod(2026, 1),
      ),
    );
    final boundary = GlobalKey();
    await seedRecoveryReference(db);
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

    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await settle();
    }

    Future<void> capture(String name) async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final picture = await render.toImage();
      final bytes = (await picture.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      picture.dispose();
      captures['${Platform.operatingSystem}-$name.png'] = base64Encode(bytes);
    }

    try {
      await binding.setSurfaceSize(
        Platform.isWindows ? const Size(1440, 900) : const Size(412, 915),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: AutofinanceApp(
            navigationSession: session,
            annualActual: () async => createAnnualActualQuery(
              database: db,
              invalidation: invalidation,
            ),
            movements: () async => createMovementListSource(db, invalidation),
          ),
        ),
      );
      await settle();
      expect(find.text('+2.329,65'), findsOneWidget);
      await capture('resumen');
      await tap(find.byKey(const Key('actual-show-detail')));
      if (Platform.isWindows) {
        final table = tester.widget<AfDetailTable>(find.byType(AfDetailTable));
        expect(table.columns, hasLength(13));
        table.rows.singleWhere((r) => r.label == 'Alimentación').onExpand!();
        await settle();
      }
      await capture('detalle');
      await tap(find.byKey(const ValueKey('actual-all:1')));
      expect(find.text('Café'), findsWidgets);
      await tap(find.text('Volver a Real anual, 2026'));
      expect(session.period, NavigationPeriod(2026, 1));
      await tap(find.text('Volver al resumen'));
      expect(find.byType(AfTimeChart), findsOneWidget);
      expect(find.text('+2.329,65'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await binding.setSurfaceSize(null);
      session.dispose();
      await invalidation.close();
      await db.close();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
