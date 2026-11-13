import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/data/auth_service.dart';

class NotificationService {
  NotificationService._();

  static SupabaseClient get _client => AuthService.client;

  static Future<List<Map<String, dynamic>>> load({int limit = 100}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];
    final rows = await _client.from('notifications')
        .select('id,actor_id,type,entity_id,entity_type,message,is_read,created_at')
        .eq('recipient_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    final items = List<Map<String, dynamic>>.from(rows);
    final ids = items.map((e) => e['actor_id'] as String?)
        .whereType<String>().toSet().toList();
    if (ids.isEmpty) return items;
    final profiles = await _client.from('profiles')
        .select('id,username,display_name,avatar_path').inFilter('id', ids);
    final byId = {for (final p in profiles) p['id'] as String: Map<String, dynamic>.from(p)};
    for (final item in items) {
      final actorId = item['actor_id'] as String?;
      item['actor'] = actorId == null ? null : byId[actorId];
    }
    return items;
  }

  static Future<void> markRead(String id) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client.from('notifications').update({'is_read': true})
        .eq('id', id).eq('recipient_id', userId);
  }

  static Future<void> markAllRead() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client.from('notifications').update({'is_read': true})
        .eq('recipient_id', userId).eq('is_read', false);
  }
}