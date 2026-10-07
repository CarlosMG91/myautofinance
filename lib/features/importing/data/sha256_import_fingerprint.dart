import 'package:crypto/crypto.dart';

import '../domain/import_file.dart';

/// Adaptador técnico; app lo inyecta, el dominio no depende de crypto.
final class Sha256ImportFingerprint implements ImportFingerprint {
  const Sha256ImportFingerprint();

  @override
  String ofBytes(List<int> bytes) => sha256.convert(bytes).toString();
}
