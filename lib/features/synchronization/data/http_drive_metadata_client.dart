import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/drive_access.dart';
import '../domain/drive_metadata.dart';
import 'drive_metadata_credential.dart';

/// Drive v3 con endpoint fijo y redirects deshabilitados. El llamante conserva
/// la propiedad de client. Construirlo no hace red ni lee credenciales.
final class HttpDriveMetadataClient implements DriveMetadataClient {
  HttpDriveMetadataClient({
    required this._client,
    required this._credentials,
    DateTime Function()? now,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _now = now ?? DateTime.now;

  static const _folderFields = 'id,name,mimeType,parents,trashed,appProperties';
  static const _fileFields =
      '$_folderFields,modifiedTime,size,md5Checksum,version';
  final http.Client _client;
  final DriveMetadataCredentialSource _credentials;
  final DateTime Function() _now;
  final Duration requestTimeout;

  void _nonEmpty(String value) {
    if (value.trim().isEmpty) {
      throw const DriveMetadataFailure(DriveMetadataIssue.invalidRequest);
    }
  }

  String _literal(String value) {
    _nonEmpty(value);
    return "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";
  }

  Future<String> _token(String accountId) async {
    _nonEmpty(accountId);
    final DriveMetadataCredential credential;
    try {
      credential = await _credentials
          .readCredential(accountId: accountId)
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const DriveMetadataFailure(DriveMetadataIssue.requestTimeout);
    } on DriveAccessFailure catch (failure) {
      throw DriveMetadataFailure(switch (failure.issue) {
        DriveAccessIssue.credentialExpired =>
          DriveMetadataIssue.credentialExpired,
        DriveAccessIssue.permissionDenied =>
          DriveMetadataIssue.permissionDenied,
        DriveAccessIssue.accountChangeRequired =>
          DriveMetadataIssue.accountChangeRequired,
        _ => DriveMetadataIssue.credentialUnavailable,
      });
    } catch (_) {
      throw const DriveMetadataFailure(
        DriveMetadataIssue.credentialUnavailable,
      );
    }
    final session = credential.session;
    if (session.account.permissionId != accountId ||
        (session.folder != null && session.folder!.accountId != accountId)) {
      throw const DriveMetadataFailure(
        DriveMetadataIssue.accountChangeRequired,
      );
    }
    if (session.grantedScopes.length != 1 ||
        !session.grantedScopes.contains(driveFileScope)) {
      throw const DriveMetadataFailure(DriveMetadataIssue.permissionDenied);
    }
    if (!session.validUntil.isAfter(_now())) {
      throw const DriveMetadataFailure(DriveMetadataIssue.credentialExpired);
    }
    if (!RegExp(r'^[A-Za-z0-9._~+/=-]+$').hasMatch(credential.accessToken)) {
      throw const DriveMetadataFailure(DriveMetadataIssue.invalidCredential);
    }
    return credential.accessToken;
  }

  Future<Map<String, dynamic>> _request({
    required String accountId,
    required String method,
    required Uri uri,
    Map<String, dynamic>? body,
  }) async {
    final token = await _token(accountId);
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(requestTimeout);
    } on TimeoutException {
      throw const DriveMetadataFailure(DriveMetadataIssue.requestTimeout);
    } catch (_) {
      throw const DriveMetadataFailure(DriveMetadataIssue.networkFailure);
    }
    if (response.statusCode != 200 &&
        !(method == 'POST' && response.statusCode == 201)) {
      throw _httpFailure(response);
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // No propagar datos privados contenidos en mensajes del parser.
    }
    throw const DriveMetadataFailure(DriveMetadataIssue.incompleteResponse);
  }

  DriveMetadataFailure _httpFailure(http.Response response) {
    final reasons = <String>{};
    try {
      final errors = (jsonDecode(response.body) as Map)['error']['errors'];
      if (errors is List) {
        for (final error in errors) {
          if (error is Map && error['reason'] is String) {
            reasons.add(error['reason'] as String);
          }
        }
      }
    } catch (_) {
      // La clasificación por HTTP sigue disponible sin cuerpo de error válido.
    }
    final status = response.statusCode;
    final issue = switch (status) {
      401 => DriveMetadataIssue.credentialExpired,
      403
          when reasons.any(
            {'rateLimitExceeded', 'userRateLimitExceeded'}.contains,
          ) =>
        DriveMetadataIssue.rateLimited,
      403
          when reasons.any(
            {
              'dailyLimitExceeded',
              'storageQuotaExceeded',
              'activeItemCreationLimitExceeded',
              'numChildrenInNonRootLimit',
              'myDriveHierarchyDepthLimit',
            }.contains,
          ) =>
        DriveMetadataIssue.quotaExceeded,
      403 => DriveMetadataIssue.permissionDenied,
      404 => DriveMetadataIssue.notFound,
      429 => DriveMetadataIssue.rateLimited,
      >= 500 && <= 599 => DriveMetadataIssue.serverUnavailable,
      _ => DriveMetadataIssue.invalidRequest,
    };
    Duration? retryAfter;
    if (issue == DriveMetadataIssue.rateLimited ||
        issue == DriveMetadataIssue.serverUnavailable) {
      final value = response.headers['retry-after'];
      if (value != null) {
        final seconds = int.tryParse(value);
        if (seconds != null && seconds >= 0) {
          retryAfter = Duration(seconds: seconds);
        } else {
          try {
            final delay = HttpDate.parse(value).difference(_now().toUtc());
            retryAfter = delay.isNegative ? Duration.zero : delay;
          } catch (_) {
            // Cabecera opcional inválida: no inventar un plazo.
          }
        }
      }
    }
    return DriveMetadataFailure(
      issue,
      httpStatus: status,
      retryAfter: retryAfter,
    );
  }

  DriveFileMetadata _file(dynamic value) {
    try {
      if (value is! Map<String, dynamic>) throw const FormatException();
      for (final key in ['id', 'name', 'mimeType']) {
        if (value[key] is! String || (value[key] as String).trim().isEmpty) {
          throw const FormatException();
        }
      }
      final parents = value['parents'];
      if (parents is! List ||
          parents.any((p) => p is! String || p.trim().isEmpty) ||
          value['trashed'] is! bool) {
        throw const FormatException();
      }
      int? size;
      if (value.containsKey('size')) {
        if (value['size'] is! String) throw const FormatException();
        size = int.tryParse(value['size'] as String);
        if (size == null || size < 0) throw const FormatException();
      }
      DateTime? modifiedTime;
      if (value.containsKey('modifiedTime')) {
        if (value['modifiedTime'] is! String ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$')
                .hasMatch(value['modifiedTime'] as String)) {
          throw const FormatException();
        }
        modifiedTime = DateTime.parse(value['modifiedTime'] as String).toUtc();
      }
      final checksum = value['md5Checksum'];
      if (value.containsKey('md5Checksum') &&
          (checksum is! String ||
              !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(checksum))) {
        throw const FormatException();
      }
      final version = value['version'];
      if (value.containsKey('version') &&
          (version is! String || !RegExp(r'^\d+$').hasMatch(version))) {
        throw const FormatException();
      }
      final properties = value['appProperties'];
      if (value.containsKey('appProperties') &&
          (properties is! Map<String, dynamic> ||
              properties.values.any((v) => v is! String))) {
        throw const FormatException();
      }
      return DriveFileMetadata(
        id: value['id'] as String,
        name: value['name'] as String,
        mimeType: value['mimeType'] as String,
        parents: parents.cast<String>(),
        trashed: value['trashed'] as bool,
        size: size,
        modifiedTime: modifiedTime,
        md5Checksum: checksum as String?,
        version: version as String?,
        appProperties: properties == null
            ? const {}
            : (properties as Map<String, dynamic>).cast<String, String>(),
      );
    } catch (_) {
      throw const DriveMetadataFailure(DriveMetadataIssue.incompleteResponse);
    }
  }

  @override
  Future<String> getMyDriveRootId({required String accountId}) async {
    final root = await _request(
      accountId: accountId,
      method: 'GET',
      uri: Uri.https('www.googleapis.com', '/drive/v3/files/root', {
        'fields': 'id,mimeType',
      }),
    );
    final id = root['id'];
    if (id is! String ||
        id.trim().isEmpty ||
        root['mimeType'] != driveFolderMimeType) {
      throw const DriveMetadataFailure(DriveMetadataIssue.incompleteResponse);
    }
    return id;
  }

  @override
  Future<List<DriveFileMetadata>> listFiles({
    required String accountId,
    String? parentId,
    String? name,
    String? mimeType,
    Map<String, String>? appProperties,
  }) async {
    final clauses = [
      'trashed=false',
      if (parentId != null) '${_literal(parentId)} in parents',
      if (name != null) 'name=${_literal(name)}',
      if (mimeType != null) 'mimeType=${_literal(mimeType)}',
      for (final entry in (appProperties ?? const <String, String>{}).entries)
        'appProperties has { key=${_literal(entry.key)} and value=${_literal(entry.value)} }',
    ];
    final files = <DriveFileMetadata>[];
    final seenTokens = <String>{};
    String? pageToken;
    do {
      final page = await _request(
        accountId: accountId,
        method: 'GET',
        uri: Uri.https('www.googleapis.com', '/drive/v3/files', {
          'q': clauses.join(' and '),
          'spaces': 'drive',
          'corpora': 'user',
          'includeItemsFromAllDrives': 'false',
          'pageSize': '1000',
          'fields': 'nextPageToken,incompleteSearch,files($_fileFields)',
          'pageToken': ?pageToken,
        }),
      );
      if (page['files'] is! List ||
          (page.containsKey('incompleteSearch') &&
              page['incompleteSearch'] != false)) {
        throw const DriveMetadataFailure(DriveMetadataIssue.incompleteResponse);
      }
      for (final value in page['files'] as List) {
        final file = _file(value);
        if (file.trashed) {
          throw const DriveMetadataFailure(
            DriveMetadataIssue.incompleteResponse,
          );
        }
        files.add(file);
      }
      final next = page['nextPageToken'];
      if (page.containsKey('nextPageToken') &&
          (next is! String || next.trim().isEmpty || !seenTokens.add(next))) {
        throw const DriveMetadataFailure(DriveMetadataIssue.incompleteResponse);
      }
      pageToken = next as String?;
    } while (pageToken != null);
    return List.unmodifiable(files);
  }

  @override
  Future<DriveFileMetadata> getFile({
    required String accountId,
    required String fileId,
  }) async {
    _nonEmpty(fileId);
    final file = _file(
      await _request(
        accountId: accountId,
        method: 'GET',
        uri: Uri(
          scheme: 'https',
          host: 'www.googleapis.com',
          pathSegments: ['drive', 'v3', 'files', fileId],
          queryParameters: {'fields': _fileFields},
        ),
      ),
    );
    if (file.id != fileId) {
      throw const DriveMetadataFailure(DriveMetadataIssue.incompleteResponse);
    }
    if (file.trashed) {
      throw const DriveMetadataFailure(DriveMetadataIssue.notFound);
    }
    return file;
  }

  @override
  Future<DriveFileMetadata> createAutofinanceFolder({
    required String accountId,
  }) async {
    final file = _file(
      await _request(
        accountId: accountId,
        method: 'POST',
        uri: Uri.https('www.googleapis.com', '/drive/v3/files', {
          'fields': _folderFields,
        }),
        body: {
          'name': 'Autofinance',
          'mimeType': driveFolderMimeType,
          'parents': ['root'],
          'appProperties': driveAutofinanceFolderProperties,
        },
      ),
    );
    // Drive devuelve el ID real de la raíz, no necesariamente el alias root.
    if (file.name != 'Autofinance' ||
        file.mimeType != driveFolderMimeType ||
        file.trashed ||
        file.parents.length != 1 ||
        !driveAutofinanceFolderProperties.entries.every(
          (entry) => file.appProperties[entry.key] == entry.value,
        )) {
      throw const DriveMetadataFailure(DriveMetadataIssue.incompleteResponse);
    }
    return file;
  }
}
