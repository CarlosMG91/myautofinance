import '../domain/movement_management.dart';
import '../domain/movement_repository.dart';
import '../domain/category_management.dart';

/// Proyección del catálogo propietario, sin dependencia movimientos → patrimonio.
class MovementAccountOption {
  const MovementAccountOption(this.id, this.name, this.from, this.through);
  final String id, name, from;
  final String? through;
  bool eligible(ValueDate date) {
    final month = '${date.value.substring(0, 7)}-01';
    return month.compareTo(from) >= 0 &&
        (through == null || month.compareTo(through!) <= 0);
  }
}

class MovementEditorSource {
  const MovementEditorSource({
    required this.management,
    required this.accounts,
    required this.categories,
  });
  final MovementManagement management;
  final Future<List<MovementAccountOption>> Function() accounts;
  final Future<List<CategoryDetails>> Function() categories;
}

typedef MovementEditorLoader = Future<MovementEditorSource> Function();
