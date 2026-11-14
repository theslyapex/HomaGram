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
  final String? username, displayName;
  final DateTime? createdAt, bannedUntil;
  final bool isBanned;

  factory AdminUserSummary.fromJson(Map<String, dynamic> json) => AdminUserSummary(
    id: json['user_id'] as String,
    username: json['username'] as String?,
    displayName: json['display_name'] as String?,
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
  });
  final String id, postId, reporterId, reason, status;
  final String? details, reviewNote, postCaption;
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
    return result.map((row) =>
      AdminUserSummary.fromJson(Map<String, dynamic>.from(row as Map))).toList();
  }

  static Future<Map<String, dynamic>> loadUserDetail(String userId) async {
    final result = await _client.rpc('admin_user_detail', params: {'p_user_id': userId});
    if (result is! Map) throw const FormatException('Invalid admin user detail');
    return Map<String, dynamic>.from(result);
  }

  static Future<List<AdminPostReport>> loadReports() async {
    final result = await _client.rpc('admin_list_post_reports', params: {
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
