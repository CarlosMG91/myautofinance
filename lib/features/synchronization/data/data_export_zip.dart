import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../domain/data_export.dart';

/// ZIP estándar método STORE. Sin buffers de archivo completo ni dependencia
/// nativa; límite explícito <4 GiB (no se produce un ZIP64 truncado).
final class ExportZipFile {
  const ExportZipFile(this.path, this.size, this.sha, this.crc, this.rows);
  final String path;
  final int size;
  final String sha;
  final int crc;
  final int? rows;
  Map<String, Object?> toJson() => {
    'path': path,
    'mediaType': path.endsWith('.csv')
        ? 'text/csv'
        : path.endsWith('.json')
        ? 'application/json'
        : 'text/markdown',
    'rowCount': rows?.toString(),
    'sizeBytes': '$size',
    'sha256': sha,
  };
}

Future<ExportZipFile> describeExportFile(
  File file,
  String path,
  DataExportCancellation cancellation,
  int? rows,
) async {
  final check = _Check(path.endsWith('.csv'));
  await for (final bytes in file.openRead()) {
    cancellation.check();
    check.add(bytes);
  }
  final result = check.finish(path);
  if (result.rows != rows || result.size <= 0) _invalid();
  return result;
}

Future<void> createAndVerifyExportZip({
  required Directory stage,
  required File zip,
  required List<ExportZipFile> files,
  required DataExportCancellation cancellation,
  required int maxBytes,
}) async {
  if (maxBytes <= 0 ||
      maxBytes > 0xffffffff ||
      files.length > 65535 ||
      files.map((f) => f.path.toLowerCase()).toSet().length != files.length) {
    _invalid();
  }
  final localHeaders = <List<int>>[];
  final centralHeaders = <List<int>>[];
  var offset = 0;
  for (final file in files) {
    if (!RegExp(r'^[A-Za-z_]+\.(csv|json|md)$').hasMatch(file.path)) _invalid();
    final name = utf8.encode(file.path);
    final local = _Bytes()
      ..u32(0x04034b50)
      ..u16(20)
      ..u16(0x800)
      ..u16(0)
      ..u16(0)
      ..u16(33)
      ..u32(file.crc)
      ..u32(file.size)
      ..u32(file.size)
      ..u16(name.length)
      ..u16(0)
      ..add(name);
    final central = _Bytes()
      ..u32(0x02014b50)
      ..u16(20)
      ..u16(20)
      ..u16(0x800)
      ..u16(0)
      ..u16(0)
      ..u16(33)
      ..u32(file.crc)
      ..u32(file.size)
      ..u32(file.size)
      ..u16(name.length)
      ..u16(0)
      ..u16(0)
      ..u16(0)
      ..u16(0)
      ..u32(0)
      ..u32(offset)
      ..add(name);
    localHeaders.add(local.bytes);
    centralHeaders.add(central.bytes);
    offset += local.bytes.length + file.size;
  }
  final centralSize = centralHeaders.fold<int>(0, (n, h) => n + h.length);
  final end = _Bytes()
    ..u32(0x06054b50)
    ..u16(0)
    ..u16(0)
    ..u16(files.length)
    ..u16(files.length)
    ..u32(centralSize)
    ..u32(offset)
    ..u16(0);
  if (offset + centralSize + end.bytes.length > maxBytes) {
    throw const DataExportFailure(DataExportFailureCode.limitExceeded);
  }
  final output = await zip.open(mode: FileMode.writeOnly);
  try {
    for (var i = 0; i < files.length; i++) {
      cancellation.check();
      await output.writeFrom(localHeaders[i]);
      await for (final bytes in File(
        '${stage.path}/${files[i].path}',
      ).openRead()) {
        cancellation.check();
        await output.writeFrom(bytes);
      }
    }
    for (final header in centralHeaders) {
      await output.writeFrom(header);
    }
    await output.writeFrom(end.bytes);
    await output.flush();
  } finally {
    await output.close();
  }
  // Reabre el archivo final. Verifica inventario/directorios y todos los bytes
  // descomprimidos, CRC, SHA-256, tamaños y registros lógicos CSV.
  final input = await zip.open();
  try {
    for (var i = 0; i < files.length; i++) {
      await _expectBytes(input, localHeaders[i]);
      final expected = files[i];
      final check = _Check(expected.rows != null);
      var remaining = expected.size;
      while (remaining > 0) {
        cancellation.check();
        final bytes = await input.read(remaining < 65536 ? remaining : 65536);
        if (bytes.isEmpty) _invalid();
        check.add(bytes);
        remaining -= bytes.length;
      }
      final actual = check.finish(expected.path);
      if (actual.sha != expected.sha ||
          actual.crc != expected.crc ||
          actual.size != expected.size ||
          actual.rows != expected.rows) {
        _invalid();
      }
    }
    for (final header in centralHeaders) {
      await _expectBytes(input, header);
    }
    await _expectBytes(input, end.bytes);
    if ((await input.read(1)).isNotEmpty) _invalid();
    cancellation.check();
  } finally {
    await input.close();
  }
}

Future<void> _expectBytes(RandomAccessFile input, List<int> expected) async {
  final actual = await input.read(expected.length);
  if (actual.length != expected.length) _invalid();
  for (var i = 0; i < actual.length; i++) {
    if (actual[i] != expected[i]) _invalid();
  }
}

Never _invalid() =>
    throw const DataExportFailure(DataExportFailureCode.storage);

final class _Bytes {
  final bytes = <int>[];
  void add(List<int> value) => bytes.addAll(value);
  void u16(int n) =>
      add((ByteData(2)..setUint16(0, n, Endian.little)).buffer.asUint8List());
  void u32(int n) =>
      add((ByteData(4)..setUint32(0, n, Endian.little)).buffer.asUint8List());
}

final class _Digest implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

final _crcTable = List<int>.generate(256, (n) {
  for (var j = 0; j < 8; j++) {
    n = (n & 1) != 0 ? 0xedb88320 ^ (n >>> 1) : n >>> 1;
  }
  return n;
});

final class _Check {
  _Check(this.csv) {
    hash = sha256.startChunkedConversion(digest);
  }
  final bool csv;
  final digest = _Digest();
  late final ByteConversionSink hash;
  int size = 0;
  int crc = 0xffffffff;
  bool quoted = false;
  int previous = -1;
  int records = 0;
  void add(List<int> bytes) {
    hash.add(bytes);
    size += bytes.length;
    for (final byte in bytes) {
      crc = _crcTable[(crc ^ byte) & 255] ^ (crc >>> 8);
      if (csv) {
        if (byte == 34) quoted = !quoted;
        if (!quoted && previous == 13 && byte == 10) records++;
        previous = byte;
      }
    }
  }

  ExportZipFile finish(String path) {
    hash.close();
    if (csv && (quoted || previous != 10 || records < 1)) _invalid();
    return ExportZipFile(
      path,
      size,
      digest.value.toString(),
      crc ^ 0xffffffff,
      csv ? records - 1 : null,
    );
  }
}
