import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/local_backup_creation.dart';

const maxBackupCounter = 9223372036854775807;
final backupUuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final datasetUuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final backupHash = RegExp(r'^[0-9a-f]{64}$');

Never invalidBackupMetadata() =>
    throw const LocalBackupFailure(LocalBackupFailureCode.invalidMetadata);

String backupUtc(DateTime value) {
  final utc = value.toUtc();
  if (utc.year < 1 || utc.year > 9999) invalidBackupMetadata();
  return DateTime.utc(
    utc.year,
    utc.month,
    utc.day,
    utc.hour,
    utc.minute,
    utc.second,
    utc.millisecond,
  ).toIso8601String();
}

void checkBackupUtc(Object? value) {
  if (value is! String ||
      !RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$').hasMatch(value) ||
      backupUtc(DateTime.parse(value)) != value) {
    invalidBackupMetadata();
  }
}

int backupCounter(Object? value, {bool positive = true}) {
  if (value is! String || !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value)) {
    invalidBackupMetadata();
  }
  final parsed = BigInt.parse(value);
  if (parsed > BigInt.from(maxBackupCounter) ||
      parsed < BigInt.from(positive ? 1 : 0)) {
    invalidBackupMetadata();
  }
  return parsed.toInt();
}

Map<String, dynamic> backupObject(Object? value, Set<String> fields) {
  if (value is! Map<String, dynamic> ||
      value.length != fields.length ||
      !value.keys.every(fields.contains)) {
    invalidBackupMetadata();
  }
  return value;
}

/// Detecta claves repetidas antes de jsonDecode (que conserva solo la última).
Object? _decode(String source) {
  if (source.startsWith('\uFEFF')) invalidBackupMetadata();
  final tokens = RegExp(r'"(?:[^"\\]|\\.)*"|[{}\[\]:,]|[^\s{}\[\]:,]+')
      .allMatches(source)
      .toList();
  final stack = <Set<String>?>[];
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i][0]!;
    if (token == '{') stack.add(<String>{});
    if (token == '[') stack.add(null);
    if (token == '}' || token == ']') {
      if (stack.isEmpty) invalidBackupMetadata();
      stack.removeLast();
    }
    if (token.startsWith('"') &&
        i + 1 < tokens.length &&
        tokens[i + 1][0] == ':') {
      if (stack.isEmpty ||
          stack.last == null ||
          !stack.last!.add(jsonDecode(token) as String)) {
        invalidBackupMetadata();
      }
    }
  }
  return jsonDecode(source);
}

String backupPayloadHash(Map<String, dynamic> payload) =>
    sha256.convert(utf8.encode(jsonEncode(payload))).toString();

List<int> encodeBackupEnvelope(Map<String, dynamic> payload) {
  final text = jsonEncode(payload);
  return utf8.encode(
    jsonEncode({
      'payload': text,
      'payloadSha256': sha256.convert(utf8.encode(text)).toString(),
    }),
  );
}

Map<String, dynamic> decodeBackupEnvelope(List<int> bytes) {
  try {
    if (bytes.length >= 3 &&
        bytes[0] == 239 &&
        bytes[1] == 187 &&
        bytes[2] == 191) {
      invalidBackupMetadata();
    }
    final envelope = backupObject(_decode(utf8.decode(bytes)), {
      'payload',
      'payloadSha256',
    });
    final payload = envelope['payload'];
    if (payload is! String ||
        envelope['payloadSha256'] !=
            sha256.convert(utf8.encode(payload)).toString()) {
      invalidBackupMetadata();
    }
    final decoded = _decode(payload);
    if (decoded is! Map<String, dynamic>) invalidBackupMetadata();
    return decoded;
  } on LocalBackupFailure {
    rethrow;
  } catch (_) {
    invalidBackupMetadata();
  }
}
