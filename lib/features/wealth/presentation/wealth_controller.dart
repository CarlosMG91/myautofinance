import '../domain/wealth_management.dart';
import '../domain/account_repository.dart';
import '../domain/wealth_repository.dart';

typedef WealthManagementLoader = Future<WealthManagement> Function();

/// Resuelve la conexión por consulta, sin retener repositorios tras restaurar.
final class WealthController {
  WealthController({required this._loadManagement});
  final WealthManagementLoader _loadManagement;

  Future<List<AccountRecord>> catalog() async =>
      (await _loadManagement()).catalog();
  Future<AccountDetails> details(String id) async =>
      (await _loadManagement()).details(id);
  Future<WealthSnapshot> month(Month month) async =>
      (await _loadManagement()).photos.read(month);
  Future<List<WealthSnapshot>> year(int year) async =>
      (await _loadManagement()).photos.readYear(year);
}
