import 'package:supabase_flutter/supabase_flutter.dart';

class AdminDashboardStats {
  const AdminDashboardStats({
    required this.users, required this.posts, required this.stories,
    required this.reels, required this.messages, required this.groups,
    required this.channels, required this.pendingPostReports,
    required this.openSupportConversations,
  });
  final int users, posts, stories, reels, messages, groups, channels;
  final int pendingPostReports, openSupportConversations;

  factory AdminDashboardStats.fromJson(Map<String, dynamic> json) {
    int value(String key) => (json[key] as num?)?.toInt() ?? 0;
    return AdminDashboardStats(
      users: value('users'), posts: value('posts'), stories: value('stories'),
      reels: value('reels'), messages: value('messages'), groups: value('groups'),
      channels: value('channels'), pendingPostReports: value('pending_post_reports'),
      openSupportConversations: value('open_support_conversations'),
    );
  }
}

class AdminUserSummary {
  const AdminUserSummary({
    required this.id, required this.username, required this.displayName,
    required this.createdAt, required this.bannedUntil, required this.isBanned,
  });
  final String id;
  final String? username, displayName, avatarUrl;
  final DateTime? createdAt, bannedUntil;
  final bool isBanned;

  factory AdminUserSummary.fromJson(Map<String, dynamic> json) => AdminUserSummary(
    id: json['user_id'] as String,
    username: json['username'] as String?,
    displayName: json['display_name'] as String?,
    avatarUrl: json['avatar_url'] as String?,
    createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    bannedUntil: DateTime.tryParse(json['banned_until']?.toString() ?? ''),
    isBanned: json['is_banned'] as bool? ?? false,
  );
}

class AdminPostReport {
  const AdminPostReport({
    required this.id, required this.postId, required this.reporterId,
    required this.reason, required this.details, required this.status,
    required this.createdAt, required this.reviewNote, required this.postCaption,
    this.rightsOwner, this.rightsHolderName, this.postAuthorId,
    this.authorUsername, this.authorDisplayName,
  });
  final String id, postId, reporterId, reason, status;
  final String? details, reviewNote, postCaption, rightsOwner, rightsHolderName;
  final String? postAuthorId, authorUsername, authorDisplayName;
  final DateTime? createdAt;

  factory AdminPostReport.fromJson(Map<String, dynamic> json) => AdminPostReport(
    id: json['report_id'] as String,
    postId: json['post_id'] as String,
    reporterId: json['reporter_id'] as String,
    reason: json['reason'] as String,
    details: json['details'] as String?,
    status: json['status'] as String? ?? 'pending',
    createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    reviewNote: json['review_note'] as String?,
    postCaption: json['post_caption'] as String?,
    rightsOwner: json['rights_owner'] as String?,
    rightsHolderName: json['rights_holder_name'] as String?,
    postAuthorId: json['post_author_id']?.toString(),
    authorUsername: json['author_username'] as String?,
    authorDisplayName: json['author_display_name'] as String?,
  );
}

class AdminModerationItem {
  const AdminModerationItem({
    required this.type, required this.id, required this.authorId,
    required this.username, required this.displayName, required this.caption,
    required this.mediaType, required this.createdAt, required this.bio,
    required this.isVerified, this.mediaUrl, this.coverUrl, this.avatarUrl,
  });
  final String type, id, authorId;
  final String? username, displayName, caption, mediaType, bio;
  final DateTime? createdAt;
  final bool isVerified;
  final String? mediaUrl, coverUrl, avatarUrl;

  factory AdminModerationItem.fromJson(Map<String, dynamic> json) => AdminModerationItem(
    type: json['content_type']?.toString() ?? 'post',
    id: json['content_id']?.toString() ?? '',
    authorId: json['author_id']?.toString() ?? '',
    username: json['username'] as String?,
    displayName: json['display_name'] as String?,
    caption: json['caption'] as String?,
    mediaType: json['media_type'] as String?,
    createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    bio: json['bio'] as String?,
    isVerified: json['is_verified'] as bool? ?? false,
    mediaUrl: json['media_url'] as String?,
    coverUrl: json['cover_url'] as String?,
    avatarUrl: json['avatar_url'] as String?,
  );
}

class AdminCommunitySummary {
  const AdminCommunitySummary({
    required this.id,
    required this.kind,
    required this.title,
    required this.ownerId,
    required this.ownerUsername,
    required this.ownerDisplayName,
    required this.createdAt,
    required this.isPublic,
    required this.slug,
    required this.description,
    required this.memberCount,
    required this.isBlocked,
    required this.blockReason,
  });

  final String id, kind, title;
  final String? ownerId, ownerUsername, ownerDisplayName, slug, description, blockReason;
  final DateTime? createdAt;
  final bool isPublic, isBlocked;
  final int memberCount;

  factory AdminCommunitySummary.fromJson(Map<String, dynamic> json) =>
      AdminCommunitySummary(
        id: json['conversation_id']?.toString() ?? '',
        kind: json['kind']?.toString() ?? 'group',
        title: json['title']?.toString() ?? 'بدون نام',
        ownerId: json['owner_id']?.toString(),
        ownerUsername: json['owner_username'] as String?,
        ownerDisplayName: json['owner_display_name'] as String?,
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
        isPublic: json['is_public'] as bool? ?? false,
        slug: json['slug'] as String?,
        description: json['description'] as String?,
        memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
        isBlocked: json['is_blocked'] as bool? ?? false,
        blockReason: json['block_reason'] as String?,
      );
}

class AdminService {
  AdminService._();
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<bool> isCurrentUserAdmin() async =>
      await _client.rpc('is_current_user_admin') == true;

  static Future<AdminDashboardStats> loadStats() async {
    final result = await _client.rpc('admin_dashboard_stats');
    if (result is! Map) throw const FormatException('Invalid admin stats');
    return AdminDashboardStats.fromJson(Map<String, dynamic>.from(result));
  }

  static Future<List<AdminUserSummary>> loadUsers({String search = ''}) async {
    final result = await _client.rpc('admin_list_users', params: {
      'p_search': search.trim().isEmpty ? null : search.trim(),
      'p_limit': 50,
      'p_offset': 0,
    });
    if (result is! List) return [];
    final users = <AdminUserSummary>[];
    for (final row in result) {
      final data = Map<String, dynamic>.from(row as Map);
      final avatarPath = data['avatar_path'] as String?;
      if (avatarPath != null && avatarPath.isNotEmpty) {
        try {
          data['avatar_url'] = await _client.storage.from('avatars').createSignedUrl(avatarPath, 900);
        } catch (_) {}
      }
      users.add(AdminUserSummary.fromJson(data));
    }
    return users;
  }

  static Future<Map<String, dynamic>> loadUserDetail(String userId) async {
    final result = await _client.rpc('admin_user_detail', params: {'p_user_id': userId});
    if (result is! Map) throw const FormatException('Invalid admin user detail');
    return Map<String, dynamic>.from(result);
  }

  static Future<List<AdminCommunitySummary>> loadCommunities({
    String kind = 'all',
    String search = '',
    int offset = 0,
  }) async {
    final result = await _client.rpc('admin_list_communities', params: {
      'p_kind': kind,
      'p_search': search.trim().isEmpty ? null : search.trim(),
      'p_limit': 50,
      'p_offset': offset,
    });
    if (result is! List) return [];
    return result.map((row) => AdminCommunitySummary.fromJson(
      Map<String, dynamic>.from(row as Map),
    )).toList();
  }

  static Future<void> moderateCommunity({
    required String conversationId,
    required String action,
    String? message,
  }) async {
    await _client.rpc('admin_moderate_community', params: {
      'p_conversation_id': conversationId,
      'p_action': action,
      'p_message': message,
    });
  }

  static Future<List<AdminModerationItem>> loadModerationContent({String type = 'all', int offset = 0}) async {
    final result = await _client.rpc('admin_list_moderation_content', params: {
      'p_content_type': type, 'p_limit': 50, 'p_offset': offset,
    });
    if (result is! List) return [];
    final items = <AdminModerationItem>[];
    for (final row in result) {
      final data = Map<String, dynamic>.from(row as Map);
      final mediaPath = data['media_path'] as String?;
      final coverPath = data['cover_path'] as String?;
      final avatarPath = data['avatar_path'] as String?;
      if (mediaPath != null && mediaPath.isNotEmpty) {
        try {
          data['media_url'] = await _client.storage.from('post-media').createSignedUrl(mediaPath, 900);
        } catch (_) {}
      }
      if (coverPath != null && coverPath.isNotEmpty) {
        try {
          data['cover_url'] = await _client.storage.from('post-media').createSignedUrl(coverPath, 900);
        } catch (_) {}
      }
      if (avatarPath != null && avatarPath.isNotEmpty) {
        try {
          data['avatar_url'] = await _client.storage.from('avatars').createSignedUrl(avatarPath, 900);
        } catch (_) {}
      }
      items.add(AdminModerationItem.fromJson(data));
    }
    return items;
  }

  static Future<void> moderateContent({
    required String action, String? userId, String? postId,
    String? message, String? duration,
  }) async {
    final response = await _client.functions.invoke('admin-moderate-content', body: {
      'action': action, 'user_id': userId, 'post_id': postId,
      'message': message, 'duration': duration,
    });
    if (response.status < 200 || response.status >= 300 ||
        response.data is! Map || response.data['success'] != true) {
      throw StateError('Moderation action failed');
    }
  }

  static Future<List<AdminPostReport>> loadReports() async {
    final result = await _client.rpc('admin_list_post_reports_detailed', params: {
      'p_limit': 50, 'p_offset': 0,
    });
    if (result is! List) return [];
    return result.map((row) =>
      AdminPostReport.fromJson(Map<String, dynamic>.from(row as Map))).toList();
  }

  static Future<List<Map<String, dynamic>>> loadMessageReports() async {
    final result = await _client.rpc('admin_list_message_reports', params: {'p_limit': 100, 'p_offset': 0});
    if (result is! List) return [];
    return result.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  static Future<List<AdminAuditLog>> loadAuditLogs({int offset = 0}) async {
    final result = await _client.rpc('admin_list_audit_logs', params: {
      'p_limit': 100, 'p_offset': offset,
    });
    if (result is! List) return [];
    return result.map((row) => AdminAuditLog.fromJson(
      Map<String, dynamic>.from(row as Map))).toList();
  }

  static Future<void> deleteUser(String userId) async {
    final response = await _client.functions.invoke(
      'admin-delete-user',
      body: {'user_id': userId},
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError('User deletion failed');
    }
    final data = response.data;
    if (data is Map && data['success'] == true) return;
    throw StateError('User deletion was not confirmed by the server');
  }

  static Future<void> setVerified(String userId, bool verified, {String? note}) async {
    await _client.rpc('admin_set_verified', params: {
      'p_user_id': userId, 'p_verified': verified, 'p_note': note,
    });
  }

  static Future<List<Map<String, dynamic>>> loadVerificationRequests({String status = 'pending'}) async {
    final rows = await _client.from('verification_requests')
      .select('id,user_id,applicant_type,category,legal_name,phone,organization_registration_number,organization_national_id,public_links,explanation,evidence_paths,status,review_note,created_at')
      .eq('status', status).order('created_at', ascending: true).limit(100);
    final result = rows.map((row) => Map<String, dynamic>.from(row)).toList();
    if (result.isEmpty) return result;
    final ids = result.map((r) => r['user_id'] as String).toSet().toList();
    final profiles = await _client.from('profiles')
      .select('id,username,display_name').inFilter('id', ids);
    final byId = {for (final p in profiles) p['id'] as String: Map<String,dynamic>.from(p)};
    for (final row in result) {
      row['profile'] = byId[row['user_id']];
      final signed = <String>[];
      for (final path in (row['evidence_paths'] as List? ?? const [])) {
        try { signed.add(await _client.storage.from('verification-evidence').createSignedUrl(path.toString(), 900)); } catch (_) {}
      }
      row['evidence_urls'] = signed;
    }
    return result;
  }

  static Future<void> reviewVerification(String requestId, String status, {String? note}) async {
    await _client.rpc('admin_review_verification', params: {
      'p_request_id': requestId, 'p_status': status, 'p_note': note,
    });
  }

  static Future<String> openSupportForUser(String userId) async {
    final result = await _client.rpc('admin_get_or_create_support_conversation', params: {'p_user_id': userId});
    return result.toString();
  }

  static Future<void> reviewMessageReport(String id, String status) async {
    await _client.rpc('admin_review_message_report', params: {
      'p_report_id': id, 'p_status': status, 'p_review_note': null,
    });
  }

  static Future<void> reviewReport(String id, String status) async {
    await _client.rpc('admin_review_post_report', params: {
      'p_report_id': id, 'p_status': status, 'p_review_note': null,
    });
  }
}

class AdminAuditLog {
  const AdminAuditLog({
    required this.id, required this.actorId, required this.action,
    required this.metadata, required this.createdAt,
    this.actorUsername, this.actorDisplayName, this.targetUserId,
    this.targetUsername, this.targetDisplayName,
  });
  final String id, actorId, action;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;
  final String? actorUsername, actorDisplayName, targetUserId, targetUsername, targetDisplayName;

  factory AdminAuditLog.fromJson(Map<String, dynamic> json) => AdminAuditLog(
    id: json['log_id']?.toString() ?? '',
    actorId: json['actor_id']?.toString() ?? '',
    action: json['action']?.toString() ?? '',
    metadata: json['metadata'] is Map ? Map<String, dynamic>.from(json['metadata'] as Map) : const {},
    createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    actorUsername: json['actor_username'] as String?,
    actorDisplayName: json['actor_display_name'] as String?,
    targetUserId: json['target_user_id']?.toString(),
    targetUsername: json['target_username'] as String?,
    targetDisplayName: json['target_display_name'] as String?,
  );
}
