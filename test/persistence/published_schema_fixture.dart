import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:sqlite3/sqlite3.dart';

/// Solo fixtures: vuelve a los triggers publicados v6 antes de retirar tablas
/// para construir versiones anteriores. Nunca se usa como migración de app.
void usePublishedV6CategoryTriggers(Database db) {
  for (final sql in categoryReorganizationObjects) {
    final name = RegExp(r'CREATE TRIGGER (\w+)').firstMatch(sql)![1]!;
    db.execute('DROP TRIGGER $name');
  }
  db.execute(
    budgetSchemaObjects.singleWhere(
      (sql) => sql.contains('categories_budget_history'),
    ),
  );
}
