import 'dart:typed_data';

/// Una carga local, sin rutas, decodificación ni persistencia.
abstract interface class LocalFileSelector {
  Future<LocalFileSelection> select();
}

sealed class LocalFileSelection {
  const LocalFileSelection();
}

final class LocalFileSelected extends LocalFileSelection {
  LocalFileSelected({required this.name, required Uint8List bytes})
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  final String name;
  final Uint8List bytes;
}

final class LocalFileCancelled extends LocalFileSelection {
  const LocalFileCancelled();
}

enum LocalFileFailureCode { accessDenied, unavailable, readFailed, busy }

final class LocalFileFailed extends LocalFileSelection {
  const LocalFileFailed(this.code);
  final LocalFileFailureCode code;
}
