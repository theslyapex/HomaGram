import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/data/auth_service.dart';
import '../../messaging/data/messaging_service.dart';

class StoryService {
  StoryService._();

  static SupabaseClient get _client => AuthService.client;
  static String get _uid => _client.auth.currentUser!.id;

  static Future<List<Map<String, dynamic>>> loadActiveStories() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await _client.from('stories')
        .select('id,author_id,media_path,media_type,caption,created_at,expires_at')
        .gt('expires_at', now)
        .order('created_at');
    return _hydrate(rows);
  }

  static Future<List<Map<String, dynamic>>> loadArchive() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await _client.from('stories')
        .select('id,author_id,media_path,media_type,caption,created_at,expires_at')
        .eq('author_id', _uid)
        .lte('expires_at', now)
        .order('created_at', ascending: false)
        .limit(100);
    return _hydrate(rows);
  }

  static Future<List<Map<String, dynamic>>> _hydrate(List<dynamic> rows) async {
    if (rows.isEmpty) return [];
    final ids = rows.map((r) => r['author_id'] as String).toSet().toList();
    final profiles = await _client.from('profiles')
        .select('id,username,display_name,avatar_path').inFilter('id', ids);
    final byId = {for (final p in profiles) p['id'] as String: Map<String,dynamic>.from(p)};
    final storyIds = rows.map((r) => r['id'] as String).toList();
    final seenRows = await _client.from('story_views')
        .select('story_id').eq('viewer_id', _uid).inFilter('story_id', storyIds);
    final seen = seenRows.map((r) => r['story_id'] as String).toSet();
    final result = <Map<String,dynamic>>[];
    for (final row in rows) {
      final story = Map<String,dynamic>.from(row);
      final profile = byId[story['author_id']] ?? <String,dynamic>{};
      story['display_name'] = profile['display_name'] ?? 'کاربر HomaGram';
      story['username'] = profile['username'] ?? 'user';
      story['avatar_url'] = null;
      story['media_url'] = null;
      story['is_viewed'] = seen.contains(story['id']);
      final avatarPath = profile['avatar_path'] as String?;
      if (avatarPath != null) {
        try { story['avatar_url'] = await _client.storage.from('avatars').createSignedUrl(avatarPath, 3600); } catch (_) {}
      }
      try {
        story['media_url'] = await _client.storage.from('story-media')
            .createSignedUrl(story['media_path'] as String, 3600);
      } catch (_) {}
      result.add(story);
    }
    return result;
  }

  static Future<void> publish({
    required File file,
    required String mediaType,
    required String fileName,
    required String mimeType,
    required String caption,
  }) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > 52428800) {
      throw ArgumentError('حجم رسانه باید حداکثر ۵۰ مگابایت باشد.');
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
      });
    } catch (_) {
      try { await _client.storage.from('story-media').remove([path]); } catch (_) {}
      rethrow;
    }
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
    try {
      await _client.storage.from('story-media').remove([story['media_path'] as String]);
    } catch (_) {}
  }

  static Future<void> replyToStory(String authorId, String text) async {
    final conversationId = await MessagingService.createDirectConversation(authorId);
    await MessagingService.sendTextMessage(conversationId, text);
  }
}
