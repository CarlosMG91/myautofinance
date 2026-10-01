enum DatabaseFailureCode { futureVersion, incompatible, open, close, backup }

/// Mensaje público controlado; no incluye rutas privadas ni SQL del usuario.
final class DatabaseFailure implements Exception {
  const DatabaseFailure(this.code);

  final DatabaseFailureCode code;

  String get message => switch (code) {
    DatabaseFailureCode.backup => 'No se pudo crear una copia local válida. Los datos locales siguen disponibles.',
    DatabaseFailureCode.futureVersion =>
      'La base pertenece a una versión más reciente de Autofinance. '
          'Actualiza la aplicación para abrirla.',
    DatabaseFailureCode.incompatible =>
      'La base local no es compatible o está dañada. '
          'Se han conservado sus datos; revisa una copia antes de continuar.',
    DatabaseFailureCode.open =>
      'No se pudo abrir la base local. Revisa el acceso al almacenamiento '
          'y vuelve a intentarlo.',
    DatabaseFailureCode.close => 'No se pudo cerrar la base local. Vuelve a intentarlo antes de continuar.',
  };

  @override
  String toString() => message;
}
