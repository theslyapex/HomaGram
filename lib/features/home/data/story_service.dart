import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/data/auth_service.dart';
import '../../messaging/data/messaging_service.dart';

bool isSupportedStoryMedia({
  required String mediaType,
  required String mimeType,
}) {
  if (mediaType == 'image') {
    return const {'image/jpeg', 'image/png', 'image/webp'}.contains(mimeType);
  }
  if (mediaType == 'video') {
    return const {'video/mp4', 'video/quicktime'}.contains(mimeType);
  }
  return false;
}

class StoryService {
  StoryService._();

  static SupabaseClient get _client => AuthService.client;
  static String get _uid => _client.auth.currentUser!.id;

  static Future<List<Map<String, dynamic>>> loadActiveStories() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await _client.from('stories')
        .select('id,author_id,media_path,media_type,caption,text_content,background_key,overlay_text,overlay_x,overlay_y,overlay_scale,overlay_color,overlay_font,drawing_data,sticker_data,created_at,expires_at')
        .gt('expires_at', now)
        .order('created_at');
    return _hydrate(rows);
  }

  // Active stories owned by the signed-in user, for immediate highlight selection.
  static Future<List<Map<String, dynamic>>> loadMyActiveStories() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await _client.from('stories')
        .select('id,author_id,media_path,media_type,caption,text_content,background_key,overlay_text,overlay_x,overlay_y,overlay_scale,overlay_color,overlay_font,drawing_data,sticker_data,created_at,expires_at')
        .eq('author_id', _uid)
        .gt('expires_at', now)
        .order('created_at', ascending: false);
    return _hydrate(rows);
  }

  static const int archivePageSize = 30;

  static Future<List<Map<String, dynamic>>> loadArchivePage({
    required int offset,
    int limit = archivePageSize,
  }) async {
    if (offset < 0 || limit < 1 || limit > 100) {
      throw ArgumentError('بازه صفحه‌بندی آرشیو معتبر نیست.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await _client.from('stories')
        .select('id,author_id,media_path,media_type,caption,text_content,background_key,overlay_text,overlay_x,overlay_y,overlay_scale,overlay_color,overlay_font,drawing_data,sticker_data,created_at,expires_at')
        .eq('author_id', _uid)
        .lte('expires_at', now)
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + limit - 1);
    return _hydrate(rows);
  }

  static Future<List<Map<String, dynamic>>> loadArchive() =>
      loadArchivePage(offset: 0, limit: archivePageSize);

  // Sign storage paths in small concurrent batches. This avoids the old
  // one-request-at-a-time loop while preventing a large burst of requests.
  static Future<Map<String, String>> _signPaths(
    String bucket,
    Iterable<String> rawPaths,
  ) async {
    final paths = rawPaths.where((path) => path.isNotEmpty).toSet().toList();
    final signed = <String, String>{};
    const batchSize = 8;

    for (var start = 0; start < paths.length; start += batchSize) {
      final batch = paths.skip(start).take(batchSize);
      final results = await Future.wait(batch.map((path) async {
        try {
          final url = await _client.storage.from(bucket).createSignedUrl(path, 3600);
          return MapEntry(path, url);
        } catch (_) {
          return null;
        }
      }));
      for (final entry in results) {
        if (entry != null) signed[entry.key] = entry.value;
      }
    }
    return signed;
  }

  static Future<List<Map<String, dynamic>>> _hydrate(List<dynamic> rows) async {
    if (rows.isEmpty) return [];

    final ids = rows.map((r) => r['author_id'] as String).toSet().toList();
    final storyIds = rows.map((r) => r['id'] as String).toList();

    // Fetch profiles and viewed-state data together instead of serially.
    final profileAndViews = await Future.wait([
      _client.from('profiles')
          .select('id,username,display_name,avatar_path').inFilter('id', ids),
      _client.from('story_views')
          .select('story_id').eq('viewer_id', _uid).inFilter('story_id', storyIds),
    ]);
    final profiles = profileAndViews[0] as List;
    final seenRows = profileAndViews[1] as List;
    final byId = {
      for (final p in profiles)
        p['id'] as String: Map<String, dynamic>.from(p)
    };
    final seen = seenRows.map((r) => r['story_id'] as String).toSet();

    final avatarPaths = byId.values
        .map((profile) => profile['avatar_path'] as String?)
        .whereType<String>();
    final mediaPaths = rows
        .map((row) => row['media_path'] as String?)
        .whereType<String>();
    final stickerPaths = <String>[];
    for (final row in rows) {
      final data = row['sticker_data'];
      if (data is List) {
        for (final item in data) {
          if (item is Map && item['type'] == 'image' && item['path'] is String) {
            stickerPaths.add(item['path'] as String);
          }
        }
      }
    }

    // Sign each unique path once, with bounded concurrency.
    final signedResults = await Future.wait([
      _signPaths('avatars', avatarPaths),
      _signPaths('story-media', mediaPaths),
      _signPaths('story-stickers', stickerPaths),
    ]);
    final avatarUrls = signedResults[0];
    final mediaUrls = signedResults[1];
    final stickerUrls = signedResults[2];

    return rows.map((row) {
      final story = Map<String, dynamic>.from(row);
      final profile = byId[story['author_id']] ?? <String, dynamic>{};
      story['display_name'] = profile['display_name'] ?? 'کاربر HomaGram';
      story['username'] = profile['username'] ?? 'user';
      story['avatar_path'] = profile['avatar_path'];
      story['avatar_url'] = avatarUrls[profile['avatar_path']];
      story['media_url'] = mediaUrls[story['media_path']];
      final stickerData = story['sticker_data'];
      if (stickerData is List) {
        story['sticker_data'] = stickerData.map((raw) {
          if (raw is! Map) return raw;
          final item = Map<String, dynamic>.from(raw);
          final path = item['path'] as String?;
          if (path != null) item['signed_url'] = stickerUrls[path];
          return item;
        }).toList();
      }
      story['is_viewed'] = seen.contains(story['id']);
      return story;
    }).toList();
  }

  static Future<void> publish({
    required File file,
    required String mediaType,
    required String fileName,
    required String mimeType,
    required String caption,
    String? overlayText,
    double overlayX = 0.5,
    double overlayY = 0.5,
    double overlayScale = 1.0,
    String overlayColor = '#FFFFFF',
    String overlayFont = 'estedad',
    List<Map<String, dynamic>> drawingData = const [],
    List<Map<String, dynamic>> stickerData = const [],
  }) async {
    final cleanOverlay = overlayText?.trim();
    if (cleanOverlay != null && cleanOverlay.length > 180) {
      throw ArgumentError('متن روی رسانه حداکثر ۱۸۰ نویسه است.');
    }
    if (overlayX < 0 || overlayX > 1 || overlayY < 0 || overlayY > 1 ||
        overlayScale < 0.6 || overlayScale > 2.5 ||
        !const {'#FFFFFF', '#111827', '#FFE082', '#FF6B6B', '#45D6C5', '#A78BFA', '#F9A8D4'}.contains(overlayColor) ||
        !const {'estedad', 'serif', 'mono'}.contains(overlayFont)) {
      throw ArgumentError('تنظیمات متن روی رسانه معتبر نیست.');
    }
    if (drawingData.length > 100) throw ArgumentError('تعداد خطوط نقاشی بیش از حد مجاز است.');
    const allowedStickers = {'❤️','😍','😂','🔥','✨','⭐','🌈','🌸','🦋','🎉','☀️','🌙','💯','👏','🎈','🍀','☕','🎧'};
    if (stickerData.length > 20) throw ArgumentError('تعداد استیکرها بیش از حد مجاز است.');
    for (final sticker in stickerData) {
      final x = (sticker['x'] as num?)?.toDouble();
      final y = (sticker['y'] as num?)?.toDouble();
      final scale = (sticker['scale'] as num?)?.toDouble();
      final rotation = (sticker['rotation'] as num?)?.toDouble();
      if (!allowedStickers.contains(sticker['emoji']) ||
          x == null || y == null || x < .05 || x > .95 || y < .05 || y > .95 ||
          scale == null || scale < .5 || scale > 3 ||
          rotation == null || rotation < -3.14 || rotation > 3.14) {
        throw ArgumentError('اطلاعات استیکر معتبر نیست.');
      }
    }
    if (!isSupportedStoryMedia(mediaType: mediaType, mimeType: mimeType)) {
      throw ArgumentError('نوع رسانه یا فرمت فایل استوری پشتیبانی نمی‌شود.');
    }
    if (caption.trim().length > 500) {
      throw ArgumentError('متن استوری حداکثر ۵۰۰ نویسه است.');
    }

    final uploadedStickerPaths = <String>[];
    final persistedStickers = <Map<String, dynamic>>[];
    try {
      for (final raw in stickerData) {
        final sticker = Map<String, dynamic>.from(raw);
        if (sticker['type'] == 'image') {
          final localPath = sticker.remove('local_path') as String?;
          final mime = sticker['mime_type'] as String?;
          final name = sticker['file_name'] as String? ?? 'sticker';
          if (localPath == null || mime == null ||
              !const {'image/gif','image/jpeg','image/png','image/webp'}.contains(mime)) {
            throw ArgumentError('فایل استیکر معتبر نیست.');
          }
          final stickerBytes = await File(localPath).readAsBytes();
          if (stickerBytes.isEmpty || stickerBytes.length > 5 * 1024 * 1024) {
            throw ArgumentError('حجم استیکر باید حداکثر ۵ مگابایت باشد.');
          }
          final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'png';
          if (!const {'gif','jpg','jpeg','png','webp'}.contains(ext)) {
            throw ArgumentError('پسوند فایل استیکر پشتیبانی نمی‌شود.');
          }
          final stickerPath = '$_uid/${DateTime.now().microsecondsSinceEpoch}_${uploadedStickerPaths.length}.$ext';
          await _client.storage.from('story-stickers').uploadBinary(
            stickerPath, stickerBytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
          uploadedStickerPaths.add(stickerPath);
          sticker
            ..remove('mime_type')
            ..remove('file_name')
            ..['path'] = stickerPath;
        } else if (sticker['type'] == 'emoji') {
          if (!allowedStickers.contains(sticker['emoji'])) {
            throw ArgumentError('ایموجی استیکر معتبر نیست.');
          }
        } else {
          throw ArgumentError('نوع استیکر پشتیبانی نمی‌شود.');
        }
        final x = (sticker['x'] as num?)?.toDouble();
        final y = (sticker['y'] as num?)?.toDouble();
        final scale = (sticker['scale'] as num?)?.toDouble();
        final rotation = (sticker['rotation'] as num?)?.toDouble();
        if (x == null || y == null || x < .05 || x > .95 || y < .05 || y > .95 ||
            scale == null || scale < .5 || scale > 3 ||
            rotation == null || rotation < -3.14 || rotation > 3.14) {
          throw ArgumentError('موقعیت استیکر معتبر نیست.');
        }
        persistedStickers.add(sticker);
      }
    } catch (_) {
      if (uploadedStickerPaths.isNotEmpty) {
        try { await _client.storage.from('story-stickers').remove(uploadedStickerPaths); } catch (_) {}
      }
      rethrow;
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > 52428800) {
      throw ArgumentError('حجم رسانه باید بیشتر از صفر و حداکثر ۵۰ مگابایت باشد.');
    }
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase()
        : (mediaType == 'video' ? 'mp4' : 'jpg');
    final path = '$_uid/${DateTime.now().microsecondsSinceEpoch}.$ext';
    await _client.storage.from('story-media').uploadBinary(
      path, bytes, fileOptions: FileOptions(contentType: mimeType, upsert: false),
    );
    try {
      await _client.from('stories').insert({
        'author_id': _uid,
        'media_path': path,
        'media_type': mediaType,
        'caption': caption.trim(),
        'overlay_text': cleanOverlay == null || cleanOverlay.isEmpty ? null : cleanOverlay,
        'overlay_x': overlayX,
        'overlay_y': overlayY,
        'overlay_scale': overlayScale,
        'overlay_color': overlayColor,
        'overlay_font': overlayFont,
        'drawing_data': drawingData,
        'sticker_data': persistedStickers,
      });
    } catch (_) {
      try { await _client.storage.from('story-media').remove([path]); } catch (_) {}
      if (uploadedStickerPaths.isNotEmpty) {
        try { await _client.storage.from('story-stickers').remove(uploadedStickerPaths); } catch (_) {}
      }
      rethrow;
    }
  }

  static const Set<String> textBackgroundKeys = {
    'aurora', 'sunset', 'ocean', 'forest', 'midnight', 'rose',
  };

  static Future<void> publishText({
    required String textContent,
    required String backgroundKey,
  }) async {
    final content = textContent.trim();
    if (content.isEmpty || content.length > 1000) {
      throw ArgumentError('متن استوری باید بین ۱ تا ۱۰۰۰ نویسه باشد.');
    }
    if (!textBackgroundKeys.contains(backgroundKey)) {
      throw ArgumentError('پس‌زمینه انتخاب‌شده معتبر نیست.');
    }
    await _client.from('stories').insert({
      'author_id': _uid,
      'media_path': null,
      'media_type': 'text',
      'text_content': content,
      'background_key': backgroundKey,
      'caption': '',
    });
  }

  static Future<void> recordView(String storyId) async {
    await _client.from('story_views').upsert({
      'story_id': storyId, 'viewer_id': _uid,
    }, onConflict: 'story_id,viewer_id', ignoreDuplicates: true);
  }

  static Future<void> react(String storyId, String emoji) async {
    await _client.from('story_reactions').upsert({
      'story_id': storyId, 'user_id': _uid, 'emoji': emoji,
    }, onConflict: 'story_id,user_id');
  }

  static Future<List<Map<String, dynamic>>> loadViewers(String storyId) async {
    final rows = await _client.from('story_views')
        .select('viewer_id,viewed_at').eq('story_id', storyId)
        .order('viewed_at', ascending: false);
    if (rows.isEmpty) return [];
    final ids = rows.map((r) => r['viewer_id'] as String).toList();
    final profiles = await _client.from('profiles')
        .select('id,username,display_name,avatar_path').inFilter('id', ids);
    final byId = {for (final p in profiles) p['id'] as String: p};
    final reactions = await _client.from('story_reactions')
        .select('user_id,emoji').eq('story_id', storyId);
    final reactionByUser = {for (final r in reactions) r['user_id'] as String: r['emoji'] as String};
    return rows.map((r) {
      final p = byId[r['viewer_id']] ?? <String,dynamic>{};
      return <String,dynamic>{
        'username': p['username'] ?? 'user',
        'display_name': p['display_name'] ?? 'کاربر',
        'viewed_at': r['viewed_at'],
        'reaction': reactionByUser[r['viewer_id']],
      };
    }).toList();
  }

  static Future<void> deleteStory(Map<String, dynamic> story) async {
    await _client.from('stories').delete().eq('id', story['id'] as String);
    final mediaPath = story['media_path'] as String?;
    if (mediaPath != null && mediaPath.isNotEmpty) {
      try {
        await _client.storage.from('story-media').remove([mediaPath]);
      } catch (_) {}
    }
  }

  static Future<void> replyToStory(String authorId, String text) async {
    final conversationId = await MessagingService.createDirectConversation(authorId);
    await MessagingService.sendTextMessage(conversationId, text);
  }
}
