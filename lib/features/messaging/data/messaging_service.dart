import 'package:supabase_flutter/supabase_flutter.dart';

class ConversationPreview {
  const ConversationPreview({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.updatedAt,
  });

  final String id;
  final String kind;
  final String title;
  final String subtitle;
  final DateTime updatedAt;
}

class MessagingService {
  MessagingService._();

  static SupabaseClient get _client => Supabase.instance.client;
  static String get _userId => _client.auth.currentUser!.id;

  static Future<List<ConversationPreview>> loadInbox() async {
    final memberships = await _client
        .from('conversation_members')
        .select('conversation_id')
        .eq('user_id', _userId)
        .isFilter('left_at', null);

    if (memberships.isEmpty) return [];

    final ids = memberships
        .map((row) => row['conversation_id'] as String)
        .toList(growable: false);

    final conversations = await _client
        .from('conversations')
        .select('id,kind,title,updated_at')
        .inFilter('id', ids)
        .order('updated_at', ascending: false);

    final previews = await Future.wait(conversations.map((conversation) async {
      final id = conversation['id'] as String;
      final kind = conversation['kind'] as String;
      var title = (conversation['title'] as String?) ?? 'گفت‌وگوی خصوصی';

      if (kind == 'direct') {
        final otherMembers = await _client
            .from('conversation_members')
            .select('user_id')
            .eq('conversation_id', id)
            .isFilter('left_at', null)
            .neq('user_id', _userId)
            .limit(1);

        if (otherMembers.isNotEmpty) {
          final profile = await _client
              .from('profiles')
              .select('display_name,username')
              .eq('id', otherMembers.first['user_id'] as String)
              .maybeSingle();
          if (profile != null) {
            title = (profile['display_name'] as String?)?.trim().isNotEmpty == true
                ? profile['display_name'] as String
                : '@${profile['username']}';
          }
        }
      }

      final latest = await _client
          .from('messages')
          .select('body,message_type,deleted_at')
          .eq('conversation_id', id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      var subtitle = 'هنوز پیامی ارسال نشده';
      if (latest != null) {
        if (latest['deleted_at'] != null) {
          subtitle = 'پیام حذف شده است';
        } else if (latest['message_type'] == 'image') {
          subtitle = 'تصویر';
        } else if (latest['message_type'] == 'video') {
          subtitle = 'ویدئو';
        } else {
          subtitle = (latest['body'] as String?) ?? '';
        }
      }

      return ConversationPreview(
        id: id,
        kind: kind,
        title: title,
        subtitle: subtitle,
        updatedAt: DateTime.parse(conversation['updated_at'] as String),
      );
    }));

    previews.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return previews;
  }

  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final term = query.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');
    if (term.length < 2) return [];
    final rows = await _client
        .from('profiles')
        .select('id,username,display_name')
        .neq('id', _userId)
        .ilike('username', '%$term%')
        .limit(20);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  static Future<String> createDirectConversation(String targetUserId) async {
    final result = await _client.rpc(
      'create_direct_conversation',
      params: {'p_target_user': targetUserId},
    );
    return result as String;
  }

  static Future<void> leaveConversation(String conversationId) async {
    await _client.rpc(
      'leave_conversation',
      params: {'p_conversation_id': conversationId},
    );
  }

  static Future<List<Map<String, dynamic>>> loadMessages(
    String conversationId,
  ) async {
    final rows = await _client
        .from('messages')
        .select('id,sender_id,body,message_type,deleted_at,created_at,edited_at')
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .limit(200);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  static Future<void> sendTextMessage(
    String conversationId,
    String body,
  ) async {
    final text = body.trim();
    if (text.isEmpty) return;
    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': _userId,
      'message_type': 'text',
      'body': text,
    });
  }


  static Future<String> createGroupConversation({
    required String title,
    required List<String> memberIds,
  }) async {
    final result = await _client.rpc(
      'create_group_conversation',
      params: {'p_title': title.trim(), 'p_member_ids': memberIds},
    );
    return result as String;
  }

  static Future<void> editMessage(String messageId, String body) async {
    final text = body.trim();
    if (text.isEmpty || text.length > 10000) {
      throw ArgumentError('متن پیام باید بین ۱ تا ۱۰۰۰۰ نویسه باشد.');
    }
    await _client.from('messages').update({'body': text}).eq('id', messageId);
  }

  static Future<void> deleteMessage(String messageId) async {
    await _client.from('messages').update({
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', messageId);
  }

  static Future<void> markConversationRead(String conversationId) async {
    final rows = await _client
        .from('messages')
        .select('id')
        .eq('conversation_id', conversationId)
        .neq('sender_id', _userId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false)
        .limit(200);
    if (rows.isEmpty) return;
    final ids = rows.map((row) => row['id'] as String).toList();
    final existing = await _client
        .from('message_receipts')
        .select('message_id')
        .eq('user_id', _userId)
        .inFilter('message_id', ids);
    final existingIds = existing.map((row) => row['message_id'] as String).toSet();
    final now = DateTime.now().toUtc().toIso8601String();
    if (existingIds.isNotEmpty) {
      await _client.from('message_receipts')
          .update({'read_at': now})
          .eq('user_id', _userId)
          .inFilter('message_id', existingIds.toList());
    }
    final missing = ids.where((id) => !existingIds.contains(id)).toList();
    if (missing.isNotEmpty) {
      await _client.from('message_receipts').insert(missing.map((id) => {
        'message_id': id,
        'user_id': _userId,
        'delivered_at': now,
        'read_at': now,
      }).toList());
    }
  }

  static Future<void> toggleReaction(String messageId, String emoji) async {
    final existing = await _client
        .from('message_reactions')
        .select('message_id')
        .eq('message_id', messageId)
        .eq('user_id', _userId)
        .eq('emoji', emoji)
        .maybeSingle();
    if (existing != null) {
      await _client.from('message_reactions')
          .delete()
          .eq('message_id', messageId)
          .eq('user_id', _userId)
          .eq('emoji', emoji);
    } else {
      await _client.from('message_reactions').insert({
        'message_id': messageId,
        'user_id': _userId,
        'emoji': emoji,
      });
    }
  }

  static Future<List<Map<String, dynamic>>> loadReactions(String messageId) async {
    final rows = await _client
        .from('message_reactions')
        .select('emoji,user_id')
        .eq('message_id', messageId);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  static RealtimeChannel watchInbox(void Function() onChange) {
    return _client
        .channel('homagram-inbox-$_userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  static RealtimeChannel watchConversation(
    String conversationId,
    void Function() onChange,
  ) {
    return _client
        .channel('homagram-conversation-$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  static Future<void> removeChannel(RealtimeChannel channel) async {
    await _client.removeChannel(channel);
  }
}
