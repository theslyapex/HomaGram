import 'dart:typed_data';

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
        .toSet()
        .toList(growable: false);

    // Fetch inbox data in batches rather than issuing two or three requests
    // for every conversation. This keeps inbox latency predictable as it grows.
    final results = await Future.wait([
      _client
          .from('conversations')
          .select('id,kind,title,updated_at')
          .inFilter('id', ids)
          .order('updated_at', ascending: false),
      _client
          .from('conversation_members')
          .select('conversation_id,user_id')
          .inFilter('conversation_id', ids)
          .isFilter('left_at', null),
      _client
          .from('messages')
          .select('conversation_id,body,message_type,deleted_at,created_at')
          .inFilter('conversation_id', ids)
          .order('created_at', ascending: false)
          .limit(1000),
    ]);

    final conversations = results[0] as List;
    final allMembers = results[1] as List;
    final recentMessages = results[2] as List;

    final otherUserIds = allMembers
        .where((row) => row['user_id'] != _userId)
        .map((row) => row['user_id'] as String)
        .toSet()
        .toList(growable: false);

    final profiles = otherUserIds.isEmpty
        ? <dynamic>[]
        : await _client
            .from('profiles')
            .select('id,display_name,username')
            .inFilter('id', otherUserIds);

    final profileById = {
      for (final profile in profiles)
        profile['id'] as String: Map<String, dynamic>.from(profile),
    };

    final otherMemberByConversation = <String, String>{};
    for (final member in allMembers) {
      final userId = member['user_id'] as String;
      if (userId != _userId) {
        otherMemberByConversation.putIfAbsent(
          member['conversation_id'] as String,
          () => userId,
        );
      }
    }

    final latestByConversation = <String, Map<String, dynamic>>{};
    for (final row in recentMessages) {
      latestByConversation.putIfAbsent(
        row['conversation_id'] as String,
        () => Map<String, dynamic>.from(row),
      );
    }

    final previews = <ConversationPreview>[];
    for (final conversation in conversations) {
      final id = conversation['id'] as String;
      final kind = conversation['kind'] as String;
      var title = (conversation['title'] as String?)?.trim();
      if (title == null || title.isEmpty) title = 'گفت‌وگوی خصوصی';

      if (kind == 'direct') {
        final otherUserId = otherMemberByConversation[id];
        final profile = otherUserId == null ? null : profileById[otherUserId];
        if (profile != null) {
          final displayName = (profile['display_name'] as String?)?.trim();
          final username = (profile['username'] as String?)?.trim();
          title = displayName != null && displayName.isNotEmpty
              ? displayName
              : username != null && username.isNotEmpty
                  ? '@$username'
                  : title;
        }
      }

      final latest = latestByConversation[id];
      var subtitle = 'هنوز پیامی ارسال نشده';
      if (latest != null) {
        if (latest['deleted_at'] != null) {
          subtitle = 'پیام حذف شده است';
        } else if (latest['message_type'] == 'image') {
          subtitle = 'تصویر';
        } else if (latest['message_type'] == 'video') {
          subtitle = 'ویدئو';
        } else if (latest['message_type'] == 'audio') {
          subtitle = 'فایل صوتی';
        } else if (latest['message_type'] == 'file') {
          subtitle = 'فایل';
        } else {
          subtitle = (latest['body'] as String?) ?? '';
        }
      }

      previews.add(ConversationPreview(
        id: id,
        kind: kind,
        title: title,
        subtitle: subtitle,
        updatedAt: DateTime.tryParse(
              conversation['updated_at'] as String? ?? '',
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ));
    }

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
    final messages = rows.map((row) => Map<String, dynamic>.from(row)).toList();
    if (messages.isEmpty) return messages;
    final ids = messages.map((m) => m['id'] as String).toList();
    final attachments = await _client.from('message_attachments')
        .select('message_id,storage_path,mime_type,file_name,size_bytes')
        .inFilter('message_id', ids);
    for (final item in attachments) {
      try {
        item['signed_url'] = await _client.storage.from('chat-media')
            .createSignedUrl(item['storage_path'] as String, 3600);
      } catch (_) {
        item['signed_url'] = null;
      }
    }
    final reactions = await _client.from('message_reactions')
        .select('message_id,user_id,emoji').inFilter('message_id', ids);
    final receipts = await _client.from('message_receipts')
        .select('message_id,user_id,read_at').inFilter('message_id', ids);
    for (final message in messages) {
      final id = message['id'];
      final ownReceipts = receipts.where((r) => r['message_id'] == id).toList();
      message['attachments'] = attachments.where((a) => a['message_id'] == id).toList();
      message['reactions'] = reactions.where((r) => r['message_id'] == id).toList();
      message['read_count'] = ownReceipts.where((r) =>
          r['user_id'] != message['sender_id'] && r['read_at'] != null).length;
      message['recipient_count'] = ownReceipts.where((r) =>
          r['user_id'] != message['sender_id']).length;
    }
    return messages;
  }
  static Future<void> sendTextMessage(
    String conversationId,
    String body, {
    String? replyToId,
  }) async {
    final text = body.trim();
    if (text.isEmpty) return;
    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': _userId,
      'message_type': 'text',
      'body': text,
      if (replyToId != null) 'reply_to_id': replyToId,
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


  static Future<void> sendMediaMessage({
    required String conversationId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    if (bytes.isEmpty || bytes.length > 52428800) {
      throw ArgumentError('حجم فایل باید کمتر از ۵۰ مگابایت باشد.');
    }
    final kind = mimeType.startsWith('image/') ? 'image'
        : mimeType.startsWith('video/') ? 'video'
        : mimeType.startsWith('audio/') ? 'audio' : 'file';
    final label = kind == 'image' ? 'تصویر' : kind == 'video' ? 'ویدئو'
        : kind == 'audio' ? 'فایل صوتی' : 'فایل';
    final inserted = await _client.from('messages').insert({
      'conversation_id': conversationId, 'sender_id': _userId,
      'message_type': kind, 'body': label,
    }).select('id').single();
    final messageId = inserted['id'] as String;
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path = '$conversationId/$_userId/$messageId/$safeName';
    try {
      await _client.storage.from('chat-media').uploadBinary(
        path, bytes, fileOptions: FileOptions(contentType: mimeType, upsert: false),
      );
      await _client.from('message_attachments').insert({
        'message_id': messageId, 'conversation_id': conversationId,
        'uploader_id': _userId, 'storage_path': path,
        'mime_type': mimeType, 'size_bytes': bytes.length, 'file_name': safeName,
      });
    } catch (_) {
      try { await _client.storage.from('chat-media').remove([path]); } catch (_) {}
      try {
        await _client.from('messages').update({
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', messageId);
      } catch (_) {}
      rethrow;
    }
  }

  static Future<void> manageGroupMember(
    String conversationId, String targetUserId, String action,
  ) async {
    await _client.rpc('manage_group_member', params: {
      'p_conversation_id': conversationId,
      'p_target_user': targetUserId,
      'p_action': action,
    });
  }

  static Future<void> manageChannelMember(
    String conversationId, String targetUserId, String action,
  ) async {
    await _client.rpc('manage_channel_member', params: {
      'p_conversation_id': conversationId,
      'p_target_user': targetUserId,
      'p_action': action,
    });
  }

  static Future<void> updateChannelDetails({
    required String conversationId,
    required String title,
    required String slug,
    required String description,
  }) async {
    await _client.rpc('update_channel_details', params: {
      'p_conversation_id': conversationId,
      'p_title': title.trim(),
      'p_slug': slug.trim().toLowerCase(),
      'p_description': description.trim(),
    });
  }

  static Future<void> updateGroupTitle(String conversationId, String title) async {
    await _client.rpc('update_group_title', params: {
      'p_conversation_id': conversationId, 'p_title': title.trim(),
    });
  }

  static Future<List<Map<String, dynamic>>> loadConversationMembers(
    String conversationId,
  ) async {
    final rows = await _client.from('conversation_members')
        .select('user_id,role,joined_at')
        .eq('conversation_id', conversationId).isFilter('left_at', null)
        .order('joined_at');
    if (rows.isEmpty) return [];
    final ids = rows.map((row) => row['user_id'] as String).toList();
    final profiles = await _client.from('profiles')
        .select('id,username,display_name,avatar_path').inFilter('id', ids);
    final byId = {for (final profile in profiles) profile['id'] as String: profile};
    return rows.map((row) {
      final profile = byId[row['user_id']] ?? <String, dynamic>{};
      return <String, dynamic>{
        ...Map<String, dynamic>.from(row),
        'username': profile['username'] ?? '',
        'display_name': profile['display_name'] ?? '',
        'avatar_path': profile['avatar_path'],
      };
    }).toList();
  }

  static Future<List<Map<String, dynamic>>> searchMessages(
    String conversationId, String query,
  ) async {
    final term = query.trim();
    if (term.length < 2) return [];
    final rows = await _client.from('messages')
        .select('id,sender_id,body,message_type,created_at,deleted_at')
        .eq('conversation_id', conversationId).isFilter('deleted_at', null)
        .ilike('body', '%$term%')
        .order('created_at', ascending: false).limit(50);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
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
          .isFilter('read_at', null)
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
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
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
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_reactions',
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_receipts',
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_attachments',
          callback: (_) => onChange(),
        )
        .subscribe();
  }


  static Future<void> updatePresence(bool online) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('user_presence').upsert({
      'user_id': _userId, 'is_online': online,
      'last_seen_at': now, 'updated_at': now,
    }, onConflict: 'user_id');
  }

  static Future<List<Map<String, dynamic>>> loadConversationPresence(String conversationId) async {
    final members = await _client.from('conversation_members')
        .select('user_id').eq('conversation_id', conversationId)
        .isFilter('left_at', null).neq('user_id', _userId);
    if (members.isEmpty) return [];
    final ids = members.map((row) => row['user_id'] as String).toList();
    final rows = await _client.from('user_presence')
        .select('user_id,is_online,last_seen_at').inFilter('user_id', ids);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  static RealtimeChannel watchPresence(void Function() onChange) {
    return _client.channel('homagram-presence-$_userId')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public',
          table: 'user_presence', callback: (_) => onChange())
        .subscribe();
  }

  static Future<void> removeChannel(RealtimeChannel channel) async {
    await _client.removeChannel(channel);
  }

  static Future<List<Map<String, dynamic>>> loadPublicChannels() async {
    final rows = await _client.from('channels')
        .select('conversation_id,slug,description,is_public,created_at,conversations(title)')
        .eq('is_public', true)
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  static Future<String> createChannel({
    required String title,
    required String slug,
    required String description,
    bool isPublic = true,
  }) async {
    final result = await _client.rpc('create_channel', params: {
      'p_title': title.trim(),
      'p_slug': slug.trim().toLowerCase(),
      'p_description': description.trim(),
      'p_is_public': isPublic,
    });
    return result as String;
  }

  static Future<void> joinPublicChannel(String conversationId) async {
    await _client.rpc('join_public_channel', params: {
      'p_conversation_id': conversationId,
    });
  }

  static Future<String> createChannelInvite(
    String conversationId, {
    int expiresInHours = 168,
    int maxUses = 100,
  }) async {
    final result = await _client.rpc('create_channel_invite', params: {
      'p_conversation_id': conversationId,
      'p_expires_in_hours': expiresInHours,
      'p_max_uses': maxUses,
    });
    return result as String;
  }

  static Future<List<Map<String, dynamic>>> loadChannelInvites(
    String conversationId,
  ) async {
    final rows = await _client.rpc('list_channel_invites', params: {
      'p_conversation_id': conversationId,
    });
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  static Future<void> revokeChannelInvite(String inviteId) async {
    await _client.rpc('revoke_channel_invite', params: {
      'p_invite_id': inviteId,
    });
  }

  static Future<String> joinChannelByInvite(String token) async {
    final result = await _client.rpc('join_channel_by_invite', params: {
      'p_token': token.trim().toLowerCase(),
    });
    return result as String;
  }

  static Future<void> updateChannelMemberPermissions({
    required String conversationId,
    required bool membersCanPost,
    required bool membersCanSendMedia,
  }) async {
    await _client.rpc('update_channel_member_permissions', params: {
      'p_conversation_id': conversationId,
      'p_members_can_post': membersCanPost,
      'p_members_can_send_media': membersCanSendMedia,
    });
  }

  static Future<void> transferChannelOwnership({
    required String conversationId,
    required String newOwnerUserId,
  }) async {
    await _client.rpc('transfer_channel_ownership', params: {
      'p_conversation_id': conversationId,
      'p_new_owner': newOwnerUserId,
    });
  }

  static Future<String> loadChannelTitle(String conversationId) async {
    final row = await _client.from('conversations')
        .select('title').eq('id', conversationId).single();
    return (row['title'] as String?)?.trim().isNotEmpty == true
        ? row['title'] as String
        : 'کانال خصوصی';
  }

}
