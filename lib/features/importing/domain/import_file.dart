import 'import_batch.dart';

/// SHA-256 hexadecimal de los bytes completos, sin normalizarlos.
abstract interface class ImportFingerprint {
  String ofBytes(List<int> bytes);
}

/// Archivo privado de la sesión en memoria. Nunca se persisten estos bytes.
final class ImportFile {
  factory ImportFile.fromBytes({
    required List<int> bytes,
    required ImportFingerprint fingerprint,
    required ImportSource source,
    required String originalName,
  }) {
    if (originalName.trim().isEmpty ||
        originalName.contains('/') ||
        originalName.contains('\\') ||
        originalName.contains('\u0000') ||
        bytes.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('Nombre de archivo o bytes inválidos.');
    }
    final snapshot = List<int>.unmodifiable(bytes);
    final digest = fingerprint.ofBytes(snapshot);
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      throw ArgumentError('Huella SHA-256 inválida.');
    }
    return ImportFile._(snapshot, digest, source, originalName);
  }

  const ImportFile._(this.bytes, this.sha256, this.source, this.originalName);

  final List<int> bytes;
  final String sha256, originalName;
  final ImportSource source;

  /// El confirmador debe repetir esta comprobación dentro de su flujo vigente.
  bool matchesFingerprint(ImportFingerprint fingerprint) =>
      fingerprint.ofBytes(bytes) == sha256;
}
