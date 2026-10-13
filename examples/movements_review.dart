import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:myautofinance/app/app.dart';
import 'package:myautofinance/app/category_management_factory.dart';
import 'package:myautofinance/app/data/sqlite/local_database.dart';
import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_account_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_category_repository.dart';
import 'package:myautofinance/app/data/sqlite/sqlite_import_batch_repository.dart';
import 'package:myautofinance/app/movement_list_factory.dart';
import 'package:myautofinance/app/pending_movement_factory.dart';
import 'package:myautofinance/app/navigation/navigation_context.dart';
import 'package:myautofinance/app/navigation/navigation_period.dart';
import 'package:myautofinance/app/navigation/navigation_session.dart';
import 'package:myautofinance/features/importing/importing.dart';
import 'package:myautofinance/features/movements/movements.dart';
import 'package:myautofinance/features/wealth/wealth.dart';

/// Muestra explícita: SQLite en memoria, sin archivos personales ni red.
Future<MovementReviewData> createMovementReviewData() async {
  final db = LocalDatabase(NativeDatabase.memory(setup: configureConnection));
  final invalidation = CategoryReadInvalidation();
  final account = await SqliteAccountRepository(db).create(
    name: 'Cuenta de prueba',
    kind: AccountKind.account,
    activeFrom: Month(2026, 1),
    liquidity: Liquidity.liquid,
  );
  final category = (await SqliteCategoryRepository(
    db,
  ).create(name: 'Vida diaria')).id;
  await SqliteImportBatchRepository(db).create(
    sha256: 'e' * 64,
    source: ImportSource.historicalCsv,
    originalName: 'muestra-sintetica.csv',
    contractVersion: '1',
    movements: [
      for (final (i, item) in [
        ('Compra semanal', -6534, category),
        ('Café', -320, null),
        ('Café', -320, null),
        ('Abono de prueba', 7174, null),
      ].indexed)
        ImportedMovement(
          i + 2,
          MovementInput(
            accountId: account.id,
            valueDate: ValueDate(2026, 3, 15),
            concept: item.$1,
            amountCents: item.$2,
            categoryId: item.$3,
            discretion: 'Texto sintético conservado',
          ),
        ),
    ],
    budgets: [],
  );
  final session = NavigationSession(
    initialContext: NavigationContext(
      destination: SessionDestination.movements,
      period: NavigationPeriod(2026, 3),
    ),
  );
  return MovementReviewData(db, invalidation, session);
}

class MovementReviewData {
  MovementReviewData(this.db, this.invalidation, this.session);
  final LocalDatabase db;
  final CategoryReadInvalidation invalidation;
  final NavigationSession session;
  Widget app() => AutofinanceApp(
    navigationSession: session,
    movements: () async => createMovementListSource(db, invalidation),
    pendingMovements: () async => createPendingMovementSource(db, invalidation),
    categories: () async =>
        createCategoryManagement(database: db, invalidation: invalidation),
  );
  Future<void> close() async {
    session.dispose();
    await invalidation.close();
    await db.close();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final fixture = await createMovementReviewData();
  runApp(fixture.app());
}
