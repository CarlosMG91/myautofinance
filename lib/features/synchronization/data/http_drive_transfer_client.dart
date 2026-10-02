import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../domain/drive_metadata.dart';
import '../domain/drive_transfer.dart';
import 'drive_metadata_credential.dart';
import 'http_drive_metadata_client.dart';

/// Sin reintentos, renovación OAuth, registro de datos ni trabajo al construir.
final class HttpDriveTransferClient implements DriveTransferClient {
  HttpDriveTransferClient({
    required http.Client client,
    required DriveMetadataCredentialSource credentials,
    DateTime Function()? now,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _client = client,
       _metadata = HttpDriveMetadataClient(
         client: client,
         credentials: credentials,
         now: now,
         requestTimeout: requestTimeout,
       );

  static const chunkBytes = 256 * 1024;
  final http.Client _client;
  final HttpDriveMetadataClient _metadata;
  final Duration requestTimeout;

  void _check(DriveTransferCancellation cancellation) {
    if (cancellation.isCancelled) {
      throw const DriveTransferFailure(DriveTransferIssue.cancelled);
    }
  }

  /// Timer aborta también la conexión; Future.timeout por sí solo no lo hace.
  Future<T> _exchange<T>({
    required String accountId,
    required String method,
    required Uri uri,
    required DriveTransferCancellation cancellation,
    required Future<T> Function(http.StreamedResponse) consume,
    Map<String, String> headers = const {},
    List<int> body = const [],
    bool commits = false,
    void Function()? onSending,
  }) async {
    _check(cancellation);
    String token;
    try {
      token = await Future.any([
        _metadata.readTransferToken(accountId),
        cancellation.whenCancelled.then<String>((_) {
          throw const DriveTransferFailure(DriveTransferIssue.cancelled);
        }),
      ]);
    } on DriveMetadataFailure catch (e) {
      throw DriveTransferFailure(
        DriveTransferIssue.remoteFailure,
        remoteFailure: e,
      );
    }
    _check(cancellation);
    final abort = Completer<void>();
    final request =
        http.AbortableRequest(method, uri, abortTrigger: abort.future)
          ..followRedirects = false
          ..headers.addAll({'Authorization': 'Bearer $token', ...headers})
          ..bodyBytes = body;
    final timer = Timer(requestTimeout, () {
      if (!abort.isCompleted) abort.complete();
    });
    var sent = false;
    try {
      onSending?.call();
      _check(cancellation);
      sent = true;
      return await Future.any([
        (() async => consume(await _client.send(request)))(),
        cancellation.whenCancelled.then<T>((_) {
          throw const DriveTransferFailure(DriveTransferIssue.cancelled);
        }),
      ]).timeout(requestTimeout);
    } on DriveTransferFailure catch (e) {
      if (commits && sent && e.issue != DriveTransferIssue.remoteFailure) {
        throw DriveTransferFailure(
          DriveTransferIssue.ambiguousResponse,
          remoteFailure: e.remoteFailure,
        );
      }
      rethrow;
    } on TimeoutException {
      throw DriveTransferFailure(
        commits
            ? DriveTransferIssue.ambiguousResponse
            : DriveTransferIssue.remoteFailure,
        remoteFailure: const DriveMetadataFailure(
          DriveMetadataIssue.requestTimeout,
        ),
      );
    } catch (_) {
      throw DriveTransferFailure(
        commits
            ? DriveTransferIssue.ambiguousResponse
            : cancellation.isCancelled
            ? DriveTransferIssue.cancelled
            : DriveTransferIssue.remoteFailure,
        remoteFailure: DriveMetadataFailure(
          abort.isCompleted && !cancellation.isCancelled
              ? DriveMetadataIssue.requestTimeout
              : DriveMetadataIssue.networkFailure,
        ),
      );
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
    }
  }

  Future<List<int>> _smallBody(http.StreamedResponse response) async {
    final bytes = <int>[];
    await for (final part in response.stream) {
      if (bytes.length + part.length > 64 * 1024) {
        throw const DriveTransferFailure(DriveTransferIssue.invalidResponse);
      }
      bytes.addAll(part);
    }
    return bytes;
  }

  Never _httpError(
    http.StreamedResponse response,
    List<int> body, {
    bool commits = false,
  }) {
    final failure = _metadata.classifyResponse(
      http.Response.bytes(body, response.statusCode, headers: response.headers),
    );
    throw DriveTransferFailure(
      commits && response.statusCode >= 500
          ? DriveTransferIssue.ambiguousResponse
          : DriveTransferIssue.remoteFailure,
      remoteFailure: failure,
    );
  }

  @override
  Future<DriveFileMetadata> upload({
    required String accountId,
    required String folderId,
    String? fileId,
    required String sourcePath,
    required DriveTransferCancellation cancellation,
    required Future<void> Function() beforeCommit,
    void Function(DriveTransferProgress)? onProgress,
  }) async {
    if (folderId.trim().isEmpty || (fileId != null && fileId.trim().isEmpty)) {
      throw const DriveTransferFailure(DriveTransferIssue.invalidRequest);
    }
    RandomAccessFile? source;
    try {
      _check(cancellation);
      source = await File(sourcePath).open();
      final total = await source.length();
      if (total <= 0) {
        throw const DriveTransferFailure(DriveTransferIssue.invalidRequest);
      }
      final uri = Uri(
        scheme: 'https',
        host: 'www.googleapis.com',
        pathSegments: ['upload', 'drive', 'v3', 'files', ?fileId],
        queryParameters: {
          'uploadType': 'resumable',
          'fields': 'id,name,mimeType,parents,trashed,appProperties,modifiedTime,size,md5Checksum,version',
        },
      );
      final session = await _exchange<Uri>(
        accountId: accountId,
        method: fileId == null ? 'POST' : 'PATCH',
        uri: uri,
        cancellation: cancellation,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'X-Upload-Content-Type': 'application/octet-stream',
          'X-Upload-Content-Length': '$total',
        },
        body: utf8.encode(
          jsonEncode(
            fileId == null
                ? {
                    'name': driveAutofinanceCopyName,
                    'parents': [folderId],
                    'appProperties': driveAutofinanceCopyProperties,
                  }
                : <String, dynamic>{},
          ),
        ),
        consume: (r) async {
          final body = await _smallBody(r);
          if (r.statusCode != 200 && r.statusCode != 201) _httpError(r, body);
          final location = Uri.tryParse(r.headers['location'] ?? '');
          if (location == null ||
              location.scheme != 'https' ||
              location.host != 'www.googleapis.com' ||
              location.userInfo.isNotEmpty ||
              location.port != 443 ||
              !location.path.startsWith('/upload/drive/v3/files') ||
              location.fragment.isNotEmpty) {
            throw const DriveTransferFailure(
              DriveTransferIssue.invalidResponse,
            );
          }
          return location;
        },
      );
      var offset = 0;
      onProgress?.call(
        DriveTransferProgress(0, total, DriveTransferPhase.transferring),
      );
      while (offset < total) {
        _check(cancellation);
        final length = min(chunkBytes, total - offset);
        final block = await source.read(length);
        if (block.length != length || await source.length() != total) {
          throw const DriveTransferFailure(DriveTransferIssue.localIoFailure);
        }
        final last = offset + length == total;
        if (last) {
          onProgress?.call(
            DriveTransferProgress(
              offset,
              total,
              DriveTransferPhase.beforeCommit,
            ),
          );
          await Future.any([
            beforeCommit(),
            cancellation.whenCancelled.then<void>((_) => _check(cancellation)),
          ]);
          _check(cancellation);
        }
        final result = await _exchange<DriveFileMetadata?>(
          accountId: accountId,
          method: 'PUT',
          uri: session,
          cancellation: cancellation,
          commits: last,
          onSending: last
              ? () => onProgress?.call(
                  DriveTransferProgress(
                    offset,
                    total,
                    DriveTransferPhase.committing,
                  ),
                )
              : null,
          headers: {
            'Content-Type': 'application/octet-stream',
            'Content-Range': 'bytes $offset-${offset + length - 1}/$total',
          },
          body: block,
          consume: (r) async {
            final body = await _smallBody(r);
            if (!last && r.statusCode == 308) {
              if (r.headers['range'] != 'bytes=0-${offset + length - 1}') {
                throw const DriveTransferFailure(
                  DriveTransferIssue.invalidResponse,
                );
              }
              return null;
            }
            if (last && (r.statusCode == 200 || r.statusCode == 201)) {
              try {
                final file = _metadata.parseFileMetadata(
                  jsonDecode(utf8.decode(body)),
                );
                if (file.size != total ||
                    file.version == null ||
                    file.modifiedTime == null ||
                    file.trashed ||
                    (fileId != null && file.id != fileId) ||
                    file.parents.length != 1 ||
                    file.parents.single != folderId ||
                    !driveAutofinanceCopyProperties.entries.every(
                      (e) => file.appProperties[e.key] == e.value,
                    )) {
                  throw const FormatException();
                }
                return file;
              } catch (_) {
                throw const DriveTransferFailure(
                  DriveTransferIssue.ambiguousResponse,
                );
              }
            }
            if (r.statusCode >= 200 && r.statusCode < 400) {
              throw const DriveTransferFailure(
                DriveTransferIssue.ambiguousResponse,
              );
            }
            _httpError(r, body, commits: last);
          },
        );
        offset += length;
        onProgress?.call(
          DriveTransferProgress(
            offset,
            total,
            last
                ? DriveTransferPhase.complete
                : DriveTransferPhase.transferring,
          ),
        );
        if (result != null) return result;
      }
      throw const DriveTransferFailure(DriveTransferIssue.invalidResponse);
    } on FileSystemException {
      throw const DriveTransferFailure(DriveTransferIssue.localIoFailure);
    } finally {
      try {
        await source?.close();
      } on FileSystemException {
        throw const DriveTransferFailure(DriveTransferIssue.localIoFailure);
      }
    }
  }

  @override
  Future<DriveDownloadCandidate> download({
    required String accountId,
    required String fileId,
    required int expectedBytes,
    required String temporaryDirectory,
    required DriveTransferCancellation cancellation,
    void Function(DriveTransferProgress)? onProgress,
  }) async {
    if (fileId.trim().isEmpty || expectedBytes <= 0) {
      throw const DriveTransferFailure(DriveTransferIssue.invalidRequest);
    }
    Directory? staging;
    RandomAccessFile? output;
    var keep = false;
    var receiving = true;
    try {
      _check(cancellation);
      staging = await Directory(temporaryDirectory).createTemp('drive-');
      final file = File(
        '${staging.path}${Platform.pathSeparator}candidate.part',
      );
      output = await file.open(mode: FileMode.write);
      var bytes = 0;
      await _exchange<void>(
        accountId: accountId,
        method: 'GET',
        uri: Uri(
          scheme: 'https',
          host: 'www.googleapis.com',
          pathSegments: ['drive', 'v3', 'files', fileId],
          queryParameters: {'alt': 'media'},
        ),
        cancellation: cancellation,
        consume: (r) async {
          if (!receiving) {
            throw const DriveTransferFailure(DriveTransferIssue.cancelled);
          }
          if (r.statusCode != 200) _httpError(r, await _smallBody(r));
          onProgress?.call(
            DriveTransferProgress(
              0,
              expectedBytes,
              DriveTransferPhase.transferring,
            ),
          );
          await for (final block in r.stream) {
            if (!receiving) {
              throw const DriveTransferFailure(DriveTransferIssue.cancelled);
            }
            _check(cancellation);
            if (bytes + block.length > expectedBytes) {
              throw const DriveTransferFailure(
                DriveTransferIssue.invalidResponse,
              );
            }
            try {
              await output!.writeFrom(block);
            } on FileSystemException {
              throw const DriveTransferFailure(
                DriveTransferIssue.localIoFailure,
              );
            }
            bytes += block.length;
            onProgress?.call(
              DriveTransferProgress(
                bytes,
                expectedBytes,
                DriveTransferPhase.transferring,
              ),
            );
          }
          if (bytes != expectedBytes) {
            throw const DriveTransferFailure(
              DriveTransferIssue.invalidResponse,
            );
          }
        },
      );
      _check(cancellation);
      await output.flush();
      await output.close();
      output = null;
      _check(cancellation);
      onProgress?.call(
        DriveTransferProgress(
          bytes,
          expectedBytes,
          DriveTransferPhase.complete,
        ),
      );
      keep = true;
      return DriveDownloadCandidate(path: file.path, bytes: bytes);
    } on FileSystemException {
      throw const DriveTransferFailure(DriveTransferIssue.localIoFailure);
    } finally {
      receiving = false;
      try {
        try {
          await output?.close();
        } finally {
          if (!keep && staging != null) await staging.delete(recursive: true);
        }
      } on FileSystemException {
        // Un huérfano continúa siendo .part y nunca se registra como copia.
        throw const DriveTransferFailure(DriveTransferIssue.localIoFailure);
      }
    }
  }
}
