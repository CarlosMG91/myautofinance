import 'package:uuid/uuid.dart';

import '../../../features/movements/movements.dart';
import 'local_database.dart';

/// Adaptador compartido compuesto por app, sin dependencias de dominio a Drift.
final class SqliteCategoryRepository implements CategoryRepository {
  SqliteCategoryRepository(this.database);
  final LocalDatabase database;

  String _timestamp() => DateTime.fromMillisecondsSinceEpoch(
    DateTime.now().millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();

  @override
  Future<List<CategoryNode>> list({bool includeArchived = true}) async {
    final rows = await database.customSelect('''
WITH RECURSIVE tree(id,parent_id,name,income,archived,depth) AS (
 SELECT id,parent_id,name,is_income,archived,1 FROM categories WHERE parent_id IS NULL
 UNION ALL
 SELECT c.id,c.parent_id,c.name,t.income,c.archived,t.depth+1
 FROM categories c JOIN tree t ON c.parent_id=t.id
) SELECT * FROM tree ORDER BY depth,name,id
''').get();
    return rows
        .where((r) => includeArchived || r.read<int>('archived') == 0)
        .map(
          (r) => CategoryNode(
            id: r.read<String>('id'),
            parentId: r.readNullable<String>('parent_id'),
            name: r.read<String>('name'),
            isIncome: r.read<int>('income') == 1,
            archived: r.read<int>('archived') == 1,
            depth: r.read<int>('depth'),
          ),
        )
        .toList();
  }

  @override
  Future<CategoryNode?> get(String id) async {
    for (final node in await list()) {
      if (node.id == id) return node;
    }
    return null;
  }

  Future<void> _validate(
    String id,
    String name,
    String? parentId,
    bool? income,
  ) async {
    if (name.trim().isEmpty) {
      throw const CategoryFailure('El nombre no puede estar vacío.');
    }
    if ((parentId == null && income == null) ||
        (parentId != null && income != null)) {
      throw const CategoryFailure(
        'La marca de ingreso se define solo en la raíz.',
      );
    }
    final nodes = {for (final n in await list()) n.id: n};
    if (parentId != null && !nodes.containsKey(parentId)) {
      throw const CategoryFailure('El padre no existe.');
    }
    if (parentId != null && nodes[parentId]!.archived) {
      throw const CategoryFailure('El padre está archivado.');
    }
    final parents = {
      for (final n in nodes.values) n.id: n.parentId,
      id: parentId,
    };
    for (final nodeId in parents.keys) {
      final seen = <String>{};
      String? current = nodeId;
      while (current != null) {
        if (!seen.add(current)) {
          throw const CategoryFailure('La rama contiene un ciclo.');
        }
        if (seen.length > 3) {
          throw const CategoryFailure('Solo se permiten tres niveles.');
        }
        current = parents[current];
      }
    }
    final old = nodes[id];
    if (old != null &&
        (old.parentId != parentId ||
            (parentId == null && old.isIncome != income))) {
      final branch = <String>{id};
      for (var i = 0; i < 3; i++) {
        branch.addAll(
          nodes.values
              .where((n) => branch.contains(n.parentId))
              .map((n) => n.id)
              .toList(),
        );
      }
      // Las tablas se incorporan en sus tickets. Nunca reinterpretar referencias.
      final tables = await database
          .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
          .get();
      for (final table in ['movements', 'budgets']) {
        if (tables.any((r) => r.read<String>('name') == table)) {
          final refs = await database
              .customSelect(
                'SELECT category_id FROM $table WHERE category_id IS NOT NULL',
              )
              .get();
          if (refs.any((r) => branch.contains(r.read<String>('category_id')))) {
            throw const CategoryFailure(
              'Una rama con historia no puede cambiar de padre ni de ingreso.',
            );
          }
        }
      }
    }
  }

  @override
  Future<CategoryNode> create({
    required String name,
    String? parentId,
    bool? isIncome,
  }) => database.transaction(() async {
    final id = const Uuid().v4();
    await _validate(
      id,
      name,
      parentId,
      isIncome ?? (parentId == null ? false : null),
    );
    final now = _timestamp();
    await database.customStatement(
      'INSERT INTO categories(id,parent_id,name,is_income,archived,created_at,updated_at) VALUES (?,?,?,?,0,?,?)',
      [
        id,
        parentId,
        name,
        isIncome == null ? (parentId == null ? 0 : null) : (isIncome ? 1 : 0),
        now,
        now,
      ],
    );
    return (await get(id))!;
  });

  @override
  Future<CategoryNode> edit(
    String id, {
    required String name,
    required String? parentId,
    required bool? isIncome,
  }) => database.transaction(() async {
    final old = await get(id);
    if (old == null) throw const CategoryFailure('La categoría no existe.');
    await _validate(id, name, parentId, isIncome);
    if (old.name == name &&
        old.parentId == parentId &&
        (parentId != null || old.isIncome == isIncome)) {
      return old;
    }
    await database.customStatement(
      'UPDATE categories SET name=?,parent_id=?,is_income=?,updated_at=? WHERE id=?',
      [
        name,
        parentId,
        isIncome == null ? null : (isIncome ? 1 : 0),
        _timestamp(),
        id,
      ],
    );
    return (await get(id))!;
  });

  @override
  Future<void> setArchived(String id, {required bool archived}) =>
      database.transaction(() async {
        if (await get(id) == null) {
          throw const CategoryFailure('La categoría no existe.');
        }
        if (!archived) {
          final node = (await get(id))!;
          if (node.parentId != null && (await get(node.parentId!))!.archived) {
            throw const CategoryFailure('Reactiva primero la rama padre.');
          }
        }
        await database.customStatement(
          '''
WITH RECURSIVE branch(id) AS (
 SELECT id FROM categories WHERE id=? UNION ALL
 SELECT c.id FROM categories c JOIN branch b ON c.parent_id=b.id
) UPDATE categories SET archived=?,updated_at=? WHERE id IN (SELECT id FROM branch) AND archived<>?
''',
          [id, archived ? 1 : 0, _timestamp(), archived ? 1 : 0],
        );
      });
}
