import 'dart:convert';
import 'dart:io';

class SupabaseResumableUpload {
  SupabaseResumableUpload._();
  static const int _chunkSize = 6 * 1024 * 1024;
  static const List<Duration> _retryDelays = [
    Duration.zero, Duration(seconds: 3), Duration(seconds: 5),
    Duration(seconds: 10), Duration(seconds: 20),
  ];

  static Future<void> upload({
    required File file,
    required String bucket,
    required String objectPath,
    required String contentType,
    required String projectUrl,
    required String publishableKey,
    required String accessToken,
    required void Function(double progress) onProgress,
  }) async {
    final length = await file.length();
    final projectRef = Uri.parse(projectUrl).host.split('.').first;
    if (projectRef.isEmpty || length <= 0) {
      throw StateError('Invalid Supabase project URL or empty upload file.');
    }
    final endpoint = Uri.https('$projectRef.storage.supabase.co', '/storage/v1/upload/resumable');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final metadata = <String, String>{
        'bucketName': bucket, 'objectName': objectPath,
        'contentType': contentType, 'cacheControl': '3600',
      }.entries.map((entry) =>
        entry.key + ' ' + base64.encode(utf8.encode(entry.value))
      ).join(',');

      final create = await client.postUrl(endpoint);
      _setHeaders(create, publishableKey, accessToken);
      create.headers
        ..set('Tus-Resumable', '1.0.0')
        ..set('Upload-Length', '$length')
        ..set('Upload-Metadata', metadata)
        ..set(HttpHeaders.contentLengthHeader, '0');
      final created = await create.close().timeout(const Duration(minutes: 1));
      final createBody = await utf8.decoder.bind(created).join();
      if (created.statusCode != HttpStatus.created) {
        throw HttpException('TUS session creation failed (' + created.statusCode.toString() + '): ' + createBody, uri: endpoint);
      }
      final location = created.headers.value(HttpHeaders.locationHeader);
      if (location == null || location.isEmpty) {
        throw const HttpException('TUS server did not return an upload location.');
      }
      final uploadUri = endpoint.resolve(location);
      final raf = await file.open();
      try {
        var offset = 0;
        onProgress(0);
        while (offset < length) {
          final start = offset;
          final end = (start + _chunkSize).clamp(0, length);
          await raf.setPosition(start);
          final chunk = await raf.read(end - start);
          if (chunk.isEmpty) throw const FileSystemException('Could not read the next upload chunk.');
          var sent = false;
          Object? lastError;
          for (var attempt = 0; attempt < _retryDelays.length && !sent; attempt++) {
            final delay = _retryDelays[attempt];
            if (delay > Duration.zero) await Future<void>.delayed(delay);
            try {
              final patch = await client.patchUrl(uploadUri);
              _setHeaders(patch, publishableKey, accessToken);
              patch.headers
                ..set('Tus-Resumable', '1.0.0')
                ..set('Upload-Offset', '$start')
                ..set('Content-Type', 'application/offset+octet-stream')
                ..set(HttpHeaders.contentLengthHeader, chunk.length.toString());
              patch.add(chunk);
              final response = await patch.close().timeout(const Duration(minutes: 2));
              final body = await utf8.decoder.bind(response).join();
              if (response.statusCode == HttpStatus.noContent) {
                offset = int.tryParse(response.headers.value('Upload-Offset') ?? '') ?? end;
                sent = true;
              } else {
                throw HttpException('TUS chunk failed (' + response.statusCode.toString() + '): ' + body, uri: uploadUri);
              }
            } catch (error) {
              lastError = error;
              try {
                final serverOffset = await _readOffset(client, uploadUri, publishableKey, accessToken);
                if (serverOffset > start && serverOffset <= length) {
                  offset = serverOffset;
                  sent = true;
                }
              } catch (headError) {
                lastError = headError;
              }
            }
          }
          if (!sent) throw HttpException('Resumable upload stopped after retries: ' + lastError.toString());
          if (offset < 0 || offset > length) throw HttpException('Invalid TUS upload offset: ' + offset.toString());
          onProgress(offset / length);
        }
      } finally {
        await raf.close();
      }
    } finally {
      client.close(force: true);
    }
  }

  static void _setHeaders(HttpClientRequest request, String key, String token) {
    request.headers
      ..set('apikey', key)
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
  }

  static Future<int> _readOffset(HttpClient client, Uri uri, String key, String token) async {
    final request = await client.headUrl(uri);
    _setHeaders(request, key, token);
    request.headers.set('Tus-Resumable', '1.0.0');
    final response = await request.close().timeout(const Duration(seconds: 45));
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('TUS offset check failed (' + response.statusCode.toString() + '): ' + body, uri: uri);
    }
    final offset = int.tryParse(response.headers.value('Upload-Offset') ?? '');
    if (offset == null) throw const HttpException('TUS server returned no upload offset.');
    return offset;
  }
}
