import 'package:myautofinance/app/data/sqlite/schema_policy.dart';
import 'package:sqlite3/sqlite3.dart';

/// Solo fixtures: vuelve a los triggers publicados v6 antes de retirar tablas
/// para construir versiones anteriores. Nunca se usa como migración de app.
void usePublishedV6CategoryTriggers(Database db) {
  usePublishedV7ImportSchema(db);
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

/// Solo fixtures: retirar la extensión v8 antes de construir una base previa.
void usePublishedV7ImportSchema(Database db) {
  for (final sql in importOriginalSchemaObjects.reversed) {
    final match = RegExp(r'CREATE (TABLE|TRIGGER)\s+"?(\w+)').firstMatch(sql)!;
    db.execute('DROP ${match[1]} IF EXISTS "${match[2]}"');
  }
}
