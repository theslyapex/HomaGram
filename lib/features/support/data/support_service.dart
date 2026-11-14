import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class SupportConversationPreview {
  const SupportConversationPreview({
    required this.id,
    required this.userId,
    required this.status,
    required this.title,
    required this.subtitle,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String status;
  final String title;
  final String subtitle;
  final DateTime updatedAt;
}

class SupportService {
  SupportService._();

  static SupabaseClient get _client => Supabase.instance.client;
  static String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Authentication required');
    return id;
  }

  // This check controls presentation only. Database RLS is the authority.
  static bool get isSupportAdmin =>
      _client.auth.currentUser?.email?.toLowerCase() == 'theslyapex@gmail.com';

  static Future<String> getOrCreateConversation() async {
    final result = await _client.rpc('get_or_create_support_conversation');
    return result as String;
  }

  static Future<List<SupportConversationPreview>> loadAdminInbox() async {
    if (!isSupportAdmin) throw StateError('Support administrator access required');

    final rows = await _client
        .from('support_conversations')
        .select('id,user_id,status,last_message_at,updated_at')
        .order('last_message_at', ascending: false, nullsFirst: false)
        .limit(300);

    if (rows.isEmpty) return [];

    final conversations = rows.map((row) => Map<String, dynamic>.from(row)).toList();
    final userIds = conversations.map((row) => row['user_id'] as String).toSet().toList();
    final profiles = await _client
        .from('profiles')
        .select('id,username,display_name')
        .inFilter('id', userIds);
    final profileById = {
      for (final row in profiles) row['id'] as String: Map<String, dynamic>.from(row),
    };

    final conversationIds = conversations.map((row) => row['id'] as String).toList();
    final latestRows = await _client
        .from('support_messages')
        .select('conversation_id,body,message_type,created_at')
        .inFilter('conversation_id', conversationIds)
        .order('created_at', ascending: false)
        .limit(conversationIds.length * 3);
    final latestByConversation = <String, Map<String, dynamic>>{};
    for (final row in latestRows) {
      latestByConversation.putIfAbsent(
        row['conversation_id'] as String,
        () => Map<String, dynamic>.from(row),
      );
    }

    return conversations.map((row) {
      final userId = row['user_id'] as String;
      final profile = profileById[userId];
      final displayName = (profile?['display_name'] as String?)?.trim();
      final username = (profile?['username'] as String?)?.trim();
      final title = displayName?.isNotEmpty == true
          ? displayName!
          : username?.isNotEmpty == true
              ? '@$username'
              : 'کاربر هماگرام';
      final latest = latestByConversation[row['id'] as String];
      var subtitle = 'هنوز پیامی ارسال نشده';
      if (latest != null) {
        final type = latest['message_type'];
        subtitle = type == 'image'
            ? 'تصویر'
            : type == 'file'
                ? 'فایل'
                : (latest['body'] as String? ?? '');
      }
      final dateValue = row['last_message_at'] ?? row['updated_at'];
      return SupportConversationPreview(
        id: row['id'] as String,
        userId: userId,
        status: row['status'] as String? ?? 'open',
        title: title,
        subtitle: subtitle,
        updatedAt: DateTime.tryParse(dateValue as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    }).toList();
  }

  static Future<List<Map<String, dynamic>>> loadMessages(String conversationId) async {
    final rows = await _client
        .from('support_messages')
        .select('id,conversation_id,sender_id,message_type,body,storage_path,file_name,mime_type,size_bytes,created_at')
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .limit(300);

    final messages = rows.map((row) => Map<String, dynamic>.from(row)).toList();
    for (final message in messages) {
      final path = message['storage_path'] as String?;
      if (path != null && path.isNotEmpty) {
        try {
          message['signed_url'] = await _client.storage
              .from('support-media')
              .createSignedUrl(path, 3600);
        } catch (_) {
          message['signed_url'] = null;
        }
      }
    }
    return messages;
  }

  static Future<void> sendText(String conversationId, String body) async {
    final text = body.trim();
    if (text.isEmpty) return;
    if (text.length > 10000) throw ArgumentError('Message is too long');
    await _client.from('support_messages').insert({
      'conversation_id': conversationId,
      'sender_id': _userId,
      'message_type': 'text',
      'body': text,
    });
  }

  static Future<void> sendAttachment({
    required String conversationId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    if (bytes.isEmpty || bytes.length > 52428800) {
      throw ArgumentError('File size must be between 1 byte and 50 MB');
    }
    final isImage = mimeType.startsWith('image/');
    if (!isImage && !_allowedDocumentMimeTypes.contains(mimeType)) {
      throw ArgumentError('Unsupported file type');
    }

    final fileId = _uuidV4();
    final safeName = fileName.trim().replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path = '$conversationId/$_userId/$fileId';
    await _client.storage.from('support-media').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: mimeType, upsert: false),
    );

    try {
      await _client.from('support_messages').insert({
        'conversation_id': conversationId,
        'sender_id': _userId,
        'message_type': isImage ? 'image' : 'file',
        'body': '',
        'storage_path': path,
        'file_name': safeName.isEmpty ? 'attachment' : safeName,
        'mime_type': mimeType,
        'size_bytes': bytes.length,
      });
    } catch (_) {
      try {
        await _client.storage.from('support-media').remove([path]);
      } catch (_) {}
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> loadConversationInfo(String conversationId) async {
    final row = await _client
        .from('support_conversations')
        .select('id,user_id,status')
        .eq('id', conversationId)
        .single();
    return Map<String, dynamic>.from(row);
  }

  static Future<void> updateStatus(String conversationId, String status) async {
    if (!isSupportAdmin) throw StateError('Support administrator access required');
    if (status != 'open' && status != 'closed') {
      throw ArgumentError('Invalid support status');
    }
    await _client.from('support_conversations').update({
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', conversationId);
  }

  static RealtimeChannel watchMessages(String conversationId, void Function() onChange) {
    return _client
        .channel('support-messages-$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'support_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  static RealtimeChannel watchAdminInbox(void Function() onChange) {
    if (!isSupportAdmin) throw StateError('Support administrator access required');
    return _client
        .channel('support-admin-inbox-$_userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'support_conversations',
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'support_messages',
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  static Future<void> removeChannel(RealtimeChannel channel) async {
    await _client.removeChannel(channel);
  }

  static String _uuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static const Set<String> _allowedDocumentMimeTypes = {
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-powerpoint',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'text/plain',
    'text/csv',
    'application/zip',
  };
}
