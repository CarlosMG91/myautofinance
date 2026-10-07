import 'dart:typed_data';

/// Una carga local, sin rutas, decodificación ni persistencia.
abstract interface class LocalCsvSelector {
  Future<LocalCsvSelection> select();
}

sealed class LocalCsvSelection {
  const LocalCsvSelection();
}

final class LocalCsvSelected extends LocalCsvSelection {
  LocalCsvSelected({required this.name, required Uint8List bytes})
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  final String name;
  final Uint8List bytes;
}

final class LocalCsvCancelled extends LocalCsvSelection {
  const LocalCsvCancelled();
}

enum LocalCsvFailureCode { accessDenied, unavailable, readFailed, busy }

final class LocalCsvFailed extends LocalCsvSelection {
  const LocalCsvFailed(this.code);
  final LocalCsvFailureCode code;
}
