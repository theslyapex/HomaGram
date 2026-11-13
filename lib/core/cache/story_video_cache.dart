import 'dart:convert';
import 'dart:io';

/// Short-lived, account-scoped cache for private story videos.
/// Files stay in the app temporary directory and expire after 15 minutes.
class StoryVideoCache {
  StoryVideoCache._();

  static const Duration _maxAge = Duration(minutes: 15);
  static const int _maxFileBytes = 50 * 1024 * 1024;
  static const int _maxCacheBytes = 100 * 1024 * 1024;
  static final Map<String, Future<File>> _pending = {};

  static Future<File> getOrDownload({
    required String url,
    required String storagePath,
    required String userId,
  }) {
    final key = '$userId::$storagePath';
    return _pending.putIfAbsent(key, () async {
      try {
        return await _getOrDownload(url: url, storagePath: storagePath, userId: userId);
      } finally {
        _pending.remove(key);
      }
    });
  }

  static Future<File> _getOrDownload({
    required String url,
    required String storagePath,
    required String userId,
  }) async {
    final root = Directory('${Directory.systemTemp.path}/homagram_story_video_cache');
    final accountDir = Directory('${root.path}/${_encode(userId)}');
    await accountDir.create(recursive: true);

    final extension = storagePath.toLowerCase().endsWith('.mov') ? 'mov' : 'mp4';
    final target = File('${accountDir.path}/${_encode(storagePath)}.$extension');
    if (await target.exists()) {
      final stat = await target.stat();
      if (DateTime.now().difference(stat.modified) <= _maxAge && stat.size > 0) {
        await target.setLastModified(DateTime.now());
        await _trim(accountDir, keep: target);
        return target;
      }
      await target.delete();
    }

    final partial = File('${target.path}.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 20));
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Story video download failed: HTTP ${response.statusCode}');
      }
      if (response.contentLength > _maxFileBytes) {
        throw const HttpException('Story video exceeds the cache size limit');
      }

      sink = partial.openWrite();
      var received = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        received += chunk.length;
        if (received > _maxFileBytes) {
          throw const HttpException('Story video exceeds the cache size limit');
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (received == 0) throw const HttpException('Empty story video response');
      await partial.rename(target.path);
      await _trim(accountDir, keep: target);
      return target;
    } catch (_) {
      if (sink != null) await sink.close();
      if (await partial.exists()) await partial.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _trim(Directory directory, {required File keep}) async {
    final entries = <({File file, FileStat stat})>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && !entity.path.endsWith('.part')) {
        try { entries.add((file: entity, stat: await entity.stat())); } catch (_) {}
      }
    }
    final now = DateTime.now();
    for (final entry in entries.toList()) {
      if (now.difference(entry.stat.modified) > _maxAge && entry.file.path != keep.path) {
        try { await entry.file.delete(); entries.remove(entry); } catch (_) {}
      }
    }
    entries.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    var total = entries.fold<int>(0, (sum, entry) => sum + entry.stat.size);
    for (final entry in entries) {
      if (total <= _maxCacheBytes) break;
      if (entry.file.path == keep.path) continue;
      try { await entry.file.delete(); total -= entry.stat.size; } catch (_) {}
    }
  }

  static Future<void> evict({required String userId, required String storagePath}) async {
    final extension = storagePath.toLowerCase().endsWith('.mov') ? 'mov' : 'mp4';
    final file = File('${Directory.systemTemp.path}/homagram_story_video_cache/${_encode(userId)}/${_encode(storagePath)}.$extension');
    if (await file.exists()) await file.delete();
  }

  static Future<void> clearAccount(String userId) async {
    final directory = Directory('${Directory.systemTemp.path}/homagram_story_video_cache/${_encode(userId)}');
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  static String _encode(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');
}
